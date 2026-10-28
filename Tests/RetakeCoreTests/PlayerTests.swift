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

    func run(_ plan: HeistPlan) async throws(RetakeError) -> StepEvidence {
        defer { runs += 1 }
        done.append("run")
        if runs == failingRun { throw RetakeError(.failed, "No match for: label=\"Send\"") }
        return StepEvidence()
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
