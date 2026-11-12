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
        #expect(StepPlay.target(ElementTarget(label: "Notes", hint: "Opens it", traits: ["header", "selected"])) == .predicate(ElementPredicate(
            label: .exact("Notes"), traits: [.header, .selected], hint: .exact("Opens it"),
        )))
        #expect(StepPlay.target(ElementTarget(value: "Title")) == .predicate(ElementPredicate(value: .exact("Title"))))
    }

    @Test func aDragAtTheDefaultSpeedIsAPlanAndAnyOtherADirectCommand() throws {
        let from = Spot.point(x: 120, y: 590), to = Spot.point(x: 260, y: 500)
        let plain = try action(Step(.drag(from: from, to: to, duration: Step.defaultDragDuration)))
        guard case .drag(let target)? = plain else { Issue.record("not a drag: \(String(describing: plain))"); return }
        #expect(target.duration == nil, "0.7.1 refuses a plan's drag with a duration")
        guard case .direct(.drag(let timed)) = try StepPlay.make(for: Step(.drag(from: from, to: to, duration: 0.8))) else {
            Issue.record("a timed drag isn't direct")
            return
        }
        #expect(timed.duration?.seconds == 0.8 && timed.end == ScreenPoint(x: 260, y: 500))
    }

    @Test func aDragFromAnElementStartsOnItAndEndsWhereThePlayerFoundItsEnd() throws {
        let handle = ElementTarget(label: "Reorder Book club")
        let step = Step(.drag(from: .element(handle), to: .element(ElementTarget(label: "Reorder Weekend plans")), duration: 0.6))
        guard case .direct(.drag(let target)) = try StepPlay.make(for: step, end: Point(x: 780, y: 186)) else {
            Issue.record("not a timed drag")
            return
        }
        #expect(target.start == .element(StepPlay.target(handle)) && target.end == ScreenPoint(x: 780, y: 186))
        #expect(throws: RetakeError.self, "an element end needs the player to have found it") { try StepPlay.make(for: step) }
    }

    @Test func aDragFromAnElementWithAnOffsetStartsWhereThePlayerFoundIt() throws {
        let from = Spot.element(ElementTarget(label: "O piece"), offset: SpotOffset(percent: Point(x: 0, y: -50)))
        let step = Step(.drag(from: from, to: .point(x: 400, y: 800), duration: 0.6))
        guard case .direct(.drag(let target)) = try StepPlay.make(for: step, touch: Point(x: 160, y: 270)) else {
            Issue.record("not a timed drag")
            return
        }
        #expect(target.start == .coordinate(ScreenPoint(x: 160, y: 270)), "The Button Heist would touch the element itself, not the offset")
        #expect(throws: RetakeError.self, "an offset start needs the player to have found it") { try StepPlay.make(for: step) }
    }

    @Test func aTapOnAnElementWithAnOffsetTouchesWhereThePlayerFoundIt() throws {
        let step = Step(.tapElement(ElementTarget(label: "Puzzle"), offset: SpotOffset(points: Point(x: 0, y: -8))))
        guard case .heist(let plan) = try StepPlay.make(for: step, touch: Point(x: 200, y: 312)),
              case .action(let action)? = plan.body.first, case .oneFingerTap(let tap) = action.command
        else {
            Issue.record("not a tap")
            return
        }
        #expect(tap.selection == .coordinate(ScreenPoint(x: 200, y: 312)), "The Button Heist would touch the element itself, not the offset")
        #expect(throws: RetakeError.self, "an offset tap needs the player to have found it") { try StepPlay.make(for: step) }
    }

    @Test func anOffsetMovesTheActivationPointByPointsAndShareOfTheElementsSize() throws {
        let cell = ScreenElement(label: "Row 2, column 3", frame: .init(x: 356.5, y: 631.5, width: 60, height: 60), activationPoint: Point(x: 386.5, y: 661.5))
        let offset = SpotOffset(points: Point(x: 1, y: -1), percent: Point(x: 50, y: 150))
        #expect(try Player.point(of: ElementTarget(label: "Row 2, column 3"), in: [cell], movedBy: offset) == Point(x: 417.5, y: 750.5))
        #expect(try Player.point(of: ElementTarget(label: "Row 2, column 3"), in: [cell]) == Point(x: 386.5, y: 661.5))
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
