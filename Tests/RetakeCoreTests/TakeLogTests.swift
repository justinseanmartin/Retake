import Foundation
@testable import RetakeCore
import Testing

struct TakeLogTests {
    let start = Date(timeIntervalSinceReferenceDate: 1000)

    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    func timing(sent: Double, received: Double, began: Double? = nil, ended: Double? = nil, touched: Point? = nil, interaction: Double? = nil) -> Player.Timing {
        Player.Timing(
            sent: start.addingTimeInterval(sent), received: start.addingTimeInterval(received),
            evidence: StepEvidence(began: began.map(start.addingTimeInterval), ended: ended.map(start.addingTimeInterval), touched: touched, interaction: interaction),
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

    @Test func tapsAndDragsRecordWhereTheyTouched() {
        let clock = MovieClock(start: start, deviceAhead: nil)
        func entry(_ step: Step, touched: Point? = nil) -> TakeLog.Entry {
            TakeLog.entry(Player.Played(isSetup: false, number: 1, count: 1, step: step), timing(sent: 1, received: 2, touched: touched), on: clock)
        }
        #expect(entry(Step(.tapPoint(Position(Point(x: 195, y: 410))))).touch == Point(x: 195, y: 410))
        let drag = entry(Step(.drag(from: .point(x: 1, y: 2), to: .point(x: 3, y: 4), duration: 0.5)))
        #expect(drag.touch == Point(x: 1, y: 2) && drag.touchEnd == Point(x: 3, y: 4) && drag.action == "drag")
        #expect(entry(Step(.tapElement(ElementTarget(label: "Share"))), touched: Point(x: 30, y: 40)).touch == Point(x: 30, y: 40))
        #expect(entry(Step(.activate(ElementTarget(label: "Share"))), touched: Point(x: 30, y: 40)).touch == nil, "activating touches nothing")
        #expect(entry(Step(nil, hold: 2)).action == "hold")
        let timed = TakeLog.entry(
            Player.Played(isSetup: false, number: 1, count: 1, step: Step(.drag(from: .point(x: 1, y: 2), to: .point(x: 3, y: 4), duration: 0.5))),
            timing(sent: 1, received: 2, interaction: 0.52), on: clock,
        )
        #expect(timed.touchDuration == 0.52)
        let held = TakeLog.entry(Player.Played(isSetup: false, number: 1, count: 1, step: Step(nil, hold: 2)), timing(sent: 1, received: 2, interaction: 0.1), on: clock)
        #expect(held.touchDuration == nil, "only a touch has a touch's duration")
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
        #expect(evidence.touched == Point(x: 417.25, y: 493.25), "the tapped element's activation point")
        #expect(evidence.interaction == 0.131, "the touch's own time, without the wait for the screen to settle")
    }
}

struct TakeLogReadingTests {
    static func log(scene: String = "create-note", take: Int = 3, failure: String? = nil) -> TakeLog {
        TakeLog(
            scene: scene, take: take, set: "returning-user", state: .cloned, deviceType: .ipad,
            device: .init(model: "iPad13,4", marketingName: "iPad Pro (11-inch) (3rd generation)", os: "26.6.2 (23G90)"),
            app: .init(bundleID: "com.example.notes", version: "1.0", build: "7"),
            retake: "0.0.1", buttonHeist: .init(version: "0.7.1"), recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
            failure: failure, duration: 12.346, width: 1200, height: 1718, frames: 700, dropped: 2,
            aspect: .init(portrait: .init(width: 3, height: 4), landscape: .init(width: 4, height: 3)), screen: CGSize(width: 834, height: 1194),
            launch: .init(launched: 0.58, reported: 2.02, connected: 2.11), clock: .init(deviceAhead: 0.039),
            steps: [TakeLog.Entry(
                number: 1, id: "new-note", action: "drag", start: 1.018, end: 1.34, timedByDevice: true, touch: Point(x: 195.12, y: 410),
                touchEnd: Point(x: 20, y: 30), elements: [ScreenElement(label: "New Note", hint: "Starts a note", traits: ["button"], frame: .init(x: 780, y: 32, width: 44, height: 44.33), activationPoint: Point(x: 802, y: 54))],
            )],
            shapes: [.init(at: 0, width: 1200, height: 1718, turn: 0), .init(at: 4.5, width: 1718, height: 1200, turn: 90)],
        )
    }

    @Test func whatsWrittenReadsBackTheSame() {
        let log = Self.log(failure: "step 2 didn't run")
        let reader = JSONReader(file: "3.json")
        #expect(TakeLog.read(JSONWriter.write(log.json), with: reader) == log)
        #expect(reader.problems.isEmpty)
    }

    @Test func hitchesReadBackAndAreToldByCountAndTheLongest() {
        var log = Self.log()
        log.hitches = [.init(at: 1.2, duration: 0.53), .init(at: 4, duration: 0.017)]
        let reader = JSONReader(file: "3.json")
        #expect(TakeLog.read(JSONWriter.write(log.json), with: reader)?.hitches == log.hitches)
        #expect(log.hitchWarning(over: 0.01) == "create-note take 3: 2 hitches over 10 ms, the longest 530 ms at 1.2 s, during step 1.")
        #expect(log.hitchWarning(over: 0.05) == "create-note take 3: 1 hitch over 50 ms, the longest 530 ms at 1.2 s, during step 1.")
        #expect(log.hitchWarning(over: 0.6) == nil, "none as long as the threshold")
        log.hitches = [.init(at: 0.1, duration: 0.85), .init(at: 4, duration: 0.06)]
        #expect(log.hitchWarning(over: 0.05) == "create-note take 3: 1 hitch over 50 ms, the longest 60 ms at 4 s, between steps.", "the lead-in's left out")
        log.hitches = []
        #expect(log.hitchWarning(over: 0.05) == nil)
        log.hitches = nil
        #expect(TakeLog.read(JSONWriter.write(log.json), with: JSONReader(file: "3.json"))?.hitches == nil, "a take the library didn't watch")
    }

    @Test func aLogThatIsntOneIsNamedWhereItsWrong() {
        let reader = JSONReader(file: "3.json")
        var text = JSONWriter.write(Self.log().json)
        text = text.replacingOccurrences(of: #""timedBy": "device""#, with: #""timedBy": "phone""#)
        text = text.replacingOccurrences(of: #""dropped": 2"#, with: #""droped": 2"#)
        #expect(TakeLog.read(text, with: reader) == nil)
        #expect(reader.problems.map(\.description).sorted() == [
            #"3.json: steps[0].timedBy: "phone" isn't one of "device" or "mac""#,
            #"3.json: unknown key "droped"; did you mean "dropped"?"#,
        ])
    }
}
