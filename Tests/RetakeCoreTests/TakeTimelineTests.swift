import Foundation
@testable import RetakeCore
import Testing

/// Anchors and elements resolved against a take's step log.
struct TakeTimelineTests {
    static let button = ScreenElement(label: "Share", traits: ["button"], frame: .init(x: 10, y: 20, width: 44, height: 44))

    /// Three steps: `a` at 1–1.5 s, `b` at 2–3 s with the screen read after it, and a hold at 4–4.5 s,
    /// in a take 6 s long.
    static func timeline(elements: [ScreenElement] = [button]) -> TakeTimeline {
        var log = TakeLogReadingTests.log()
        log.duration = 6
        log.steps = [
            TakeLog.Entry(number: 1, id: "a", action: "tap", start: 1, end: 1.5, timedByDevice: true, touch: nil, touchEnd: nil, elements: nil),
            TakeLog.Entry(number: 2, id: "b", action: "waitFor", start: 2, end: 3, timedByDevice: true, touch: nil, touchEnd: nil, elements: elements),
            TakeLog.Entry(number: 3, id: nil, action: "hold", start: 4, end: 4.5, timedByDevice: false, touch: nil, touchEnd: nil, elements: nil),
        ]
        return TakeTimeline(log)
    }

    func time(_ step: Anchor.StepReference, offset: Double? = nil, fraction: Double? = nil, edge: Anchor.Edge? = nil) throws -> Double {
        try Self.timeline().time(of: .step(.init(step: step, offset: offset, fraction: fraction, edge: edge)))
    }

    @Test func offsetsMoveForwardFromAStepsEndAndBackFromItsStart() throws {
        #expect(try time(.id("a")) == 1, "with neither, the step's start")
        #expect(try time(.id("a"), offset: 0.2) == 1.7)
        #expect(try time(.id("a"), offset: -0.2) == 0.8)
        #expect(try time(.id("a"), offset: 0.2, edge: .start) == 1.2)
        #expect(try time(.id("a"), offset: -0.2, edge: .end) == 1.3)
        #expect(try time(.start) == 0 && time(.end) == 6)
        #expect(try time(.end, offset: -0.5) == 5.5)
        #expect(try Self.timeline().time(of: .seconds(2.5)) == 2.5)
    }

    @Test func fractionsMoveAShareOfTheGapToTheNeighbouringStep() throws {
        #expect(try time(.id("b"), fraction: 0.5) == 3.5, "toward step 3's start")
        #expect(try time(.id("b"), fraction: -0.5) == 1.75, "back toward step 1's end")
        #expect(try time(.number(-1), fraction: 0.5) == 5.25, "past the last step, toward the take's end")
        #expect(try time(.number(1), fraction: -1) == 0, "before the first, toward the take's start")
        #expect(try time(.start, fraction: 0.5) == 0.5, "from the take's start toward the first step")
        #expect(try time(.id("b"), fraction: 0.5, edge: .start) == 3, "from its start toward the next step's")
    }

    @Test(arguments: [
        (Anchor.StepReference.id("nowhere"), nil as Double?, #"the take has no step "nowhere""#),
        (.number(4), nil, "the take has 3 steps, so there's no step 4"),
        (.number(-4), nil, "the take has 3 steps, so there's no step -4"),
        (.end, 0.5, "a fraction forward from the take's end has no step to go toward"),
        (.start, -0.5, "a fraction back from the take's start has no step to go toward"),
    ])
    func anchorsThatDontResolveSayWhy(_ step: Anchor.StepReference, _ fraction: Double?, _ why: String) {
        #expect(throws: TakeTimeline.Unresolved(why)) { try time(step, fraction: fraction) }
    }

    @Test func anElementIsFoundInTheLatestReadingAtOrBeforeTheMoment() throws {
        #expect(try Self.timeline().element(ElementTarget(label: "Share"), at: 3) == Self.button)
        #expect(try Self.timeline().element(ElementTarget(traits: ["button"]), at: 5.9) == Self.button)
        #expect(throws: TakeTimeline.Unresolved("the take has no reading of the screen at or before 2.9 s")) {
            try Self.timeline().element(ElementTarget(label: "Share"), at: 2.9)
        }
        #expect(throws: TakeTimeline.Unresolved(#""Send" isn't on screen after step 2, at 3 s"#)) {
            try Self.timeline().element(ElementTarget(label: "Send"), at: 3)
        }
    }

    @Test func severalMatchingAreNamedByOccurrenceAndOneOffScreenIsntFound() throws {
        let second = ScreenElement(label: "Share", frame: .init(x: 10, y: 90, width: 44, height: 44))
        let hidden = ScreenElement(label: "Hidden")
        let timeline = Self.timeline(elements: [Self.button, second, hidden])
        #expect(try timeline.element(ElementTarget(label: "Share", occurrence: 2), at: 3) == second)
        #expect(throws: TakeTimeline.Unresolved(#"2 elements match "Share" on screen after step 2, at 3 s; name it more closely, or give occurrence, from 1 to 2"#)) {
            try timeline.element(ElementTarget(label: "Share"), at: 3)
        }
        #expect(throws: TakeTimeline.Unresolved(#""Hidden" is off screen after step 2, at 3 s"#)) {
            try timeline.element(ElementTarget(label: "Hidden"), at: 3)
        }
    }
}
