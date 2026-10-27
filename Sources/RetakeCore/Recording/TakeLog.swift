import Foundation

/// A take's step log, written beside its movie as `<n>.json`: what was recorded, with what, and
/// when each step happened on the movie's own clock, where it touched, and what was on screen after
/// it. Edits cut on it, draw touches from it and find elements in it. See README.md, "Takes".
public struct TakeLog: Equatable, Sendable {
    public var scene: String
    public var take: Int
    public var set: String
    public var state: SetFile.State
    public var deviceType: DeviceType
    public var device: DeviceInfo
    public var app: AppInfo
    /// The Retake that recorded it.
    public var retake: String
    /// The Button Heist that drove the app, the one embedded in it.
    public var buttonHeist: RetakeVersion.ButtonHeist
    public var recordedAt: Date
    /// Why the take failed, for one whose step didn't run; nil for a take that played every step.
    public var failure: String?
    /// The movie's length, and its size in pixels.
    public var duration: Double
    public var width: Int
    public var height: Int
    /// For a take recorded from before the app launched: when it was launched, when Retake's
    /// support library reported in, and when The Button Heist connected, for an edit to cut in on.
    public var launch: Launch?
    /// How steps were placed on the movie's clock.
    public var clock: Clock
    public var steps: [Entry]
    /// The movie's first shape, and each change after it, with how the frames were turned.
    public var shapes: [TakeWriter.ShapeChange]

    public struct DeviceInfo: Equatable, Sendable {
        /// The hardware identifier, `iPad13,4`, and the marketing name.
        public var model: String
        public var marketingName: String?
        /// The iOS version and build, `26.6.2 (23G90)`.
        public var os: String
    }

    public struct AppInfo: Equatable, Sendable {
        public var bundleID: String
        /// `CFBundleShortVersionString` and `CFBundleVersion`.
        public var version: String?
        public var build: String?
    }

    public struct Launch: Equatable, Sendable {
        public var launched: Double
        public var reported: Double
        public var connected: Double
    }

    public struct Clock: Equatable, Sendable {
        /// How far the device's clock was ahead of the Mac's, in seconds, measured once at the
        /// start of the take; steps are placed from the device's own times through it.
        public var deviceAhead: Double?
    }

    /// One step as it was recorded.
    public struct Entry: Equatable, Sendable {
        /// Its number among the scene's steps, from 1, and its id.
        public var number: Int
        public var id: String?
        /// The kind of step: `tap`, `drag`, `type`, `activate`, `orientation`, `waitFor`,
        /// `inspect`, or `hold` for one that's only a pause.
        public var action: String
        /// Seconds into the movie: when it began, and when it ended, as the device saw it where it
        /// could, which for a `waitFor` is when its element came or went.
        public var start: Double
        public var end: Double
        /// Whether `start` and `end` are the device's own times, or when the Mac sent the step and
        /// heard back, which a round trip either side widens.
        public var timedByDevice: Bool
        /// Where it touched the screen, in screen points: a tap by point, and a drag's two ends.
        public var touch: Point?
        public var touchEnd: Point?
        /// What was on screen when it ended.
        public var elements: [ScreenElement]?
    }
}

/// Where moments on the Mac's clock, and the device's, fall on a movie's own clock.
public struct MovieClock: Equatable, Sendable {
    /// When, on the Mac's clock, the movie's first frame was.
    public var start: Date
    /// How far the device's clock is ahead of the Mac's.
    public var deviceAhead: Double?

    public init(start: Date, deviceAhead: Double?) {
        self.start = start
        self.deviceAhead = deviceAhead
    }

    public func seconds(_ mac: Date) -> Double {
        mac.timeIntervalSince(start)
    }

    /// A step's start and end in the movie: from the device's times, kept within when the Mac sent
    /// it and heard back, where it has them; else from those two.
    public func place(_ timing: Player.Timing) -> (start: Double, end: Double, byDevice: Bool) {
        let sent = seconds(timing.sent), received = seconds(timing.received)
        guard let deviceAhead, let began = timing.evidence.began, let ended = timing.evidence.ended else {
            return (sent, received, false)
        }
        let start = min(max(seconds(began.addingTimeInterval(-deviceAhead)), sent), received)
        let end = min(max(seconds(ended.addingTimeInterval(-deviceAhead)), start), received)
        return (start, end, true)
    }
}

extension TakeLog {
    /// Its entry for a step that ran, placed on the movie's clock.
    public static func entry(_ played: Player.Played, _ timing: Player.Timing, on clock: MovieClock) -> Entry {
        let (start, end, byDevice) = clock.place(timing)
        var touch: Point?, touchEnd: Point?
        switch played.step.action {
        case .tapPoint(let point): touch = point
        case .drag(let from, let to, _): (touch, touchEnd) = (from, to)
        default: break
        }
        return Entry(
            number: played.number, id: played.step.id, action: played.step.action?.key ?? "hold",
            start: start, end: end, timedByDevice: byDevice, touch: touch, touchEnd: touchEnd, elements: timing.evidence.elements,
        )
    }

    /// The log as Retake writes it.
    public var json: JSONValue {
        var object: [JSONObject.Entry] = [
            .init(key: "scene", value: .string(scene)),
            .init(key: "take", value: .number(Double(take))),
            .init(key: "set", value: .string(set)),
            .init(key: "state", value: .string(state.rawValue)),
            .init(key: "deviceType", value: .string(deviceType.rawValue)),
            .init(key: "device", value: Self.object([
                ("model", .string(device.model)), ("marketingName", device.marketingName.map(JSONValue.string)), ("os", .string(device.os)),
            ])),
            .init(key: "app", value: Self.object([
                ("bundleID", .string(app.bundleID)), ("version", app.version.map(JSONValue.string)), ("build", app.build.map(JSONValue.string)),
            ])),
            .init(key: "retake", value: .string(retake)),
            .init(key: "buttonHeist", value: Self.object([
                ("version", .string(buttonHeist.version)), ("commit", buttonHeist.commit.map(JSONValue.string)),
            ])),
            .init(key: "recordedAt", value: .string(ISO8601DateFormatter().string(from: recordedAt))),
        ]
        if let failure { object.append(.init(key: "failure", value: .string(failure))) }
        object += [
            .init(key: "duration", value: Self.number(duration)),
            .init(key: "size", value: .array([.number(Double(width)), .number(Double(height))])),
        ]
        if let launch {
            object.append(.init(key: "launch", value: Self.object([
                ("launched", Self.number(launch.launched)), ("reported", Self.number(launch.reported)), ("connected", Self.number(launch.connected)),
            ])))
        }
        object.append(.init(key: "clock", value: Self.object([("deviceAhead", clock.deviceAhead.map { Self.number($0) })])))
        object.append(.init(key: "steps", value: .array(steps.map(\.json))))
        object.append(.init(key: "shapes", value: .array(shapes.map { shape in
            Self.object([
                ("at", Self.number(shape.at)), ("size", .array([.number(Double(shape.width)), .number(Double(shape.height))])),
                ("turn", .number(Double(shape.turn))),
            ])
        })))
        return .object(JSONObject(object))
    }

    /// An object of the fields given, leaving out those that are nil.
    static func object(_ fields: [(String, JSONValue?)]) -> JSONValue {
        .object(JSONObject(fields.compactMap { key, value in value.map { JSONObject.Entry(key: key, value: $0) } }))
    }

    /// Seconds to the millisecond, and points to the hundredth, which is all they mean.
    static func number(_ value: Double, places: Double = 1000) -> JSONValue {
        .number((value * places).rounded() / places)
    }
}

extension TakeLog.Entry {
    var json: JSONValue {
        TakeLog.object([
            ("number", .number(Double(number))),
            ("id", id.map(JSONValue.string)),
            ("action", .string(action)),
            ("start", TakeLog.number(start)),
            ("end", TakeLog.number(end)),
            ("timedBy", .string(timedByDevice ? "device" : "mac")),
            ("touch", touch.map(\.json)),
            ("touchEnd", touchEnd.map(\.json)),
            ("elements", elements.map { .array($0.map(\.json)) }),
        ])
    }
}

extension Point {
    var json: JSONValue { .array([TakeLog.number(x, places: 100), TakeLog.number(y, places: 100)]) }
}

extension ScreenElement {
    var json: JSONValue {
        TakeLog.object([
            ("label", label.map(JSONValue.string)),
            ("value", value.map(JSONValue.string)),
            ("identifier", identifier.map(JSONValue.string)),
            ("traits", traits.isEmpty ? nil : .array(traits.map(JSONValue.string))),
            ("frame", frame.map { .array([$0.x, $0.y, $0.width, $0.height].map { TakeLog.number($0, places: 100) }) }),
            ("activationPoint", activationPoint.map(\.json)),
        ])
    }
}
