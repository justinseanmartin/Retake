import ButtonHeist
import Foundation
import ThePlans

/// What a scene's steps are played through: the app, reached by The Button Heist, and the device it
/// runs on. A seam, so playing is tested without either.
@ButtonHeistActor
public protocol AppDriver: AnyObject {
    /// Runs one step's plan in the app, failing (1) with what went wrong when it doesn't run.
    func run(_ plan: HeistPlan) async throws(RetakeError)
    /// Sends one direct command, for what a plan can't hold, failing (1) like `run`.
    func perform(_ command: HeistActionCommand) async throws(RetakeError)
    /// What's on screen now.
    func elements() async throws(RetakeError) -> [ScreenElement]
    /// Turns the device, returning once it's asked to, not once the app has turned.
    func turn(to orientation: SceneFile.Orientation) async throws(RetakeError)
}

/// Plays a scene's setup and steps, one plan per step, with each step's hold after it. See
/// docs/cli.md, "retake rehearse" and "retake record".
public struct Player: Sendable {
    /// What playing a step is reported as, for printing.
    public enum Event: Sendable {
        case started(Played)
        case finished(Played, seconds: Double)
        case inspected(Played, [ScreenElement])
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

    /// Waits a number of seconds: a step's hold, or between looks at the screen.
    public var pause: @Sendable (Double) async -> Void
    /// Seconds on a clock that only goes forward.
    public var now: @Sendable () -> Double
    public var report: @Sendable (Event) -> Void

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

    /// Plays `scene`'s setup, then its steps from `from` (numbered from 1), the steps before it
    /// without their holds. Fails at the first step that doesn't run, naming it.
    @ButtonHeistActor
    public func play(_ scene: SceneFile, named name: String, from: Int = 1, on driver: some AppDriver) async throws(RetakeError) {
        guard (1...scene.steps.count).contains(from) else {
            throw RetakeError(.usage, "--from \(from) is past \(name)'s last step, \(scene.steps.count).")
        }
        var orientation = scene.orientation
        for (index, step) in scene.setup.enumerated() {
            let played = Played(isSetup: true, number: index + 1, count: scene.setup.count, step: step)
            try await play(played, in: name, orientation: &orientation, holding: true, on: driver)
        }
        for (index, step) in scene.steps.enumerated() {
            let played = Played(isSetup: false, number: index + 1, count: scene.steps.count, step: step)
            try await play(played, in: name, orientation: &orientation, holding: index + 1 >= from, on: driver)
        }
    }

    @ButtonHeistActor
    func play(_ played: Played, in scene: String, orientation: inout SceneFile.Orientation, holding: Bool, on driver: some AppDriver) async throws(RetakeError) {
        report(.started(played))
        let started = now()
        var inspected: [ScreenElement]?
        do {
            switch try StepPlay.make(for: played.step) {
            case .heist(let plan):
                try await driver.run(plan)
            case .direct(let command):
                try await driver.perform(command)
            case .turn(let target):
                try await turn(from: orientation, to: target, on: driver)
                orientation = target
            case .inspect:
                inspected = try await driver.elements()
            case .pause:
                break
            }
        } catch {
            // A wait that ran out says so; The Button Heist's account of it is its predicate's.
            if error.status == .failed, case .waitFor(let element, let gone, let timeout)? = played.step.action {
                let what = gone ? "\(element) was still on screen" : "\(element) wasn't on screen"
                throw RetakeError(.failed, "\(scene): \(played.name) failed: \(what) after \(Step.seconds(timeout)).")
            }
            throw RetakeError(error.status, "\(scene): \(played.name), \(played.step.summary), didn't run: \(error.message)")
        }
        report(.finished(played, seconds: now() - started))
        if let inspected { report(.inspected(played, inspected)) }
        if holding, played.step.hold > 0 { await pause(played.step.hold) }
    }

    /// Turns the device and waits for the app to turn with it: for what's on screen to have moved
    /// from where it was, and then to look the same twice running, so the app has finished laying
    /// itself out. The Button Heist doesn't report a turn as a change of screen, and doesn't say
    /// the screen's size. A turn to the way the device already faces needs no wait.
    @ButtonHeistActor
    func turn(from current: SceneFile.Orientation, to target: SceneFile.Orientation, on driver: some AppDriver) async throws(RetakeError) {
        let before = Self.frames(try await driver.elements())
        try await driver.turn(to: target)
        guard target != current else { return }
        let deadline = now() + Self.turnTimeout
        var last: [ScreenElement.Rect?]?
        while now() < deadline {
            let frames = Self.frames(try await driver.elements())
            if frames != before, frames == last { return }
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
