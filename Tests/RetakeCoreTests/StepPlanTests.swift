import Foundation
@testable import RetakeCore
import ThePlans
import Testing

struct StepPlanTests {
    func action(_ step: Step) throws -> HeistActionCommand? {
        guard case .heist(let plan) = try StepPlay.make(for: step), case .action(let action)? = plan.body.first else { return nil }
        return action.command
    }

    @Test func anElementIsMatchedOnEveryFieldGivenWithOccurrenceCountedFromZero() {
        let target = StepPlay.target(ElementTarget(label: "Delete", identifier: "row.delete", occurrence: 2))
        #expect(target == .predicate(ElementPredicate(label: .exact("Delete"), identifier: .exact("row.delete")), ordinal: 1))
        #expect(StepPlay.target(ElementTarget(value: "")) == .predicate(ElementPredicate(value: .isEmpty)), "an empty field")
        #expect(StepPlay.target(ElementTarget(value: "Title")) == .predicate(ElementPredicate(value: .exact("Title"))))
    }

    @Test func aDragAtTheDefaultSpeedIsAPlanAndAnyOtherADirectCommand() throws {
        let from = Point(x: 120, y: 590), to = Point(x: 260, y: 500)
        let plain = try action(Step(.drag(from: from, to: to, duration: Step.defaultDragDuration)))
        guard case .drag(let target)? = plain else { Issue.record("not a drag: \(String(describing: plain))"); return }
        #expect(target.duration == nil, "0.7.1 refuses a plan's drag with a duration")
        guard case .direct(.drag(let timed)) = try StepPlay.make(for: Step(.drag(from: from, to: to, duration: 0.8))) else {
            Issue.record("a timed drag isn't direct")
            return
        }
        #expect(timed.duration?.seconds == 0.8 && timed.end == ScreenPoint(x: 260, y: 500))
    }

    @Test func aWaitWaitsForTheElementOrItsGoingForItsTimeout() throws {
        let element = ElementTarget(label: "Done")
        guard case .heist(let plan) = try StepPlay.make(for: Step(.waitFor(element, gone: true, timeout: 4))),
              case .wait(let wait)? = plan.body.first else {
            Issue.record("not a wait")
            return
        }
        #expect(wait.predicate == .missing(StepPlay.target(element)) && wait.timeout.seconds == 4)
    }

    @Test func typingWithNoFieldTypesIntoTheFocusedOne() throws {
        guard case .typeText(let typed)? = try action(Step(.type(text: "Groceries\n", into: nil))) else {
            Issue.record("not typing")
            return
        }
        #expect(typed.target == nil)
    }

    @Test func turnsAndHoldsAreRetakesOwn() throws {
        #expect(try StepPlay.make(for: Step(.orientation(.landscapeLeft))) == .turn(.landscapeLeft))
        #expect(try StepPlay.make(for: Step(nil, hold: 2)) == .pause)
    }

    @Test func aWaitLongerThanTheButtonHeistAllowsFails() {
        #expect(throws: RetakeError.self) { try StepPlay.make(for: Step(.waitFor(ElementTarget(label: "Synced"), gone: false, timeout: 600))) }
    }

    @Test func stepsReadAsTheyArePrinted() {
        #expect(Step(.tapElement(ElementTarget(label: "Delete", occurrence: 2))).summary == "tap \"Delete\" (2nd)")
        #expect(Step(.tapElement(ElementTarget(label: "Row", occurrence: 12))).summary == "tap \"Row\" (12th)")
        #expect(Step(.type(text: "Mia\n", into: ElementTarget(value: "Name"))).summary == "type \"Mia\\n\" into value \"Name\"")
        #expect(Step(.waitFor(ElementTarget(label: "Done"), gone: true, timeout: 10)).summary == "wait for \"Done\" to go")
        #expect(Step(nil, hold: 1.5).summary == "hold 1.5 s")
        #expect(Point(x: 728.9000000000001, y: 410.25).description == "(728.9, 410.25)")
    }
}
