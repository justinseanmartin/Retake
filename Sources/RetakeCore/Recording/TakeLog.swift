import Foundation

/// A take's step log, written beside its movie as `<n>.json`: what was recorded, with what, and
/// when each step happened on the movie's own clock, where it touched, and what was on screen after
/// it. Edits cut on it, draw touches from it and find elements in it. See README.md, "Takes", and
/// Documentation/reference/take.md, generated from `TakeLog.schema`.
///
/// Retake writes no `format`: a log without one is format 1. The reader refuses a later format,
/// saying the take was recorded by a newer Retake, so a breaking change can add one cleanly.
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
    /// Frames written, and frames the encoder wasn't ready for, which a hitch in the take shows.
    public var frames: Int
    public var dropped: Int
    /// The shape the set's `previewAspect` gave the app's window, portrait and landscape, at the top (or in
    /// landscape, the left) of the screen; nil when the window filled it. The editor crops to it.
    /// Logs recorded before it was renamed call it `aspect`, which still reads.
    public var previewAspect: SetFile.AspectChoice? = nil
    /// The device's screen in points, portrait, which the log's touches and frames are in, for the
    /// editor to find them in the frames.
    public var screen: CGSize
    /// For a take recorded from before the app launched: when it was launched, when Retake's
    /// support library reported in, and when The Button Heist connected, for an edit to cut in on.
    public var launch: Launch?
    /// How steps were placed on the movie's clock.
    public var clock: Clock
    public var steps: [Entry]
    /// The movie's first shape, and each change after it, with how the frames were turned.
    public var shapes: [TakeWriter.ShapeChange]
    /// Each time the app's main thread missed a frame while it was recorded, on the movie's clock;
    /// nil when the app's support library didn't watch.
    public var hitches: [Hitch]? = nil

    /// The take's hitches of `threshold` seconds or more as a person should hear of them: how many,
    /// the longest, and whether it came while The Button Heist was acting on a step; nil when none.
    /// Those over before the first step are left out: the lead-in holds a stall of most of a second
    /// just after the app is connected, in nearly every take, which would always be the longest and
    /// hide the ones that matter. A clip that does play the lead-in is warned of by `cut`.
    public func hitchWarning(over threshold: Double) -> String? {
        let firstStep = steps.first?.start ?? 0
        let over = (hitches ?? []).filter { $0.duration >= threshold && $0.at + $0.duration > firstStep }
        guard let longest = over.max(by: { $0.duration < $1.duration }) else { return nil }
        let step = steps.first { longest.at >= $0.start - 0.05 && longest.at <= $0.end + 0.1 }
        return "\(scene) take \(take): \(Self.describe(over, over: threshold)) at \(TakeTimeline.seconds(longest.at))"
            + (step.map { ", during step \($0.number)" } ?? ", between steps") + "."
    }

    /// `3 hitches over 50 ms, the longest 530 ms`.
    public static func describe(_ hitches: [Hitch], over threshold: Double) -> String {
        let longest = hitches.map(\.duration).max() ?? 0
        return "\(hitches.count) hitch\(hitches.count == 1 ? "" : "es") over \(Int((threshold * 1000).rounded())) ms, the longest \(Int((longest * 1000).rounded())) ms"
    }

    /// The app's main thread busy for at least a frame: when it last drew, and how long until it
    /// drew again.
    public struct Hitch: Equatable, Sendable {
        public var at: Double
        public var duration: Double
    }

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
        /// or `hold` for one that's only a pause.
        public var action: String
        /// Seconds into the movie: when it began, and when it ended, as the device saw it where it
        /// could, which for a `waitFor` is when its element came or went.
        public var start: Double
        public var end: Double
        /// Whether `start` and `end` are the device's own times, or when the Mac sent the step and
        /// heard back, which a round trip either side widens.
        public var timedByDevice: Bool
        /// Where it touched the screen, in screen points: a tap, by point or on an element, and a
        /// drag's two ends.
        public var touch: Point?
        public var touchEnd: Point?
        /// How long the finger was on the screen, from `start`, as The Button Heist timed it.
        public var touchDuration: Double? = nil
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
        case .tapPoint(let position): touch = timing.evidence.touched ?? position.point(on: nil)
        case .tapElement: touch = timing.evidence.touched
        case .drag(let from, let to, _): (touch, touchEnd) = (timing.evidence.touched ?? from.point, timing.evidence.lifted ?? to.point)
        default: break
        }
        return Entry(
            number: played.number, id: played.step.id, action: played.step.action?.key ?? "hold",
            start: start, end: end, timedByDevice: byDevice, touch: touch, touchEnd: touchEnd,
            touchDuration: touch == nil ? nil : timing.evidence.interaction, elements: timing.evidence.elements,
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
        if let previewAspect {
            object.append(.init(key: "previewAspect", value: Self.object([
                ("portrait", previewAspect.portrait.map { .string($0.description) }),
                ("landscape", previewAspect.landscape.map { .string($0.description) }),
            ])))
        }
        object += [
            .init(key: "screen", value: .array([Self.number(screen.width, places: 100), Self.number(screen.height, places: 100)])),
            .init(key: "frames", value: .number(Double(frames))),
            .init(key: "dropped", value: .number(Double(dropped))),
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
        if let hitches {
            object.append(.init(key: "hitches", value: .array(hitches.map { Self.object([("at", Self.number($0.at)), ("duration", Self.number($0.duration))]) })))
        }
        return .object(JSONObject(object))
    }

    /// An object of the fields given, leaving out those that are nil.
    public static func object(_ fields: [(String, JSONValue?)]) -> JSONValue {
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
            ("touchDuration", touchDuration.map { TakeLog.number($0) }),
            ("elements", elements.map { .array($0.map(\.json)) }),
        ])
    }
}

extension Point {
    var json: JSONValue { .array([TakeLog.number(x, places: 100), TakeLog.number(y, places: 100)]) }
}

extension ScreenElement {
    /// As a step log and `compose --json` give it.
    public var json: JSONValue {
        TakeLog.object([
            ("label", label.map(JSONValue.string)),
            ("value", value.map(JSONValue.string)),
            ("identifier", identifier.map(JSONValue.string)),
            ("hint", hint.map(JSONValue.string)),
            ("traits", traits.isEmpty ? nil : .array(traits.map(JSONValue.string))),
            ("frame", frame.map { .array([$0.x, $0.y, $0.width, $0.height].map { TakeLog.number($0, places: 100) }) }),
            ("activationPoint", activationPoint.map(\.json)),
        ])
    }
}

extension TakeLog {
    /// The step log's format this Retake reads, and the only one it has written: a log without
    /// `format` is this one.
    public static let format = 1

    /// `recordedAt` as a log gives it, in ISO 8601: a date, a time to the second with any fraction of
    /// it, and `Z` or a zone's offset, with or without its colon, such as 2026-11-06T09:30:00Z or
    /// 2026-11-06T10:30:00.250+01:00. The reader and the schema both match it. A day past its
    /// month's end, such as the 31st of April, matches, and is read as the days after it.
    public static let recordedAtPattern =
        #"^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):?[0-5][0-9])$"#

    /// The moment `text` names, if it matches `recordedAtPattern`.
    static func recordedAt(_ text: String) -> Date? {
        guard text.range(of: recordedAtPattern, options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        if text.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
        return formatter.date(from: text)
    }

    /// A step log as Retake wrote it, read strictly, as every file Retake reads is; nil, with the
    /// reader's problems saying why, when it isn't one. One of a later `format` is refused with
    /// only that said, since the rest of it is a newer Retake's to read.
    public static func read(_ text: String, with reader: JSONReader) -> TakeLog? {
        guard let value = reader.parse(text), var root = reader.object(value, at: .root) else { return nil }
        if case .number(let number)? = root.object["format"], number.rounded() == number, number > Double(format) {
            reader.problem(
                "was recorded by a newer Retake, in step log format \(JSONReader.format(number)), which this Retake (\(RetakeVersion.current.version)) can't read; update Retake to use this take",
                at: .root,
            )
            return nil
        }
        _ = root.optional("format") { reader.integer($0, at: $1, atLeast: 1) }
        defer { root.finish() }
        func object<Value>(_ key: String, _ read: (inout ObjectReader) -> Value?) -> Value? {
            root.required(key) { value, path in
                guard var object = reader.object(value, at: path) else { return nil }
                defer { object.finish() }
                return read(&object)
            }
        }
        func point(_ value: JSONValue, _ path: JSONPath) -> Point? {
            guard let numbers = reader.array(value, at: path, element: { reader.number($0, at: $1) }), numbers.count == 2 else {
                reader.problem("expected [x, y]", at: path)
                return nil
            }
            return Point(x: numbers[0], y: numbers[1])
        }
        func size(_ value: JSONValue, _ path: JSONPath) -> (Int, Int)? {
            guard let numbers = reader.array(value, at: path, element: { reader.integer($0, at: $1, atLeast: 0) }), numbers.count == 2 else {
                reader.problem("expected [width, height]", at: path)
                return nil
            }
            return (numbers[0], numbers[1])
        }
        let scene = root.required("scene", reader.nonEmptyString)
        let take = root.required("take") { reader.integer($0, at: $1, atLeast: 1) }
        let set = root.required("set", reader.nonEmptyString)
        let state = root.required("state") { reader.choice($0, at: $1, as: SetFile.State.self) }
        let deviceType = root.required("deviceType") { reader.choice($0, at: $1, as: DeviceType.self) }
        let device = object("device") { object -> DeviceInfo? in
            let model = object.required("model", reader.string)
            let marketingName = object.optional("marketingName", reader.string)
            let os = object.required("os", reader.string)
            guard let model, let os else { return nil }
            return DeviceInfo(model: model, marketingName: marketingName, os: os)
        }
        let app = object("app") { object -> AppInfo? in
            let bundleID = object.required("bundleID", reader.nonEmptyString)
            let version = object.optional("version", reader.string)
            let build = object.optional("build", reader.string)
            return bundleID.map { AppInfo(bundleID: $0, version: version, build: build) }
        }
        let retake = root.required("retake", reader.nonEmptyString)
        let buttonHeist = object("buttonHeist") { object -> RetakeVersion.ButtonHeist? in
            let version = object.required("version", reader.nonEmptyString)
            let commit = object.optional("commit", reader.string)
            return version.map { RetakeVersion.ButtonHeist(version: $0, commit: commit) }
        }
        let recordedAt = root.required("recordedAt") { value, path -> Date? in
            guard let text = reader.string(value, at: path) else { return nil }
            guard let date = recordedAt(text) else {
                reader.problem("\"\(text)\" isn't a date and time in ISO 8601, such as 2026-11-06T09:30:00Z", at: path)
                return nil
            }
            return date
        }
        let failure = root.optional("failure", reader.string)
        let duration = root.required("duration") { reader.number($0, at: $1, .atLeast(0)) }
        let dimensions = root.required("size", size)
        // A take recorded before Retake logged its screen and frames can't be cut, which is said once.
        let unlogged = ["screen", "frames", "dropped"].filter { !root.has($0) }
        if !unlogged.isEmpty {
            let names = unlogged.map { "\"\($0)\"" }
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            reader.problem("is missing \(list): the take was recorded by an earlier Retake, which didn't log \(names.count == 1 ? "it" : "them"); record the take again", at: .root)
        }
        func recorded<Value>(_ key: String, _ read: (JSONValue, JSONPath) -> Value?) -> Value? {
            unlogged.contains(key) ? nil : root.required(key, read)
        }
        let frames = recorded("frames") { reader.integer($0, at: $1, atLeast: 0) }
        let dropped = recorded("dropped") { reader.integer($0, at: $1, atLeast: 0) }
        // `aspect` is what logs recorded before it was renamed call it, which still read.
        let aspectKey = root.has("aspect") ? "aspect" : "previewAspect"
        if aspectKey == "aspect", root.has("previewAspect") {
            reader.problem("gives both \"previewAspect\" and \"aspect\", its old name; give only \"previewAspect\"", at: .root)
        }
        let previewAspect = root.optional(aspectKey) { SetFile.readAspectChoice($0, $1, reader) }
        let screen = recorded("screen") { value, path -> CGSize? in
            guard let numbers = reader.array(value, at: path, element: { reader.number($0, at: $1, .above(0)) }), numbers.count == 2 else {
                reader.problem("expected [width, height]", at: path)
                return nil
            }
            return CGSize(width: numbers[0], height: numbers[1])
        }
        let launch = root.optional("launch") { value, path -> Launch? in
            guard var object = reader.object(value, at: path) else { return nil }
            defer { object.finish() }
            let launched = object.required("launched") { reader.number($0, at: $1) }
            let reported = object.required("reported") { reader.number($0, at: $1) }
            let connected = object.required("connected") { reader.number($0, at: $1) }
            guard let launched, let reported, let connected else { return nil }
            return Launch(launched: launched, reported: reported, connected: connected)
        }
        let clock = object("clock") { object in Clock(deviceAhead: object.optional("deviceAhead") { reader.number($0, at: $1) }) }
        let steps = root.required("steps") { value, path in
            reader.array(value, at: path) { value, path -> Entry? in
                guard var object = reader.object(value, at: path) else { return nil }
                defer { object.finish() }
                let number = object.required("number") { reader.integer($0, at: $1, atLeast: 1) }
                let id = object.optional("id", reader.nonEmptyString)
                let action = object.required("action", reader.nonEmptyString)
                let start = object.required("start") { reader.number($0, at: $1) }
                let end = object.required("end") { reader.number($0, at: $1) }
                let timedBy = object.required("timedBy") { value, path -> Bool? in
                    guard let text = reader.string(value, at: path) else { return nil }
                    guard text == "device" || text == "mac" else {
                        reader.problem("\"\(text)\" isn't one of \"device\" or \"mac\"", at: path)
                        return nil
                    }
                    return text == "device"
                }
                let touch = object.optional("touch", point)
                let touchEnd = object.optional("touchEnd", point)
                let touchDuration = object.optional("touchDuration") { reader.number($0, at: $1, .atLeast(0)) }
                let elements = object.optional("elements") { value, path in
                    reader.array(value, at: path) { value, path in ScreenElement.read(value, at: path, with: reader) }
                }
                guard let number, let action, let start, let end, let timedBy else { return nil }
                return Entry(number: number, id: id, action: action, start: start, end: end, timedByDevice: timedBy, touch: touch, touchEnd: touchEnd, touchDuration: touchDuration, elements: elements)
            }
        }
        let shapes = root.required("shapes") { value, path in
            reader.array(value, at: path) { value, path -> TakeWriter.ShapeChange? in
                guard var object = reader.object(value, at: path) else { return nil }
                defer { object.finish() }
                let at = object.required("at") { reader.number($0, at: $1, .atLeast(0)) }
                let dimensions = object.required("size", size)
                let turn = object.required("turn") { reader.integer($0, at: $1) }
                guard let at, let dimensions, let turn else { return nil }
                return TakeWriter.ShapeChange(at: at, width: dimensions.0, height: dimensions.1, turn: turn)
            }
        }
        let hitches = root.optional("hitches") { value, path in
            reader.array(value, at: path) { value, path -> Hitch? in
                guard var object = reader.object(value, at: path) else { return nil }
                defer { object.finish() }
                let at = object.required("at") { reader.number($0, at: $1) }
                let duration = object.required("duration") { reader.number($0, at: $1, .atLeast(0)) }
                guard let at, let duration else { return nil }
                return Hitch(at: at, duration: duration)
            }
        }
        guard reader.problems.isEmpty, let scene, let take, let set, let state, let deviceType, let device, let app, let retake,
              let buttonHeist, let recordedAt, let duration, let dimensions, let frames, let dropped, let screen, let clock, let steps,
              let shapes
        else { return nil }
        return TakeLog(
            scene: scene, take: take, set: set, state: state, deviceType: deviceType, device: device, app: app, retake: retake,
            buttonHeist: buttonHeist, recordedAt: recordedAt, failure: failure, duration: duration, width: dimensions.0,
            height: dimensions.1, frames: frames, dropped: dropped, previewAspect: previewAspect, screen: screen, launch: launch, clock: clock, steps: steps, shapes: shapes,
            hitches: hitches,
        )
    }
}

extension ScreenElement {
    /// An element as a step log gives it.
    static func read(_ value: JSONValue, at path: JSONPath, with reader: JSONReader) -> ScreenElement? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let label = object.optional("label", reader.string)
        let value = object.optional("value", reader.string)
        let identifier = object.optional("identifier", reader.string)
        let hint = object.optional("hint", reader.string)
        let traits = object.optional("traits") { reader.array($0, at: $1, element: reader.string) } ?? []
        let frame = object.optional("frame") { value, path -> Rect? in
            guard let numbers = reader.array(value, at: path, element: { reader.number($0, at: $1) }), numbers.count == 4 else {
                reader.problem("expected [x, y, width, height]", at: path)
                return nil
            }
            return Rect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
        let activationPoint = object.optional("activationPoint") { value, path -> Point? in
            guard let numbers = reader.array(value, at: path, element: { reader.number($0, at: $1) }), numbers.count == 2 else {
                reader.problem("expected [x, y]", at: path)
                return nil
            }
            return Point(x: numbers[0], y: numbers[1])
        }
        return ScreenElement(label: label, value: value, identifier: identifier, hint: hint, traits: traits, frame: frame, activationPoint: activationPoint)
    }
}
