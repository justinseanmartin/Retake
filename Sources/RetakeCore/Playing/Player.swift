import ButtonHeist
import Foundation
import ThePlans

/// What a scene's steps are played through: the app, reached by The Button Heist, and the device it
/// runs on. A seam, so playing is tested without either.
@ButtonHeistActor
public protocol AppDriver: AnyObject {
    /// Runs one step's plan in the app, failing (1) with what went wrong when it doesn't run.
    func run(_ plan: HeistPlan) async throws(RetakeError) -> StepEvidence
    /// Sends one direct command, for what a plan can't hold, failing (1) like `run`.
    func perform(_ command: HeistActionCommand) async throws(RetakeError) -> StepEvidence
    /// What's on screen now.
    func elements() async throws(RetakeError) -> [ScreenElement]
    /// Turns the device, returning once it's asked to, not once the app has turned.
    func turn(to orientation: SceneFile.Orientation) async throws(RetakeError)
}

/// Plays a scene's setup and steps, one plan per step, with each step's hold after it. See
/// Documentation/cli.md, "retake record".
public struct Player: Sendable {
    /// What playing a step is reported as, for printing.
    public enum Event: Sendable {
        case started(Played)
        case finished(Played, Timing)
        /// A scene starting, in a run of several: its name, and the take it'll be, unless it's
        /// only played.
        case scene(String, take: Int?)
        /// The app being launched on a set, in its state, once the scene is known to be playable.
        case launching(set: String, state: SetFile.State)
        /// Something said in passing, such as a launch tried again.
        case note(String)
        case warning(String)
    }

    /// A step as it's played: from the setup or the steps, its number in them from 1, and how many
    /// there are.
    public struct Played: Sendable {
        public var isSetup: Bool
        public var number: Int
        public var count: Int
        public var step: Step

        /// `step 3 of 10 (send)`, or `setup step 1 of 2`.
        public var name: String {
            let numbered = "\(isSetup ? "setup step" : "step") \(number) of \(count)"
            return step.id.map { "\(numbered) (\($0))" } ?? numbered
        }
    }

    /// When a step ran, as the Mac saw it, and what the device saw of it.
    public struct Timing: Sendable {
        /// When it was sent, and when its reply came, on the Mac's clock.
        public var sent: Date
        public var received: Date
        public var evidence: StepEvidence

        public var seconds: Double { received.timeIntervalSince(sent) }
    }

    /// Waits a number of seconds: a step's hold, or between looks at the screen.
    public var pause: @Sendable (Double) async -> Void
    /// Seconds on a clock that only goes forward.
    public var now: @Sendable () -> Double
    public var report: @Sendable (Event) -> Void
    /// Told which way an `orientation` step is about to turn the device, before it does: for the
    /// recorder, to store frames of the new shape facing the right way.
    public var turning: @Sendable (SceneFile.Orientation) -> Void = { _ in }

    /// How long an `orientation` step waits for the app to turn.
    public static let turnTimeout = 5.0
    /// How often an `orientation` step looks at the screen while it waits.
    public static let turnPollInterval = 0.1

    public init(
        pause: @escaping @Sendable (Double) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        report: @escaping @Sendable (Event) -> Void = { _ in },
    ) {
        self.pause = pause
        self.now = now
        self.report = report
    }

    /// Plays `scene`'s setup, then `beforeSteps`, such as starting the recording, then its steps,
    /// each with its hold. Fails at the first step that doesn't run, naming it.
    @ButtonHeistActor
    public func play(
        _ scene: SceneFile,
        named name: String,
        on driver: some AppDriver,
        beforeSteps: @ButtonHeistActor () async throws(RetakeError) -> Void = {},
    ) async throws(RetakeError) {
        var orientation = scene.orientation
        for (index, step) in scene.setup.enumerated() {
            let played = Played(isSetup: true, number: index + 1, count: scene.setup.count, step: step)
            try await play(played, in: name, orientation: &orientation, holding: true, on: driver)
        }
        try await beforeSteps()
        for (index, step) in scene.steps.enumerated() {
            // A step that gives no hold of its own holds for the scene's `defaultHold`.
            var step = step
            step.hold = step.hold ?? scene.defaultHold
            let played = Played(isSetup: false, number: index + 1, count: scene.steps.count, step: step)
            try await play(played, in: name, orientation: &orientation, holding: true, on: driver)
        }
    }

    @ButtonHeistActor
    func play(_ played: Played, in scene: String, orientation: inout SceneFile.Orientation, holding: Bool, on driver: some AppDriver) async throws(RetakeError) {
        report(.started(played))
        let sent = Date()
        var evidence = StepEvidence()
        do {
            switch try StepPlay.make(for: played.step) {
            case .heist(let plan):
                evidence = try await driver.run(plan)
            case .direct(let command):
                evidence = try await driver.perform(command)
            case .turn(let target):
                evidence.elements = try await turn(from: orientation, to: target, on: driver)
                orientation = target
            case .pause:
                break
            }
        } catch {
            if let ambiguous = Self.ambiguity(error.message) {
                throw RetakeError(.failed, "\(scene): \(played.name), \(played.step.summary), didn't run: \(ambiguous)")
            }
            // A wait that ran out says so; The Button Heist's account of it is its predicate's.
            if error.status == .failed, case .waitFor(let element, let gone, let timeout)? = played.step.action {
                let what = gone ? "\(element) was still on screen" : "\(element) wasn't on screen"
                throw RetakeError(.failed, "\(scene): \(played.name) failed: \(what) after \(Step.seconds(timeout)).")
            }
            throw RetakeError(error.status, "\(scene): \(played.name), \(played.step.summary), didn't run: \(error.message)")
        }
        report(.finished(played, Timing(sent: sent, received: Date(), evidence: evidence)))
        if holding, let hold = played.step.hold, hold > 0 { await pause(hold) }
    }

    /// The Button Heist's failure for an element that matches several, said in a scene's terms, or
    /// nil for any other failure. It counts its ordinal from 0, where a step's `occurrence` counts
    /// from 1, so its own advice would be off by one; its list of the matches is kept.
    static func ambiguity(_ message: String) -> String? {
        guard let match = message.firstMatch(of: /(\d+)(\+?) elements match: .*— use ordinal/) else { return nil }
        let count = String(match.1) + String(match.2)
        let candidates = message.split(separator: "\n").dropFirst().joined(separator: "\n")
        let range = match.2.isEmpty ? "1 to \(match.1)" : "from 1"
        return "\(count) elements match it, so which is meant isn't clear. Name it more closely, with its label, value "
            + "and identifier together, or give \"occurrence\" (\(range), in the order VoiceOver reads the screen):"
            + (candidates.isEmpty ? "" : "\n" + candidates)
    }

    /// Turns the device and waits for the app to turn with it: for what's on screen to have moved
    /// from where it was, and then to look the same twice running, so the app has finished laying
    /// itself out. The Button Heist doesn't report a turn as a change of screen, and doesn't say
    /// the screen's size. A turn to the way the device already faces needs no wait. Returns what's
    /// on screen once it has turned.
    @ButtonHeistActor
    func turn(from current: SceneFile.Orientation, to target: SceneFile.Orientation, on driver: some AppDriver) async throws(RetakeError) -> [ScreenElement] {
        let before = try await driver.elements()
        turning(target)
        try await driver.turn(to: target)
        guard target != current else { return before }
        let deadline = now() + Self.turnTimeout
        var last: [ScreenElement.Rect?]?
        while now() < deadline {
            let elements = try await driver.elements()
            let frames = Self.frames(elements)
            if frames != Self.frames(before), frames == last { return elements }
            last = frames
            await pause(Self.turnPollInterval)
        }
        throw RetakeError(
            .failed,
            "the app didn't turn to \(target.rawValue) within \(Step.seconds(Self.turnTimeout)); does it support \(target.rawValue)?",
        )
    }

    static func frames(_ elements: [ScreenElement]) -> [ScreenElement.Rect?] {
        elements.map(\.frame)
    }
}
