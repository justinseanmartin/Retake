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

    @Test func anAnchorIsAtItsStepsStartOrWithEdgeEndItsEndAndAnOffsetCountsFromThere() throws {
        #expect(try time(.id("a")) == 1 && time(.id("a"), offset: 0) == 1 && time(.id("a"), offset: 0, edge: .start) == 1, "0 is the start itself")
        #expect(try time(.id("a"), offset: 0.2) == 1.2 && time(.id("a"), offset: -0.2) == 0.8)
        #expect(try time(.id("a"), edge: .end) == 1.5 && time(.id("a"), offset: 0, edge: .end) == 1.5)
        #expect(try time(.id("a"), offset: 0.2, edge: .end) == 1.7 && time(.id("a"), offset: -0.2, edge: .end) == 1.3)
        #expect(try time(.start) == 0 && time(.end) == 6 && time(.end, offset: -0.5) == 5.5)
        #expect(try Self.timeline().time(of: .seconds(2.5)) == 2.5)
    }

    @Test func aFractionIsAShareOfTheWayFromThereToTheNeighbouringStep() throws {
        #expect(try time(.id("b"), fraction: 0.5) == 3, "from its start to step 3's start")
        #expect(try time(.id("b"), fraction: -0.5) == 1.75, "from its start back to step 1's end")
        #expect(try time(.id("b"), fraction: 0.5, edge: .end) == 3.5, "from its end to step 3's start")
        #expect(try time(.id("b"), fraction: -0.5, edge: .end) == 2.25, "from its end back to step 1's end")
        #expect(try time(.id("b"), fraction: 0) == 2 && time(.id("b"), fraction: 0, edge: .end) == 3)
        #expect(try time(.number(-1), fraction: 0.5, edge: .end) == 5.25, "past the last step, to the take's end")
        #expect(try time(.number(1), fraction: -1) == 0, "before the first, to the take's start")
        #expect(try time(.start, fraction: 0.5) == 0.5, "from the take's start to the first step")
    }

    @Test func secondsTurnedIntoAnAnchorResolveBackToThem() throws {
        let timeline = Self.timeline()
        for seconds in [0, 0.4, 1, 1.25, 2.75, 3.5, 5.9] {
            let value = CutPreparer.anchor(for: seconds, in: timeline.log)
            #expect(!JSONWriter.compact(value).contains("edge"))
            let anchor = try #require(EditFile.readAnchor(value, .root, JSONReader(file: "edit.json")))
            #expect(abs(try timeline.time(of: anchor) - seconds) < 1e-9, "\(JSONWriter.compact(value))")
        }
    }

    /// The rule before 2026-11-06: with no edge, a value of 0 or more counted from the step's end.
    static func timeByTheOldRule(_ anchor: Anchor.StepAnchor, in timeline: TakeTimeline) throws -> Double {
        let place = try timeline.place(of: anchor.step)
        func edge(forward: Bool) -> Double { anchor.edge.map { $0 == .start ? place.start : place.end } ?? (forward ? place.end : place.start) }
        if let offset = anchor.offset { return edge(forward: offset >= 0) + offset }
        guard let fraction = anchor.fraction else { return place.start }
        let base = edge(forward: fraction >= 0)
        let toward = try #require(fraction > 0 ? place.nextStart : fraction < 0 ? place.previousEnd : base)
        return base + abs(fraction) * (toward - base)
    }

    @Test func theExamplesAnchorsLandWhereTheyDidBeforeTheRuleChanged() throws {
        let edits = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Example/Retake/edits")
        var anchors: [Anchor.StepAnchor] = []
        func collect(_ value: JSONValue) {
            switch value {
            case .array(let values): values.forEach(collect)
            case .object(let object):
                if object["step"] != nil, case .step(let anchor)? = EditFile.readAnchor(value, .root, JSONReader(file: "edit.json")) { anchors.append(anchor) }
                object.entries.forEach { collect($0.value) }
            default: break
            }
        }
        for name in ["tour", "showcase"] {
            collect(try JSONParser.parse(String(contentsOf: edits.appending(path: "\(name).json"), encoding: .utf8)))
        }
        #expect(anchors.count > 30)
        // Each at step b, which has steps either side and a gap between its end and the next start.
        let timeline = Self.timeline()
        for var anchor in anchors {
            anchor.step = .id("b")
            #expect(try timeline.time(of: .step(anchor)) == Self.timeByTheOldRule(anchor, in: timeline), "\(anchor)")
        }
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

    @Test func anElementAtTheFirstStepsStartIsFoundInTheReadingBeforeTheStepsAndALogWithoutOneFailsAsBefore() throws {
        let compose = ScreenElement(label: "Compose", frame: .init(x: 90, y: 20, width: 44, height: 44))
        let start = try Self.timeline().time(of: .step(.init(step: .number(1), offset: nil, fraction: nil, edge: nil)))
        #expect(throws: TakeTimeline.Unresolved("the take has no reading of the screen at or before 1 s")) {
            try Self.timeline().element(ElementTarget(label: "Compose"), at: start)
        }
        var log = Self.timeline().log
        log.beforeSteps = TakeLog.Reading(at: 0.8, elements: [compose])
        let timeline = TakeTimeline(try #require(TakeLog.read(JSONWriter.write(log.json), with: JSONReader(file: "a.json"))))
        #expect(try timeline.element(ElementTarget(label: "Compose"), at: start) == compose)
        #expect(try timeline.element(ElementTarget(label: "Compose"), at: 0) == compose, "the lead-in shows the screen read at its end")
        #expect(throws: TakeTimeline.Unresolved(#""Share" isn't on screen before the first step, at 0.8 s"#)) {
            try timeline.element(ElementTarget(label: "Share"), at: 2.9)
        }
        #expect(throws: TakeTimeline.Unresolved(#""Compose" isn't on screen after step 2, at 3 s"#), "a step's reading takes over once it has ended") {
            try timeline.element(ElementTarget(label: "Compose"), at: 3)
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
