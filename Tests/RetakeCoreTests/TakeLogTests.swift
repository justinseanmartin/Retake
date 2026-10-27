import Foundation
@testable import RetakeCore
import Testing

struct TakeLogTests {
    let start = Date(timeIntervalSinceReferenceDate: 1000)

    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    func timing(sent: Double, received: Double, began: Double? = nil, ended: Double? = nil) -> Player.Timing {
        Player.Timing(
            sent: start.addingTimeInterval(sent), received: start.addingTimeInterval(received),
            evidence: StepEvidence(began: began.map(start.addingTimeInterval), ended: ended.map(start.addingTimeInterval)),
        )
    }

    @Test func stepsArePlacedFromTheDevicesTimesThroughItsClocksOffset() {
        // The device's clock runs 2 s ahead of the Mac's.
        let clock = MovieClock(start: start, deviceAhead: 2)
        let placed = clock.place(timing(sent: 5, received: 5.4, began: 7.05, ended: 7.3))
        #expect(close(placed.start, 5.05) && close(placed.end, 5.3) && placed.byDevice)
    }

    @Test func theDevicesTimesAreKeptWithinTheRoundTrip() {
        // An offset measured a little off would put the step before it was sent, or after its reply.
        let placed = MovieClock(start: start, deviceAhead: 0).place(timing(sent: 5, received: 5.4, began: 4.9, ended: 5.6))
        #expect(close(placed.start, 5) && close(placed.end, 5.4))
    }

    @Test func withoutTheDevicesTimesAStepIsWhenItWasSentAndAnswered() {
        let placed = MovieClock(start: start, deviceAhead: 2).place(timing(sent: 5, received: 5.4))
        #expect(close(placed.start, 5) && close(placed.end, 5.4) && !placed.byDevice)
    }

    @Test func aTapByPointAndADragRecordWhereTheyTouchedAndATapOnAnElementDoesnt() {
        let clock = MovieClock(start: start, deviceAhead: nil)
        func entry(_ step: Step) -> TakeLog.Entry {
            TakeLog.entry(Player.Played(isSetup: false, number: 1, count: 1, step: step), timing(sent: 1, received: 2), on: clock)
        }
        #expect(entry(Step(.tapPoint(Point(x: 195, y: 410)))).touch == Point(x: 195, y: 410))
        let drag = entry(Step(.drag(from: Point(x: 1, y: 2), to: Point(x: 3, y: 4), duration: 0.5)))
        #expect(drag.touch == Point(x: 1, y: 2) && drag.touchEnd == Point(x: 3, y: 4) && drag.action == "drag")
        #expect(entry(Step(.tapElement(ElementTarget(label: "Share")))).touch == nil, "only a tap by point is drawn")
        #expect(entry(Step(nil, hold: 2)).action == "hold")
    }

    @Test func theLogIsWrittenToTheMillisecondLeavingOutWhatItDoesntHave() throws {
        let log = TakeLog(
            scene: "create-note", take: 3, set: "returning-user", state: .clean, deviceType: .ipad,
            device: .init(model: "iPad13,4", marketingName: nil, os: "26.6.2 (23G90)"),
            app: .init(bundleID: "com.example.notes", version: "1.0", build: nil),
            retake: "0.0.1", buttonHeist: .init(version: "0.7.1"), recordedAt: start, failure: nil,
            duration: 12.3456789, width: 1200, height: 1718, launch: nil, clock: .init(deviceAhead: 0.0391),
            steps: [TakeLog.Entry(
                number: 1, id: nil, action: "tap", start: 1.0181234, end: 1.34, timedByDevice: true, touch: Point(x: 195.123, y: 410),
                touchEnd: nil, elements: [ScreenElement(label: "New Note", traits: ["button"], frame: .init(x: 780, y: 32, width: 44, height: 44.333))],
            )],
            shapes: [.init(at: 0, width: 1200, height: 1718, turn: 0)],
        )
        let json = log.json
        #expect(json[path: "duration"] == .number(12.346))
        #expect(json[path: "app", "build"] == nil && json[path: "device", "marketingName"] == nil)
        #expect(json[path: "failure"] == nil && json[path: "launch"] == nil)
        #expect(json[path: "size"] == .array([.number(1200), .number(1718)]))
        guard case .array(let steps)? = json[path: "steps"] else { Issue.record("no steps"); return }
        #expect(steps[0][path: "start"] == .number(1.018) && steps[0][path: "timedBy"] == .string("device"))
        #expect(steps[0][path: "touch"] == .array([.number(195.12), .number(410)]))
        #expect(steps[0][path: "id"] == nil)
        guard case .array(let elements)? = steps[0][path: "elements"] else { Issue.record("no elements"); return }
        #expect(elements[0][path: "frame"] == .array([.number(780), .number(32), .number(44), .number(44.33)]))
        #expect(elements[0][path: "value"] == nil)
    }

    @Test func evidenceComesFromTheResultsEarliestBaselineAndLatestScreen() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/heist-result-tap.json")
        // A tap's result from The Button Heist 0.7.1, its list of changes left out for size.
        let evidence = StepEvidence.from(json: try JSONParser.parse(String(contentsOf: url, encoding: .utf8)))
        #expect(evidence.began == Date(timeIntervalSinceReferenceDate: 814733819.044979))
        #expect(evidence.ended == Date(timeIntervalSinceReferenceDate: 814733819.31155))
        let labels = try #require(evidence.elements).compactMap(\.label)
        #expect(labels.contains("Add one"))
    }
}
