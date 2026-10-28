// The tooling SPI is only for what 0.7.1's public client can't do yet; see
// Documentation/records/2026-10-26-button-heist-asks.md, "Asks for after 0.7.1".
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation
import ThePlans
import TheScore

/// The app, reached through The Button Heist's public client over the device's CoreDevice tunnel,
/// and the device, turned with `devicectl`.
@ButtonHeistActor
public final class ButtonHeistDriver: AppDriver {
    private let heist: TheFence
    private let device: Device

    init(heist: TheFence, device: Device) {
        self.heist = heist
        self.device = device
    }

    /// How long to keep trying to reach the app after it's launched: its server can take a moment
    /// to start listening, and a first connection has failed once and then worked.
    public static let connectTimeout = 10.0

    /// Connects to the launched app, and runs `body` with a driver for it, disconnecting after.
    /// Fails (3) when the app can't be reached, or runs a different Button Heist; errors from
    /// `body` pass through as they are.
    public static func withApp<Value: Sendable>(
        _ app: LaunchedApp,
        _ body: @ButtonHeistActor (ButtonHeistDriver) async throws(RetakeError) -> Value,
    ) async throws(RetakeError) -> Value {
        let configuration: EnvironmentConfig
        do {
            configuration = try EnvironmentConfig.resolve(
                deviceFilter: app.endpoint, token: app.plan.token, connectionTimeout: 5, autoReconnect: false,
            )
        } catch {
            throw RetakeError(.environment, "Couldn't set up The Button Heist's connection to the app: \(error)")
        }
        let deadline = Date().addingTimeInterval(connectTimeout)
        while true {
            // Errors once connected are the body's, and end the session rather than retrying it.
            var outcome: Result<Value, RetakeError>?
            do {
                try await ButtonHeist.withSession(configuration) { heist in
                    let driver = ButtonHeistDriver(heist: heist, device: app.device)
                    _ = try await heist.captureInterface()
                    do throws(RetakeError) {
                        outcome = .success(try await body(driver))
                    } catch {
                        outcome = .failure(error)
                    }
                }
            } catch {
                let failure = connectionFailure(error)
                if failure.retryable, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }
                throw failure.error
            }
            guard let outcome else { throw RetakeError(.environment, "The Button Heist's session with the app ended before anything ran.") }
            return try outcome.get()
        }
    }

    /// What a failure to connect means for the command, and whether trying again could help.
    nonisolated static func connectionFailure(_ error: Error) -> (error: RetakeError, retryable: Bool) {
        let (code, message) = classify(error)
        return connectionFailure(code: code ?? .clientUnknown, message: message)
    }

    /// The Button Heist's code for an error, where it gives one, and its message.
    nonisolated static func classify(_ error: Error) -> (code: KnownFailureCode?, message: String) {
        guard let fence = error as? FenceError else { return (nil, error.localizedDescription) }
        switch fence {
        case .diagnostic(let failure): return (failure.details.code, failure.message)
        case .authFailed(let message): return (.authFailed, message)
        case .notConnected: return (.connectionNotConnected, fence.localizedDescription)
        case .actionTimeout: return (.requestTimeout, fence.localizedDescription)
        case .sessionLocked(let message): return (.sessionLocked, message)
        default: return (nil, fence.localizedDescription)
        }
    }

    nonisolated static func connectionFailure(code: KnownFailureCode, message: String) -> (error: RetakeError, retryable: Bool) {
        switch code {
        case .protocolMismatch:
            return (RetakeError(
                .environment,
                "The app runs a different Button Heist from this Retake's \(TheScore.buttonHeistVersion): "
                    + "embed it again with `retake embed` or `retake install`. (\(message))",
            ), false)
        case .authFailed, .tlsMissingToken:
            return (RetakeError(.environment, "The app refused Retake's connection: \(message)"), false)
        default:
            return (RetakeError(.environment, "Couldn't reach the app's Button Heist server: \(message)"), code.retryable || code.phase == .transport)
        }
    }

    public func run(_ plan: HeistPlan) async throws(RetakeError) -> StepEvidence {
        let result: HeistResult
        do {
            result = try await heist.run(plan, timeout: Self.timeout(for: plan))
        } catch {
            let (code, message) = Self.classify(error)
            let lost = code.map { $0.phase == .transport || $0 == .connectionNotConnected } ?? false
            throw RetakeError(lost ? .environment : .failed, message)
        }
        if case .failed = result.outcome {
            throw RetakeError(.failed, Self.failureMessage(result.steps))
        }
        return StepEvidence.from(encoded: result)
    }

    /// Through the tooling SPI's direct commands: a drag with a duration, which 0.7.1 refuses in a
    /// plan as not durable.
    public func perform(_ command: HeistActionCommand) async throws(RetakeError) -> StepEvidence {
        let response: FenceResponse
        do {
            let action = try JSONDecoder().decode(HeistValue.self, from: JSONEncoder().encode(command))
            let input = FenceCommandInput(command: .action, arguments: TheFence.CommandArgumentEnvelope(values: ["action": action]))
            response = try await heist.execute(heist.admit(input))
        } catch {
            let (code, message) = Self.classify(error)
            let lost = code.map { $0.phase == .transport || $0 == .connectionNotConnected } ?? false
            throw RetakeError(lost ? .environment : .failed, message)
        }
        if response.isFailure {
            if case .error(let failure) = response { throw RetakeError(.failed, failure.message) }
            throw RetakeError(.failed, response.humanFormatted())
        }
        guard case .action(let result, _) = response else { return StepEvidence() }
        return StepEvidence.from(encoded: result)
    }

    /// How far the device's clock is ahead of the Mac's, in seconds: from when it stamped a reading
    /// of the screen against the middle of the round trip that asked for it, the quickest of three,
    /// so it's off by at most half that round trip.
    public func clockOffset() async throws(RetakeError) -> Double {
        var best: (roundTrip: Double, offset: Double)?
        for _ in 0..<3 {
            let sent = Date()
            let stamped: Date
            do {
                stamped = try await heist.captureInterface().timestamp
            } catch {
                throw RetakeError(.failed, "Couldn't read the screen: \(error)")
            }
            let received = Date()
            let roundTrip = received.timeIntervalSince(sent)
            let offset = stamped.timeIntervalSince(sent.addingTimeInterval(roundTrip / 2))
            if best.map({ roundTrip < $0.roundTrip }) ?? true { best = (roundTrip, offset) }
        }
        return best!.offset
    }

    /// Long enough for a wait's own timeout to be what ends it, with room for the round trip.
    static func timeout(for plan: HeistPlan) -> HeistTimeout {
        let waits = plan.body.compactMap { step -> Double? in
            guard case .wait(let wait) = step else { return nil }
            return wait.timeout.seconds
        }
        let seconds = (waits.max() ?? 0) + HeistTimeout.default.seconds
        return (try? HeistTimeout.seconds(seconds)) ?? .default
    }

    /// What the first failed step observed, and what it expected, as The Button Heist says them.
    static func failureMessage(_ steps: [HeistExecutionStepResult]) -> String {
        for step in steps {
            if step.status == .failed, let failure = step.failure {
                return failure.expected.map { "\(failure.observed) (expected \($0))" } ?? failure.observed
            }
            if step.status == .failed || !step.children.isEmpty {
                let nested = failureMessage(step.children)
                if !nested.isEmpty { return nested }
            }
        }
        return steps.isEmpty ? "" : "The Button Heist reported it failed."
    }

    public func elements() async throws(RetakeError) -> [ScreenElement] {
        do {
            return try await heist.captureInterface().projectedElements.map(Self.element)
        } catch {
            throw RetakeError(.failed, "Couldn't read the screen: \(error)")
        }
    }

    nonisolated static func element(_ element: HeistElement) -> ScreenElement {
        let assertable = element.semantics.assertable
        var frame: ScreenElement.Rect?
        var activationPoint: Point?
        if case .onscreen(let evidence, let activation) = element.geometry.screen {
            if let rect = evidence.rect {
                frame = ScreenElement.Rect(x: rect.x.value, y: rect.y.value, width: rect.width.value, height: rect.height.value)
            }
            if let point = activation.point {
                activationPoint = Point(x: point.x, y: point.y)
            }
        }
        return ScreenElement(
            label: assertable.label, value: assertable.value, identifier: assertable.identifier, hint: assertable.hint,
            traits: assertable.traits.map(\.rawValue).sorted(), frame: frame, activationPoint: activationPoint,
        )
    }

    public func turn(to orientation: SceneFile.Orientation) async throws(RetakeError) {
        try Launcher.turn(device, to: orientation)
    }
}
