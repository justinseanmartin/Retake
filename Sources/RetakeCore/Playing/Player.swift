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
    /// Waits, once the app has turned, for the rotation the device draws to finish, from the
    /// device's screen. Nil, as for composing or a dry run, which open no screen, waits instead
    /// until `rotationTime` after the turn was asked for.
    public var rotated: (@Sendable () async -> Void)? = nil
    /// Takes a `capture` step's still, by its name, of the screen as it is now. Nil, as for
    /// composing or a dry run, which open no screen to capture, passes over each capture.
    public var capturing: (@Sendable (String) async throws(RetakeError) -> Void)? = nil
    /// The device's screen in points, held upright: what a step's share of the screen is of, turned
    /// as the device faces. Nil when it isn't known, and a step that gives a share fails.
    public var screen: CGSize? = nil
    /// Told what's on screen once `beforeSteps` is done, just before the first step, and when it
    /// was read: for a take's step log, which edits find elements in before the first step has
    /// ended. Nil reads nothing, as composing needs nothing; a screen that can't be read is skipped.
    public var readBeforeSteps: (@Sendable (_ elements: [ScreenElement], _ at: Date) -> Void)? = nil

    /// How long an `orientation` step waits for the app to turn.
    public static let turnTimeout = 5.0
    /// Seconds from asking for a turn until the device has drawn it, with no screen to watch it on:
    /// an iPad Pro (11-inch) (3rd generation)'s rotation began 0.34 to 0.64 s after it was asked
    /// for and moved its last 0.82 to 1.35 s after.
    public static let rotationTime = 1.5
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
        for (index, step) in scene.setup.enumerated() where !step.isSkipped {
            let played = Played(isSetup: true, number: index + 1, count: scene.setup.count, step: step)
            try await play(played, in: name, orientation: &orientation, on: driver)
        }
        try await beforeSteps()
        if let readBeforeSteps, let elements = try? await driver.elements() { readBeforeSteps(elements, Date()) }
        for (index, step) in scene.steps.enumerated() where !step.isSkipped {
            let played = Played(number: index + 1, count: scene.steps.count, step: step, of: scene)
            try await play(played, in: name, orientation: &orientation, on: driver)
        }
    }

    /// Plays one step, then waits out its hold: a tap's from when it was sent, any other step's
    /// from when it ended.
    @ButtonHeistActor
    func play(_ played: Played, in scene: String, orientation: inout SceneFile.Orientation, on driver: some AppDriver) async throws(RetakeError) {
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
            case .capture(let name):
                try await capturing?(name)
            case .pause:
                break
            }
        } catch {
            if Self.ambiguity(error.message) != nil {
                // Read now, for the matches to be listed as Retake names them.
                let elements = try? await driver.elements()
                let ambiguous = Self.ambiguity(error.message, naming: Self.heistTarget(of: played.step.action), on: elements) ?? error.message
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
        if let hold = played.step.hold {
            // A tap's hold runs from when it was sent, as the touch lands then: The Button Heist's
            // reply waits for the screen to settle, which would otherwise stretch every gap between
            // taps by however long the app animates.
            let remaining = played.step.action?.key == "tap" ? hold - (now() - sentAt) : hold
            if remaining > 0 { await pause(remaining) }
        }
    }

    /// Where a tap at a point, or a drag, touches and lifts, in points: a share of the screen as the
    /// device faces, and a drag's end on an element where the screen has it now, read just before
    /// the drag, moved by its offset. A drag that starts on an element with no offset is touched where
    /// The Button Heist finds it, but its start is found here too, for the step log.
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
                case .element(let target, let offset):
                    if elements == nil { elements = try await driver.elements() }
                    return try Self.point(of: target, in: elements!, movedBy: offset)
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

    static func point(of target: ElementTarget, in elements: [ScreenElement], movedBy offset: SpotOffset = .none) throws(RetakeError) -> Point {
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
        let frame = found.frame!
        let point = found.activationPoint ?? Point(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        return offset.moving(point, size: (frame.width, frame.height))
    }

    /// The Button Heist's failure for an element that matches several, said in a scene's terms, or
    /// nil for any other failure. Given the step's `target` and the `screen` read after it failed,
    /// each element that matches is listed as `compose` shows it, traits and hint too, with the
    /// shortest name that picks it out, `occurrence` only where nothing else does. Where the screen
    /// couldn't be read, or Retake's matches don't come to The Button Heist's count, its own list
    /// of the matches is kept, without its advice, which counts from 0 where `occurrence` counts
    /// from 1.
    static func ambiguity(_ message: String, naming target: ElementTarget? = nil, on screen: [ScreenElement]? = nil) -> String? {
        guard let match = message.firstMatch(of: /(\d+)(\+?) elements match: .*— use ordinal/), let counted = Int(match.1) else { return nil }
        func lead(_ count: String, _ range: String) -> String {
            "\(count) elements match it, so which is meant isn't clear. Name it more closely, by its traits, "
                + "identifier, value or hint as well, or as a last resort give \"occurrence\" (\(range), in the order VoiceOver reads the screen):"
        }
        if var target, let screen {
            target.occurrence = nil
            let matches = screen.indices.filter { target.matches(screen[$0]) }
            if matches.count > 1, match.2.isEmpty ? matches.count == counted : matches.count >= counted {
                let lines = matches.map { index in
                    "  \(screen[index].line)  ·  " + (ElementTarget.naming(index, in: screen).map { JSONWriter.compact($0.json) } ?? "(nothing to name it by)")
                }
                return lead("\(matches.count)", "1 to \(matches.count)") + "\n" + lines.joined(separator: "\n")
            }
        }
        let candidates = message.split(separator: "\n").dropFirst().joined(separator: "\n")
        return lead(String(match.1) + String(match.2), match.2.isEmpty ? "1 to \(match.1)" : "from 1")
            + (candidates.isEmpty ? "" : "\n" + candidates)
    }

    /// The element a step has The Button Heist find, which it may find several of.
    static func heistTarget(of action: Step.Action?) -> ElementTarget? {
        switch action {
        case .tapElement(let target)?, .activate(let target)?, .waitFor(let target, _, _)?, .type(_, let target?)?: target
        case .drag(.element(let target, let offset), _, _)? where offset.isNone: target
        default: nil
        }
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
        let asked = now()
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
                if Self.hasSettled(frames, from: Self.frames(before), moving: now, before: moving) {
                    // The app lays itself out for the new orientation as the rotation starts, so
                    // its elements settle before the device has drawn the turn.
                    if let rotated {
                        await rotated()
                    } else if Self.rotationTime > self.now() - asked {
                        await pause(Self.rotationTime - (self.now() - asked))
                    }
                    return elements
                }
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

extension Player.Played {
    /// One of `scene`'s steps, not its setup, as it's played: a step that gives no hold of its own
    /// holds for the scene's `defaultHold`.
    init(number: Int, count: Int, step: Step, of scene: SceneFile) {
        var step = step
        step.hold = step.hold ?? scene.defaultHold
        self.init(isSetup: false, number: number, count: count, step: step)
    }
}
