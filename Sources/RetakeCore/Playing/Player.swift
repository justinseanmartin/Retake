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
        /// A scene starting, in a run of several: its name, and whether it's recorded or only played.
        case scene(String, recording: Bool)
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
    /// The device's screen in points, held upright: what a step's share of the screen is of, turned
    /// as the device faces. Nil when it isn't known, and a step that gives a share fails.
    public var screen: CGSize? = nil
    /// Told what's on screen once `beforeSteps` is done, just before the first step, and when it
    /// was read: for a take's step log, which edits find elements in before the first step has
    /// ended. Nil reads nothing, as composing needs nothing; a screen that can't be read is skipped.
    public var readBeforeSteps: (@Sendable (_ elements: [ScreenElement], _ at: Date) -> Void)? = nil

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
        if let readBeforeSteps, let elements = try? await driver.elements() { readBeforeSteps(elements, Date()) }
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
        // What typing is checked against: whether anything on screen changes. Only returns aren't
        // checked, since a field that doesn't handle return ignores it, harmlessly, changing nothing.
        var before: [ScreenElement]?
        if case .type(let text, _)? = played.step.action, text.contains(where: { $0 != "\n" }) {
            before = try? await driver.elements()
        }
        report(.started(played))
        let sent = Date()
        let sentAt = now()
        var evidence = StepEvidence()
        do {
            let (touch, end) = try await points(for: played.step.action, facing: orientation, on: driver)
            defer { (evidence.touched, evidence.lifted) = (evidence.touched ?? touch, end) }
            switch try StepPlay.make(for: played.step, touch: touch, end: end) {
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
        if let before, try await !typed(since: before, after: evidence.elements, on: driver) {
            throw RetakeError(
                .failed,
                "\(scene): \(played.name), \(played.step.summary), went nowhere: nothing on screen changed, not even the field's value or whether it's being edited. Is the field still the one being typed in?",
            )
        }
        report(.finished(played, Timing(sent: sent, received: Date(), evidence: evidence)))
        if holding, let hold = played.step.hold {
            // A tap's hold runs from when it was sent, as the touch lands then: The Button Heist's
            // reply waits for the screen to settle, which would otherwise stretch every gap between
            // taps by however long the app animates.
            let remaining = played.step.action?.key == "tap" ? hold - (now() - sentAt) : hold
            if remaining > 0 { await pause(remaining) }
        }
    }

    /// Where a tap at a point, or a drag, touches and lifts, in points: a share of the screen as the
    /// device faces, and a drag's end on an element where the screen has it now, read just before
    /// the drag. A drag that starts on an element is touched where The Button Heist finds it, but its
    /// start is found here too, for the step log.
    @ButtonHeistActor
    func points(for action: Step.Action?, facing orientation: SceneFile.Orientation, on driver: some AppDriver) async throws(RetakeError) -> (touch: Point?, end: Point?) {
        let facing = screen.map { orientation.isLandscape ? CGSize(width: $0.height, height: $0.width) : $0 }
        func onScreen(_ position: Position) throws(RetakeError) -> Point {
            guard let point = position.point(on: facing) else {
                throw RetakeError(.environment, "\(position) is a share of the screen, and the device's screen size isn't known")
            }
            return point
        }
        switch action {
        case .tapPoint(let position)?:
            return (try onScreen(position), nil)
        case .drag(let from, let to, _)?:
            var elements: [ScreenElement]?
            func find(_ spot: Spot) async throws(RetakeError) -> Point {
                switch spot {
                case .position(let position): return try onScreen(position)
                case .element(let target):
                    if elements == nil { elements = try await driver.elements() }
                    return try Self.point(of: target, in: elements!)
                }
            }
            return (try await find(from), try await find(to))
        default:
            return (nil, nil)
        }
    }

    /// The activation point of the one element on screen `target` names.
    /// Whether typing changed anything on screen since `before`: in the reading the step ended
    /// with, or, to give the app a moment, one a little later.
    @ButtonHeistActor
    func typed(since before: [ScreenElement], after: [ScreenElement]?, on driver: some AppDriver) async throws(RetakeError) -> Bool {
        if let after, Self.changed(before, after) { return true }
        await pause(Self.typingSettles)
        return Self.changed(before, try await driver.elements())
    }

    /// Seconds to wait for typing to show before deciding it went nowhere.
    static let typingSettles = 0.3

    /// Whether anything VoiceOver could tell apart changed between two readings: which elements
    /// there are, or any one's label, value, identifier, hint or traits. A field's value changes as
    /// it's typed into, through any formatter, and a secure field's as its dots; a field being
    /// typed in has `isEditing` until return ends it; and a control that shows its input somewhere
    /// else changes that. Frames are left out, since the keyboard moves things whether or not
    /// anything was typed.
    static func changed(_ before: [ScreenElement], _ after: [ScreenElement]) -> Bool {
        func key(_ element: ScreenElement) -> String {
            [element.label ?? "", element.value ?? "", element.identifier ?? "", element.hint ?? "", element.traits.sorted().joined(separator: ",")]
                .joined(separator: "\u{1F}")
        }
        return before.map(key).sorted() != after.map(key).sorted()
    }

    static func point(of target: ElementTarget, in elements: [ScreenElement]) throws(RetakeError) -> Point {
        let matches = elements.filter { target.matches($0) && $0.frame != nil }
        let found: ScreenElement
        if let occurrence = target.occurrence {
            guard matches.indices.contains(occurrence - 1) else {
                throw RetakeError(.failed, "\(matches.count) element\(matches.count == 1 ? "" : "s") on screen \(matches.count == 1 ? "matches" : "match") \(target), so there's no occurrence \(occurrence)")
            }
            found = matches[occurrence - 1]
        } else {
            guard !matches.isEmpty else { throw RetakeError(.failed, "\(target) isn't on screen") }
            guard matches.count == 1 else {
                throw RetakeError(.failed, "\(matches.count) elements on screen match \(target); name it more closely, or give occurrence, from 1 to \(matches.count)")
            }
            found = matches[0]
        }
        if let point = found.activationPoint { return point }
        let frame = found.frame!
        return Point(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    /// The Button Heist's failure for an element that matches several, said in a scene's terms, or
    /// nil for any other failure. It counts its ordinal from 0, where a step's `occurrence` counts
    /// from 1, so its own advice would be off by one; its list of the matches is kept.
    static func ambiguity(_ message: String) -> String? {
        guard let match = message.firstMatch(of: /(\d+)(\+?) elements match: .*— use ordinal/) else { return nil }
        let count = String(match.1) + String(match.2)
        let candidates = message.split(separator: "\n").dropFirst().joined(separator: "\n")
        let range = match.2.isEmpty ? "1 to \(match.1)" : "from 1"
        return "\(count) elements match it, so which is meant isn't clear. Name it more closely, by its traits, "
            + "identifier, value or hint as well, or as a last resort give \"occurrence\" (\(range), in the order VoiceOver reads the screen):"
            + (candidates.isEmpty ? "" : "\n" + candidates)
    }

    /// Turns the device and waits for the app to turn with it: for what's on screen to have moved
    /// from where it was, and then to settle, so the app has finished laying itself out. Settled is
    /// nothing moving from one look to the next, or only a few elements that were moving the look
    /// before too, such as a looping animation, which never settles; and something else must have
    /// moved since before the turn, so an animation alone doesn't pass for one. The Button Heist
    /// doesn't report a turn as a change of screen, and doesn't say the screen's size. A turn to the
    /// way the device already faces needs no wait. Returns what's on screen once it has turned.
    @ButtonHeistActor
    func turn(from current: SceneFile.Orientation, to target: SceneFile.Orientation, on driver: some AppDriver) async throws(RetakeError) -> [ScreenElement] {
        let before = try await driver.elements()
        turning(target)
        try await driver.turn(to: target)
        guard target != current else { return before }
        let deadline = now() + Self.turnTimeout
        var last: [ScreenElement.Rect?]?
        var moving: Set<Int>?
        while now() < deadline {
            let elements = try await driver.elements()
            let frames = Self.frames(elements)
            if let last, last.count == frames.count {
                let now = Set(frames.indices.filter { frames[$0] != last[$0] })
                if Self.hasSettled(frames, from: Self.frames(before), moving: now, before: moving) { return elements }
                moving = now
            } else {
                moving = nil
            }
            last = frames
            await pause(Self.turnPollInterval)
        }
        throw RetakeError(
            .failed,
            "the app didn't turn to \(target.rawValue) within \(Step.seconds(Self.turnTimeout)); does it support \(target.rawValue)?",
        )
    }

    /// Whether `frames`, whose elements at `moving` moved since the last look, have settled after a
    /// turn from `before`, those at `earlier` having moved the look before that.
    static func hasSettled(_ frames: [ScreenElement.Rect?], from before: [ScreenElement.Rect?], moving: Set<Int>, before earlier: Set<Int>?) -> Bool {
        let animating = moving.isEmpty || (moving.count * 3 <= frames.count && earlier.map(moving.isSubset(of:)) == true)
        guard animating else { return false }
        if before.count != frames.count { return true }
        return frames.indices.contains { !moving.contains($0) && frames[$0] != before[$0] }
    }

    static func frames(_ elements: [ScreenElement]) -> [ScreenElement.Rect?] {
        elements.map(\.frame)
    }
}
