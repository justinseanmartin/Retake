import ButtonHeist
import Foundation
@testable import RetakeCore
import ThePlans
import Testing

/// The app as a list of what it was asked to do, with screens to show after each turn.
@ButtonHeistActor
final class FakeDriver: AppDriver {
    var done: [String] = []
    /// Fails the plan run at this index among runs, counted from 0.
    var failingRun: Int?
    var runs = 0
    /// What `elements()` returns, one after another; the last stays.
    var screens: [[ScreenElement]] = [[]]
    /// How long each run takes to answer, on `time`'s clock.
    var answering: (time: FakeTime, seconds: Double)?
    /// The screen each run ends with, as its evidence; none unless given.
    var ending: [ScreenElement]?

    func run(_ plan: HeistPlan) async throws(RetakeError) -> StepEvidence {
        defer { runs += 1 }
        done.append("run")
        if let answering { answering.time.now += answering.seconds }
        if runs == failingRun { throw RetakeError(.failed, "No match for: label=\"Send\"") }
        var evidence = StepEvidence()
        evidence.elements = ending
        return evidence
    }

    func perform(_ command: HeistActionCommand) async throws(RetakeError) -> StepEvidence {
        done.append("direct")
        return StepEvidence()
    }

    func elements() async throws(RetakeError) -> [ScreenElement] {
        done.append("look")
        return screens.count > 1 ? screens.removeFirst() : screens[0]
    }

    func turn(to orientation: SceneFile.Orientation) async throws(RetakeError) {
        done.append("turn \(orientation.rawValue)")
    }
}

/// The points each step's evidence gives, as the player reports them.
final class Touched: @unchecked Sendable {
    var points: [[Point?]] = []
}

extension Step.Action {
    static func tapPosition(x: Length, y: Length) -> Step.Action { .tapPoint(Position(x: x, y: y)) }
}

/// A clock that moves only when the player pauses, recording each pause.
final class FakeTime: @unchecked Sendable {
    var now = 0.0
    var pauses: [Double] = []

    func player() -> Player {
        Player(pause: { self.pauses.append($0); self.now += $0 }, now: { self.now })
    }
}

func screen(width: Double) -> [ScreenElement] {
    [ScreenElement(label: "New Note", frame: ScreenElement.Rect(x: width - 54, y: 32, width: 44, height: 44))]
}

@ButtonHeistActor
struct PlayerTests {
    let tap = Step(.tapElement(ElementTarget(label: "New Note")))

    @Test func setupThenStepsEachWithItsHold() async throws {
        let time = FakeTime()
        let driver = FakeDriver()
        let scene = SceneFile(
            setup: [Step(.activate(ElementTarget(label: "Library")), hold: 0.5)],
            steps: [Step(id: "a", tap.action, hold: 1), Step(id: "b", tap.action, hold: 2), Step(id: "c", tap.action, hold: 3)],
        )
        try await time.player().play(scene, named: "create-note", on: driver)
        #expect(driver.done == ["run", "run", "run", "run"])
        #expect(time.pauses == [0.5, 1, 2, 3])
    }

    @Test func typingThatChangesNothingOnScreenFailsButAnyChangeVoiceOverSeesPasses() async throws {
        let title = ScreenElement(value: "Title", traits: ["textEntry"])
        let type = SceneFile(steps: [Step(.type(text: "(555) 010", into: ElementTarget(value: "Title")))])
        func play(_ ending: [ScreenElement], later: [ScreenElement]? = nil) async -> (failure: String?, pauses: [Double]) {
            let time = FakeTime()
            let driver = FakeDriver()
            driver.screens = [[title]] + (later.map { [$0] } ?? [])
            driver.ending = ending
            do {
                try await time.player().play(type, named: "sign-up", on: driver)
                return (nil, time.pauses)
            } catch {
                return (error.message, time.pauses)
            }
        }
        // As when the field lost its focus before the keys came: the screen as it was.
        let nothing = await play([title], later: [title])
        #expect(nothing.failure?.contains("went nowhere: nothing on screen changed") == true, "\(nothing)")
        #expect(nothing.pauses == [Player.typingSettles], "looked again before failing")
        // Through a formatter, as a secure field's dots, or only `isEditing` gained or lost.
        #expect(await play([ScreenElement(value: "(555) 010-", traits: ["textEntry"])]).failure == nil)
        #expect(await play([ScreenElement(value: "•••••••••", traits: ["textEntry"])]).failure == nil)
        #expect(await play([ScreenElement(value: "Title", traits: ["isEditing", "textEntry"])]).failure == nil)
        // Shown a moment after the step ended, or somewhere else on screen.
        #expect(await play([title], later: [title, ScreenElement(label: "555 010", traits: ["staticText"])]).failure == nil)
        // Moved, as by the keyboard, and nothing else: still nowhere.
        #expect(await play([ScreenElement(value: "Title", traits: ["textEntry"], frame: .init(x: 0, y: 100, width: 300, height: 30))], later: [title]).failure != nil)
        // Only returns, which a field that doesn't handle return ignores, aren't checked.
        let time = FakeTime()
        let driver = FakeDriver()
        driver.screens = [[title]]
        driver.ending = [title]
        try await time.player().play(SceneFile(steps: [Step(.type(text: "\n", into: nil))]), named: "sign-up", on: driver)
        #expect(driver.done == ["run"], "not even looked at")
    }

    @Test func aStepWithNoHoldOfItsOwnHoldsForTheScenesDefault() async throws {
        let time = FakeTime()
        let scene = SceneFile(
            setup: [Step(.activate(ElementTarget(label: "Library")))],
            steps: [Step(id: "a", tap.action), Step(id: "b", tap.action, hold: 2), Step(id: "c", tap.action, hold: 0)],
            defaultHold: 0.5,
        )
        try await time.player().play(scene, named: "create-note", on: FakeDriver())
        #expect(time.pauses == [0.5, 2], "a's default; b's own; c's own 0; the setup's none")
    }

    @Test func aTapsHoldRunsFromWhenItWasSentAndADragsFromWhenItAnswered() async throws {
        let time = FakeTime()
        let driver = FakeDriver()
        driver.answering = (time, 0.4)
        let scene = SceneFile(steps: [
            Step(tap.action, hold: 1),
            Step(.drag(from: .point(x: 1, y: 2), to: .point(x: 3, y: 4), duration: 0.5), hold: 1),
            Step(tap.action, hold: 0.3),
        ])
        try await time.player().play(scene, named: "create-note", on: driver)
        #expect(time.pauses.map { ($0 * 1000).rounded() / 1000 } == [0.6, 1], "the last tap's answer outlasts its hold")
    }

    @Test func aDragBetweenElementsAndATapAtAShareOfTheScreenAreFoundAsTheyPlay() async throws {
        let driver = FakeDriver()
        driver.screens = [[
            ScreenElement(label: "Reorder Book club", frame: .init(x: 758, y: 812, width: 44, height: 44), activationPoint: Point(x: 780, y: 834)),
            ScreenElement(label: "Reorder Weekend plans", frame: .init(x: 758, y: 164, width: 44, height: 44)),
        ]]
        let touched = Touched()
        var player = Player(pause: { _ in }, report: { event in
            if case .finished(_, let timing) = event { touched.points.append([timing.evidence.touched, timing.evidence.lifted]) }
        })
        player.screen = CGSize(width: 834, height: 1194)
        let scene = SceneFile(steps: [
            Step(.drag(from: .element(ElementTarget(label: "Reorder Book club")), to: .element(ElementTarget(label: "Reorder Weekend plans")), duration: 0.6)),
        ])
        try await player.play(scene, named: "reorder", on: driver)
        #expect(touched.points[0] == [Point(x: 780, y: 834), Point(x: 780, y: 186)], "its activation point, or its frame's middle")
        #expect(driver.done == ["look", "direct"], "the screen's read once, before the drag")

        let landscape = SceneFile(steps: [Step(.tapPosition(x: .share(0.5), y: .points(100)))], orientation: .landscapeLeft)
        try await player.play(landscape, named: "turned", on: FakeDriver())
        #expect(touched.points[1] == [Point(x: 597, y: 100), nil], "half the screen's width as it faces, turned")
    }

    @Test func aShareOfAScreenWhoseSizeIsntKnownSaysSo() async {
        await #expect(throws: RetakeError.self) {
            try await Player(pause: { _ in }).play(SceneFile(steps: [Step(.tapPosition(x: .share(0.5), y: .share(0.5)))]), named: "a", on: FakeDriver())
        }
    }

    @Test func theFirstStepThatDoesntRunStopsThePlayNamingIt() async {
        let driver = FakeDriver()
        driver.failingRun = 1
        let scene = SceneFile(steps: [tap, Step(id: "send", .tapElement(ElementTarget(label: "Send"))), tap])
        await #expect {
            try await FakeTime().player().play(scene, named: "create-note", on: driver)
        } throws: { error in
            (error as? RetakeError)?.message == "create-note: step 2 of 3 (send), tap \"Send\", didn't run: No match for: label=\"Send\""
                && (error as? RetakeError)?.status == .failed
        }
        #expect(driver.runs == 2, "nothing after the failed step runs")
    }

    @Test func anElementThatMatchesSeveralSaysHowToNameOne() {
        let message = """
            element inflation failed [ambiguous]: 2 elements match: label="Delete" (scope: interface) — use ordinal 0–1 to select one
              label="Delete" [button] (visible)
              label="Delete" [header] (visible)
            """
        #expect(Player.ambiguity(message) == """
            2 elements match it, so which is meant isn't clear. Name it more closely, with its label, value and identifier together, or give "occurrence" (1 to 2, in the order VoiceOver reads the screen):
              label="Delete" [button] (visible)
              label="Delete" [header] (visible)
            """)
        #expect(Player.ambiguity("element inflation failed [notFound]: No match for: label=\"Nope\"") == nil)
        #expect(Player.ambiguity("10+ elements match: label=\"Row\" (scope: interface) — use ordinal 0, 1, 2, ... to select one")?.contains("(from 1,") == true)
    }

    @Test func aWaitThatRunsOutSaysWhatItWaitedFor() async {
        let driver = FakeDriver()
        driver.failingRun = 0
        let scene = SceneFile(steps: [Step(.waitFor(ElementTarget(label: "Done"), gone: true, timeout: 4))])
        await #expect {
            try await FakeTime().player().play(scene, named: "share", on: driver)
        } throws: { error in
            (error as? RetakeError)?.message == "share: step 1 of 1 failed: \"Done\" was still on screen after 4 s."
        }
    }

    @Test func aTurnEndsOnceTheScreenHasMovedAndSettled() async throws {
        let driver = FakeDriver()
        // Before the turn, then still portrait, then mid-turn, then landscape twice.
        driver.screens = [screen(width: 834), screen(width: 834), screen(width: 900), screen(width: 1194), screen(width: 1194)]
        let time = FakeTime()
        try await time.player().play(SceneFile(steps: [Step(.orientation(.landscapeLeft))]), named: "turn", on: driver)
        #expect(driver.done == ["look", "turn landscape-left", "look", "look", "look", "look"])
        #expect(time.pauses.count == 3)
    }

    @Test func aLoopingAnimationDoesntKeepATurnFromSettlingNorPassForOne() {
        func rect(_ x: Double) -> ScreenElement.Rect { ScreenElement.Rect(x: x, y: 0, width: 10, height: 10) }
        let portrait = [rect(0), rect(100), rect(200), rect(300)]
        let landscape = [rect(50), rect(150), rect(250), rect(300)]
        // The last element bobs on every look; the rest have moved to landscape and stay.
        var bobbing = landscape
        bobbing[3] = rect(305)
        #expect(Player.hasSettled(bobbing, from: portrait, moving: [3], before: [3]))
        #expect(!Player.hasSettled(bobbing, from: portrait, moving: [3], before: nil), "one look isn't enough to tell")
        #expect(!Player.hasSettled(bobbing, from: portrait, moving: [0, 1, 3], before: [0, 1, 2, 3]), "still turning")
        // Nothing turned: only the animation differs from before.
        var stayed = portrait
        stayed[3] = rect(305)
        #expect(!Player.hasSettled(stayed, from: portrait, moving: [3], before: [3]))
    }

    @Test func aTurnToTheWayTheDeviceFacesDoesntWait() async throws {
        let driver = FakeDriver()
        try await FakeTime().player().play(SceneFile(steps: [Step(.orientation(.portrait))]), named: "turn", on: driver)
        #expect(driver.done == ["look", "turn portrait"])
    }

    @Test func anAppThatDoesntTurnFailsTheStep() async {
        let driver = FakeDriver()
        driver.screens = [screen(width: 390)]
        let scene = SceneFile(steps: [Step(.orientation(.landscapeRight))])
        await #expect {
            try await FakeTime().player().play(scene, named: "turn", on: driver)
        } throws: { error in
            (error as? RetakeError)?.message.contains("didn't turn to landscape-right within 5 s") == true
        }
    }
}

struct ButtonHeistDriverTests {
    @Test func aMismatchedAppIsAnEnvironmentProblemNotRetried() {
        let mismatch = ButtonHeistDriver.connectionFailure(code: .protocolMismatch, message: "0.7.1 against 0.7.1-d53fb59edbf3")
        #expect(mismatch.error.status == .environment && !mismatch.retryable)
        #expect(mismatch.error.message.contains("embed it again"))
        let unreachable = ButtonHeistDriver.connectionFailure(code: .connectionEndpointUnreachable, message: "Could not reach")
        #expect(unreachable.error.status == .environment && unreachable.retryable, "a server not yet listening is tried again")
        #expect(!ButtonHeistDriver.connectionFailure(code: .authFailed, message: "bad token").retryable)
    }
}
