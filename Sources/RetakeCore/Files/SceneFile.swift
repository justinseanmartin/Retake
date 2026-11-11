import Foundation
import ThePlans

/// A scene, as its file in `scenes/` says it for one device type: a set and the steps played on it.
/// See README.md, "Scenes: the walk through the app".
public struct SceneFile: Equatable, Sendable {
    public enum Orientation: String, CaseIterable, Sendable {
        case portrait
        case portraitUpsideDown = "portrait-upside-down"
        case landscapeLeft = "landscape-left"
        case landscapeRight = "landscape-right"

        public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    }

    /// The device types it plays on.
    public var devices: [DeviceType]
    /// The set the scene starts on; the project's `defaultSet` when nil.
    public var set: String?
    /// Played before recording starts.
    public var setup: [Step]
    public var steps: [Step]
    /// Seconds recorded before the first step and after the last. A scene that records its launch
    /// has its lead-in from once the app is reachable.
    public var leadIn: Double
    public var tail: Double
    /// Whether recording starts before the app launches.
    public var recordsLaunch: Bool
    /// The orientation the device is turned to before the app launches.
    public var orientation: Orientation
    /// The hold of each of `steps` that doesn't give its own.
    public var defaultHold: Double

    public static let defaultLeadIn = 1.0
    public static let defaultTail = 1.0
    public static let defaultRecordsLaunch = false
    public static let defaultOrientation = Orientation.portrait
    /// `defaultHold`'s own default: no pause after a step.
    public static let defaultDefaultHold = 0.0

    public init(
        devices: [DeviceType] = DeviceType.allCases,
        set: String? = nil,
        setup: [Step] = [],
        steps: [Step],
        leadIn: Double = SceneFile.defaultLeadIn,
        tail: Double = SceneFile.defaultTail,
        recordsLaunch: Bool = SceneFile.defaultRecordsLaunch,
        orientation: Orientation = SceneFile.defaultOrientation,
        defaultHold: Double = SceneFile.defaultDefaultHold,
    ) {
        self.devices = devices
        self.set = set
        self.defaultHold = defaultHold
        self.setup = setup
        self.steps = steps
        self.leadIn = leadIn
        self.tail = tail
        self.recordsLaunch = recordsLaunch
        self.orientation = orientation
    }
}

/// One thing a scene does, with the pause after it.
public struct Step: Equatable, Sendable {
    /// The name edits anchor to.
    public var id: String?
    /// What the step does; nil for a step that's only a pause.
    public var action: Action?
    /// Seconds to pause after it; the scene's `defaultHold` when nil.
    public var hold: Double?
    /// Whether the scene was read for a device type the step's `devices` leave out. It isn't played,
    /// but keeps its number, so the steps after it are numbered alike on every type.
    public var isSkipped: Bool

    public init(id: String? = nil, _ action: Action?, hold: Double? = nil, isSkipped: Bool = false) {
        self.id = id
        self.action = action
        self.hold = hold
        self.isSkipped = isSkipped
    }

    public enum Action: Equatable, Sendable {
        case tapPoint(Position)
        case tapElement(ElementTarget)
        case drag(from: Spot, to: Spot, duration: Double)
        case type(text: String, into: ElementTarget?)
        case activate(ElementTarget)
        case orientation(SceneFile.Orientation)
        case waitFor(ElementTarget, gone: Bool, timeout: Double)
        /// Saves the screen as a still, by this name, as it is once the step before has ended and
        /// held: what `record` captures.
        case capture(String)

        /// The key a step gives the action under.
        public var key: String {
            switch self {
            case .tapPoint, .tapElement: "tap"
            case .drag: "drag"
            case .type: "type"
            case .activate: "activate"
            case .orientation: "orientation"
            case .waitFor: "waitFor"
            case .capture: "capture"
            }
        }

        public static let keys = ["tap", "drag", "type", "activate", "orientation", "waitFor", "capture"]

        /// The capture's name, for a step that captures the screen.
        public var capture: String? {
            if case .capture(let name) = self { name } else { nil }
        }
    }

    public static let defaultDragDuration = 0.5
    public static let defaultWaitTimeout = 10.0
    public static let defaultGone = false

    /// What a capture's name may be, as it names the still's file: letters, digits, `-`, `_` and
    /// `.`, starting with a letter or digit.
    public static let capturePattern = "^[A-Za-z0-9][A-Za-z0-9._-]*$"

    /// The environment The Button Heist's longest wait is read from: Retake's own, as The Button
    /// Heist reads it where Retake makes a step's plan; a test gives its own.
    @TaskLocal static var environment = ProcessInfo.processInfo.environment

    /// The Button Heist's longest wait, in seconds, unless `maximumWaitTimeoutVariable` says otherwise.
    public static let defaultMaximumWaitTimeout = WaitTimeout.defaultMaximumSeconds
    public static let maximumWaitTimeoutVariable = WaitTimeout.maximumSecondsEnvironmentKey

    /// The longest `waitFor` The Button Heist takes, in seconds: 60, or what
    /// `BUTTONHEIST_MAX_WAIT_TIMEOUT` gives, of 30 or more, read as The Button Heist reads it. A
    /// longer one would fail only once the step was played.
    public static var maximumWaitTimeout: Double {
        guard let text = environment[maximumWaitTimeoutVariable], let seconds = Double(text), seconds.isFinite, seconds >= 30 else {
            return defaultMaximumWaitTimeout
        }
        return seconds
    }

    /// Why `timeout` is too long for The Button Heist, in a clause to follow its name; nil when it isn't.
    public static func waitTimeoutProblem(_ timeout: Double) -> String? {
        let maximum = maximumWaitTimeout
        guard timeout > maximum else { return nil }
        return "\(Point.number(timeout)) s is longer than The Button Heist waits, at most \(Point.number(maximum)) s; "
            + "\(maximumWaitTimeoutVariable) raises that, set where Retake runs and in the set's environment, for the app"
    }
}

/// How far a drag's end is from its element's activation point: `points`, plus `percent` of the
/// element's width and height, either of them negative for up or left. For an end that isn't on the
/// element itself but placed by it, such as a game piece dropped a piece's height below the cell it
/// lands in.
public struct SpotOffset: Equatable, Sendable {
    public var points: Point
    /// Percentages: 50 is half the element's width or height.
    public var percent: Point

    public init(points: Point = Point(x: 0, y: 0), percent: Point = Point(x: 0, y: 0)) {
        self.points = points
        self.percent = percent
    }

    public static let none = SpotOffset()

    public var isNone: Bool { self == .none }

    /// `point` moved by the offset, its percentages of `size`, the element's width and height.
    public func moving(_ point: Point, size: (width: Double, height: Double)) -> Point {
        Point(
            x: point.x + points.x + percent.x / 100 * size.width,
            y: point.y + points.y + percent.y / 100 * size.height,
        )
    }
}

/// A point on the screen, in its points.
public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A distance on the screen, as a scene or an edit gives it: points, `120`, or a share of the
/// screen's width or height as the device faces, `"50%"`.
public enum Length: Equatable, Sendable {
    case points(Double)
    /// From 0 to 1.
    case share(Double)

    /// In points, along a side `whole` points long.
    public func points(of whole: Double) -> Double {
        switch self {
        case .points(let points): points
        case .share(let share): share * whole
        }
    }

    public var isShare: Bool {
        if case .share = self { true } else { false }
    }
}

/// A point on the screen, each coordinate in points or as a share of the screen.
public struct Position: Equatable, Sendable {
    public var x: Length
    public var y: Length

    public init(x: Length, y: Length) {
        self.x = x
        self.y = y
    }

    public init(_ point: Point) {
        self.init(x: .points(point.x), y: .points(point.y))
    }

    /// In points, on a screen `screen` points across and down as the device faces it: nil for a
    /// share of a screen whose size isn't known.
    public func point(on screen: CGSize?) -> Point? {
        guard x.isShare || y.isShare else { return Point(x: x.points(of: 0), y: y.points(of: 0)) }
        guard let screen else { return nil }
        return Point(x: x.points(of: screen.width), y: y.points(of: screen.height))
    }
}

/// Where a finger comes down or lifts: a position on the screen, or an element, at its activation
/// point as the screen has it then, moved by `offset`.
public enum Spot: Equatable, Sendable {
    case position(Position)
    case element(ElementTarget, offset: SpotOffset = .none)

    /// A point in screen points.
    public static func point(x: Double, y: Double) -> Spot { .position(Position(Point(x: x, y: y))) }

    /// Where it is without looking at the screen: a position given in points.
    public var point: Point? {
        if case .position(let position) = self { position.point(on: nil) } else { nil }
    }
}

/// An element on screen, as VoiceOver knows it: by any of its label, value, identifier, hint and
/// traits, with `occurrence` (from 1) picking one when several match.
public struct ElementTarget: Equatable, Sendable {
    public var label: String?
    public var value: String?
    public var identifier: String?
    public var hint: String?
    /// Traits it must have, every one, by The Button Heist's names: `header`, `button`.
    public var traits: [String]?
    public var occurrence: Int?

    public init(label: String? = nil, value: String? = nil, identifier: String? = nil, hint: String? = nil, traits: [String]? = nil, occurrence: Int? = nil) {
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.occurrence = occurrence
    }

    public static let keys = ["label", "value", "identifier", "hint", "traits"]
}

extension SceneFile {
    /// The scene in a file's text, or nil with problems in `reader`.
    /// The scene `text` says, for `type`: with each of its `iphone` or `ipad` overrides laid over
    /// what they override, as an edit's are, and its steps for other types skipped. Read for no type,
    /// as a file is checked on its own, it's read for each of its device types, each problem said
    /// once, and the first type's scene returned.
    public static func read(_ text: String, with reader: JSONReader, for type: DeviceType? = nil) -> SceneFile? {
        guard let value = reader.parse(text) else { return nil }
        guard case .object(let object) = value else { return read(value, with: reader, for: type) }
        guard let type else {
            var named: [DeviceType] = []
            if case .array(let values)? = object["devices"] {
                named = values.compactMap { if case .string(let name) = $0 { DeviceType(rawValue: name) } else { nil } }
            }
            var first: SceneFile?
            var said = Set<String>()
            for type in named.isEmpty ? DeviceType.allCases : named {
                let typeReader = JSONReader(file: reader.file)
                let scene = read(text, with: typeReader, for: type)
                first = first ?? scene
                for problem in typeReader.problems where said.insert(problem.description).inserted {
                    reader.problem(problem.message, at: problem.path)
                }
            }
            return said.isEmpty ? first : nil
        }
        if !checkDevices(object, reader) { return nil }
        var origins = Origins()
        let merged = Overrides.merge(object, for: type, at: .root, into: .root, origins: &origins, reader: reader)
        let typeReader = JSONReader(file: reader.file)
        let scene = read(.object(merged), with: typeReader, for: type)
        for problem in typeReader.problems {
            let path = problem.about.map { JSONPath(origins.source(of: $0).components.dropLast()) } ?? origins.source(of: problem.path)
            reader.problem(problem.message, at: path)
        }
        return typeReader.problems.isEmpty ? scene : nil
    }

    /// What names device types in a scene names only its own `devices`, as in an edit: an override,
    /// and a step's `devices`. Checked before the overrides are laid, which drops other types'.
    static func checkDevices(_ object: JSONObject, _ reader: JSONReader) -> Bool {
        let problems = reader.problems.count
        let named: Set<DeviceType>
        if let value = object["devices"] {
            guard let devices = DeviceType.readList(value, at: JSONPath.root.appending("devices"), reader) else { return false }
            named = Set(devices)
        } else {
            named = Set(DeviceType.allCases)
        }
        func walk(_ value: JSONValue, at path: JSONPath, inStep: Bool) {
            switch value {
            case .object(let object):
                for entry in object.entries {
                    let at = path.appending(entry.key)
                    if let type = DeviceType(rawValue: entry.key), !named.contains(type) {
                        reader.problem("overrides \(type.rawValue), which isn't one of this scene's devices", at: at)
                    }
                    if inStep, entry.key == "devices", case .array(let values) = entry.value {
                        for (index, value) in values.enumerated() {
                            if case .string(let name) = value, let type = DeviceType(rawValue: name), !named.contains(type) {
                                reader.problem("\"\(name)\" isn't one of this scene's devices", at: at.appending(index))
                            }
                        }
                    }
                    let steps = path.components.isEmpty && (entry.key == "steps" || entry.key == "setup")
                    walk(entry.value, at: at, inStep: false || steps)
                }
            case .array(let values):
                for (index, value) in values.enumerated() { walk(value, at: path.appending(index), inStep: inStep) }
            default:
                break
            }
        }
        walk(.object(object), at: .root, inStep: false)
        return reader.problems.count == problems
    }

    static func read(_ value: JSONValue, with reader: JSONReader, for type: DeviceType?) -> SceneFile? {
        guard var object = reader.root(value, kind: "scene") else { return nil }
        let problemsBefore = reader.problems.count
        let devices = object.optional("devices") { DeviceType.readList($0, at: $1, reader) } ?? DeviceType.allCases
        let set = object.optional("set", reader.nonEmptyString)
        let setup = object.optional("setup") { readSteps($0, $1, reader, isSetup: true, for: type) } ?? []
        let steps = object.required("steps") { readSteps($0, $1, reader, isSetup: false, for: type) }
        let leadIn = object.optional("leadIn") { reader.number($0, at: $1, .atLeast(0)) } ?? defaultLeadIn
        let tail = object.optional("tail") { reader.number($0, at: $1, .atLeast(0)) } ?? defaultTail
        let recordsLaunch = object.optional("recordsLaunch", reader.bool) ?? defaultRecordsLaunch
        let orientation = object.optional("orientation") { reader.choice($0, at: $1, as: Orientation.self) } ?? defaultOrientation
        let defaultHold = object.optional("defaultHold") { reader.number($0, at: $1, .atLeast(0)) } ?? defaultDefaultHold
        if let steps, steps.isEmpty, case .array(let values)? = object.value("steps"), values.isEmpty {
            reader.problem("needs at least one step", at: object.path("steps"))
        }
        // Steps that couldn't be read are left out, so the ids are checked once each has been.
        if let steps, case .array(let values)? = object.value("steps"), steps.count == values.count {
            checkIDs(steps, at: object.path("steps"), reader)
            checkCaptures(steps, at: object.path("steps"), reader)
        }
        object.finish()
        guard reader.problems.count == problemsBefore, let steps else { return nil }
        return SceneFile(
            devices: devices, set: set, setup: setup, steps: steps,
            leadIn: leadIn, tail: tail, recordsLaunch: recordsLaunch, orientation: orientation, defaultHold: defaultHold,
        )
    }

    static func readSteps(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, isSetup: Bool, for type: DeviceType? = nil) -> [Step]? {
        reader.array(value, at: path) { readStep($0, $1, reader, isSetup: isSetup, for: type) }
    }

    /// Ids are unique, can't look like numbers, which anchors count steps by, and can't be `start`
    /// or `end`, which name the take's edges.
    static func checkIDs(_ steps: [Step], at path: JSONPath, _ reader: JSONReader) {
        var first: [String: Int] = [:]
        for (index, step) in steps.enumerated() {
            guard let id = step.id else { continue }
            let at = path.appending(index).appending("id")
            if let earlier = first[id] {
                reader.problem("\"\(id)\" is already steps[\(earlier)]'s id; ids are unique in a scene", at: at)
            } else {
                first[id] = index
            }
        }
    }

    /// Captures are named uniquely, each naming a still of its own, ignoring case, as a Mac's disk
    /// does in the stills' names.
    static func checkCaptures(_ steps: [Step], at path: JSONPath, _ reader: JSONReader) {
        var first: [String: (index: Int, name: String)] = [:]
        for (index, step) in steps.enumerated() {
            guard let name = step.action?.capture else { continue }
            if let earlier = first[name.lowercased()] {
                let same = earlier.name == name ? "" : " (\"\(earlier.name)\", in another case, names the same file)"
                reader.problem("\"\(name)\" is already steps[\(earlier.index)]'s capture\(same); each capture names a still of its own", at: path.appending(index).appending("capture"))
            } else {
                first[name.lowercased()] = (index, name)
            }
        }
    }

    static func isNumberLike(_ id: String) -> Bool {
        Double(id) != nil || id.allSatisfy(\.isNumber)
    }

    static func readStep(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, isSetup: Bool, for type: DeviceType? = nil) -> Step? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let problemsBefore = reader.problems.count
        let devices = object.optional("devices") { value, path in
            reader.array(value, at: path) { reader.choice($0, at: $1, as: DeviceType.self) }.flatMap { devices -> [DeviceType]? in
                guard !devices.isEmpty else {
                    reader.problem("names at least one device type the step plays on", at: path)
                    return nil
                }
                return devices
            }
        }
        let isSkipped = type.map { type in devices.map { !$0.contains(type) } ?? false } ?? false
        let id: String? = object.optional("id") { value, path in
            guard let id = reader.nonEmptyString(value, at: path) else { return nil }
            if isSetup {
                reader.problem("setup steps aren't recorded, so nothing can anchor to them; leave the id out", at: path)
            } else if isNumberLike(id) {
                reader.problem("\"\(id)\" looks like a number, which anchors count steps by; give it a name", at: path)
            } else if id == "start" || id == "end" {
                reader.problem("\"\(id)\" names the take's own \(id), so a step can't have it", at: path)
            }
            return id
        }
        let hold = object.optional("hold") { reader.number($0, at: $1, .atLeast(0)) }
        let given = Step.Action.keys.filter { object.has($0) }
        if given.count > 1 {
            let named = given.map { "\"\($0)\"" }
            reader.problem("does one thing, so \(named.dropLast().joined(separator: ", ")) and \(named.last!) can't be given together", at: path)
            return nil
        }
        guard let key = given.first else {
            // A misspelled action is reported as an unknown key, which says more than this would.
            let unknown = object.object.keys.filter { !["id", "hold", "devices"].contains($0) }
            if hold == nil, !object.has("hold"), unknown.isEmpty {
                reader.problem("has nothing to do: give an action (\(Step.Action.keys.joined(separator: ", "))) or a hold", at: path)
                return nil
            }
            return reader.problems.count == problemsBefore ? Step(id: id, nil, hold: hold ?? 0, isSkipped: isSkipped) : nil
        }
        if isSetup, key == "capture" {
            reader.problem("setup steps aren't recorded, so nothing is captured in them; move it into the steps", at: path.appending(key))
            return nil
        }
        let action = object.required(key) { readAction(key, $0, $1, reader) }
        guard let action, reader.problems.count == problemsBefore else { return nil }
        return Step(id: id, action, hold: hold, isSkipped: isSkipped)
    }

    static func readAction(_ key: String, _ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Step.Action? {
        switch key {
        case "orientation":
            return reader.choice(value, at: path, as: Orientation.self).map(Step.Action.orientation)
        case "capture":
            guard let name = reader.nonEmptyString(value, at: path) else { return nil }
            guard name.wholeMatch(of: try! Regex(Step.capturePattern)) != nil else {
                reader.problem("\"\(name)\" names the still's file, so it's letters, digits, -, _ and ., starting with a letter or digit", at: path)
                return nil
            }
            return .capture(name)
        default:
            break
        }
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        switch key {
        case "tap":
            object.know("x", "y", "occurrence")
            object.know(ElementTarget.keys[0], ElementTarget.keys[1], ElementTarget.keys[2])
            let hasPoint = object.object["x"] != nil || object.object["y"] != nil
            let hasElement = (ElementTarget.keys + ["occurrence"]).contains { object.object[$0] != nil }
            if hasPoint, hasElement {
                reader.problem("taps a point (\"x\" and \"y\") or an element, not both", at: path)
                return nil
            }
            if hasPoint { return readPosition(&object, reader).map(Step.Action.tapPoint) }
            return readElement(&object, reader).map(Step.Action.tapElement)
        case "activate":
            return readElement(&object, reader).map(Step.Action.activate)
        case "drag":
            let from = object.required("from") { readSpot($0, $1, reader) }
            let to = object.required("to") { readSpot($0, $1, reader) }
            let duration = object.optional("duration") { reader.number($0, at: $1, .above(0)) } ?? Step.defaultDragDuration
            guard let from, let to else { return nil }
            return .drag(from: from, to: to, duration: duration)
        case "type":
            let text = object.required("text") { value, path -> String? in
                guard let text = reader.string(value, at: path) else { return nil }
                guard !text.isEmpty else {
                    reader.problem("can't be empty", at: path)
                    return nil
                }
                return text
            }
            let into = object.optional("into") { value, path in reader.object(value, at: path).flatMap { var element = $0; defer { element.finish() }; return readElement(&element, reader) } }
            guard let text else { return nil }
            if object.has("into"), into == nil { return nil }
            return .type(text: text, into: into)
        case "waitFor":
            let gone = object.optional("gone", reader.bool) ?? Step.defaultGone
            let timeout = object.optional("timeout") { value, path -> Double? in
                guard let timeout = reader.number(value, at: path, .above(0)) else { return nil }
                if let problem = Step.waitTimeoutProblem(timeout) {
                    reader.problem(problem, at: path)
                    return nil
                }
                return timeout
            } ?? Step.defaultWaitTimeout
            return readElement(&object, reader).map { .waitFor($0, gone: gone, timeout: timeout) }
        default:
            return nil
        }
    }

    static func readPosition(_ object: inout ObjectReader, _ reader: JSONReader) -> Position? {
        let x = object.required("x") { readLength($0, $1, reader) }
        let y = object.required("y") { readLength($0, $1, reader) }
        guard let x, let y else { return nil }
        return Position(x: x, y: y)
    }

    /// Points, at least 0 (or above it), or a percentage of the screen from 0% to 100%, as a string.
    static func readLength(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, aboveZero: Bool = false) -> Length? {
        guard case .string(let text) = value else {
            return reader.number(value, at: path, aboveZero ? .above(0) : .atLeast(0)).map(Length.points)
        }
        guard text.hasSuffix("%"), let percent = Double(text.dropLast()), percent.isFinite, percent >= 0, percent <= 100, !(aboveZero && percent == 0),
              text.first?.isNumber == true else {
            reader.problem("is a number of points, or a percentage of the screen\(aboveZero ? " above 0%" : "") up to 100%, such as \"50%\"", at: path)
            return nil
        }
        return .share(percent / 100)
    }

    /// A drag's end: a point, `x` and `y`, or an element, not both, with an element's `offset` and
    /// `offsetPercent`.
    static func readSpot(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Spot? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        object.know("x", "y", "occurrence")
        object.know(ElementTarget.keys[0], ElementTarget.keys[1], ElementTarget.keys[2])
        object.know(ElementTarget.keys[3], ElementTarget.keys[4])
        object.know("offset", "offsetPercent")
        let hasPoint = object.object["x"] != nil || object.object["y"] != nil
        let hasElement = (ElementTarget.keys + ["occurrence"]).contains { object.object[$0] != nil }
        let hasOffset = object.object["offset"] != nil || object.object["offsetPercent"] != nil
        if hasPoint, hasElement {
            reader.problem("is a point (\"x\" and \"y\") or an element, not both", at: path)
            return nil
        }
        if hasPoint {
            if hasOffset {
                reader.problem("offset and offsetPercent move an element's activation point; a point is given where it's meant", at: path)
                return nil
            }
            return readPosition(&object, reader).map(Spot.position)
        }
        let problems = reader.problems.count
        let points = object.optional("offset") { readOffset($0, $1, reader) }
        let percent = object.optional("offsetPercent") { readOffset($0, $1, reader) }
        guard let element = readElement(&object, reader), reader.problems.count == problems else { return nil }
        return .element(element, offset: SpotOffset(points: points ?? Point(x: 0, y: 0), percent: percent ?? Point(x: 0, y: 0)))
    }

    /// `x` and `y`, numbers of either sign.
    static func readOffset(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Point? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let x = object.required("x") { reader.number($0, at: $1) }
        let y = object.required("y") { reader.number($0, at: $1) }
        guard let x, let y else { return nil }
        return Point(x: x, y: y)
    }

    /// An element named by any of `label`, `value`, `identifier`, `hint` and `traits`, at least one.
    static func readElement(_ object: inout ObjectReader, _ reader: JSONReader) -> ElementTarget? {
        let target = ElementTarget(
            label: object.optional("label", reader.nonEmptyString),
            value: object.optional("value", reader.string),
            identifier: object.optional("identifier", reader.nonEmptyString),
            hint: object.optional("hint", reader.nonEmptyString),
            traits: object.optional("traits") { readTraits($0, $1, reader) },
            occurrence: object.optional("occurrence") { reader.integer($0, at: $1, atLeast: 1) },
        )
        let given = ElementTarget.keys.filter { object.object[$0] != nil }
        guard !given.isEmpty else {
            reader.problem("needs an element to name: its \"label\", \"value\", \"identifier\", \"hint\" or \"traits\"", at: object.path)
            return nil
        }
        // A field given but wrong has its problem already.
        let read: [String: Bool] = [
            "label": target.label != nil, "value": target.value != nil, "identifier": target.identifier != nil,
            "hint": target.hint != nil, "traits": target.traits != nil,
        ]
        guard given.allSatisfy({ read[$0] == true }) else { return nil }
        if object.has("occurrence"), target.occurrence == nil { return nil }
        return target
    }

    /// Traits by The Button Heist's names, at least one, each named once.
    static func readTraits(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [String]? {
        let problems = reader.problems.count
        guard let names = reader.array(value, at: path, element: { value, path -> String? in
            guard let name = reader.string(value, at: path) else { return nil }
            guard ElementTarget.knownTraits.contains(name) else {
                reader.problem("\"\(name)\" isn't a trait The Button Heist knows; `retake compose` shows each element's", at: path)
                return nil
            }
            return name
        }), reader.problems.count == problems else { return nil }
        guard !names.isEmpty else {
            reader.problem("needs at least one trait", at: path)
            return nil
        }
        if let repeated = names.first(where: { name in names.filter { $0 == name }.count > 1 }) {
            reader.problem("names \"\(repeated)\" more than once", at: path)
            return nil
        }
        return names
    }
}
