import Foundation

/// A scene, as its file in `scenes/<type>/` says it: a set and the steps played on it. See
/// README.md, "Scenes: the walk through the app".
public struct SceneFile: Equatable, Sendable {
    public enum Orientation: String, CaseIterable, Sendable {
        case portrait
        case portraitUpsideDown = "portrait-upside-down"
        case landscapeLeft = "landscape-left"
        case landscapeRight = "landscape-right"

        public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    }

    /// The set the scene starts on; the project's `defaultSet` when nil.
    public var set: String?
    /// Played before recording starts.
    public var setup: [Step]
    public var steps: [Step]
    /// Seconds recorded before the first step and after the last.
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
        set: String? = nil,
        setup: [Step] = [],
        steps: [Step],
        leadIn: Double = SceneFile.defaultLeadIn,
        tail: Double = SceneFile.defaultTail,
        recordsLaunch: Bool = SceneFile.defaultRecordsLaunch,
        orientation: Orientation = SceneFile.defaultOrientation,
        defaultHold: Double = SceneFile.defaultDefaultHold,
    ) {
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

    public init(id: String? = nil, _ action: Action?, hold: Double? = nil) {
        self.id = id
        self.action = action
        self.hold = hold
    }

    public enum Action: Equatable, Sendable {
        case tapPoint(Position)
        case tapElement(ElementTarget)
        case drag(from: Spot, to: Spot, duration: Double)
        case type(text: String, into: ElementTarget?)
        case activate(ElementTarget)
        case orientation(SceneFile.Orientation)
        case waitFor(ElementTarget, gone: Bool, timeout: Double)

        /// The key a step gives the action under.
        public var key: String {
            switch self {
            case .tapPoint, .tapElement: "tap"
            case .drag: "drag"
            case .type: "type"
            case .activate: "activate"
            case .orientation: "orientation"
            case .waitFor: "waitFor"
            }
        }

        public static let keys = ["tap", "drag", "type", "activate", "orientation", "waitFor"]
    }

    public static let defaultDragDuration = 0.5
    public static let defaultWaitTimeout = 10.0
    public static let defaultGone = false
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
/// point as the screen has it then.
public enum Spot: Equatable, Sendable {
    case position(Position)
    case element(ElementTarget)

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
    public static func read(_ text: String, with reader: JSONReader) -> SceneFile? {
        guard let value = reader.parse(text), var object = reader.root(value, kind: "scene") else { return nil }
        let problemsBefore = reader.problems.count
        let set = object.optional("set", reader.nonEmptyString)
        let setup = object.optional("setup") { readSteps($0, $1, reader, isSetup: true) } ?? []
        let steps = object.required("steps") { readSteps($0, $1, reader, isSetup: false) }
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
        }
        object.finish()
        guard reader.problems.count == problemsBefore, let steps else { return nil }
        return SceneFile(
            set: set, setup: setup, steps: steps,
            leadIn: leadIn, tail: tail, recordsLaunch: recordsLaunch, orientation: orientation, defaultHold: defaultHold,
        )
    }

    static func readSteps(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, isSetup: Bool) -> [Step]? {
        reader.array(value, at: path) { readStep($0, $1, reader, isSetup: isSetup) }
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

    static func isNumberLike(_ id: String) -> Bool {
        Double(id) != nil || id.allSatisfy(\.isNumber)
    }

    static func readStep(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, isSetup: Bool) -> Step? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let problemsBefore = reader.problems.count
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
            let unknown = object.object.keys.filter { !["id", "hold"].contains($0) }
            if hold == nil, !object.has("hold"), unknown.isEmpty {
                reader.problem("has nothing to do: give an action (\(Step.Action.keys.joined(separator: ", "))) or a hold", at: path)
                return nil
            }
            return reader.problems.count == problemsBefore ? Step(id: id, nil, hold: hold ?? 0) : nil
        }
        let action = object.required(key) { readAction(key, $0, $1, reader) }
        guard let action, reader.problems.count == problemsBefore else { return nil }
        return Step(id: id, action, hold: hold)
    }

    static func readAction(_ key: String, _ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Step.Action? {
        switch key {
        case "orientation":
            return reader.choice(value, at: path, as: Orientation.self).map(Step.Action.orientation)
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
            let timeout = object.optional("timeout") { reader.number($0, at: $1, .above(0)) } ?? Step.defaultWaitTimeout
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

    /// A drag's end: a point, `x` and `y`, or an element, not both.
    static func readSpot(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Spot? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        object.know("x", "y", "occurrence")
        object.know(ElementTarget.keys[0], ElementTarget.keys[1], ElementTarget.keys[2])
        object.know(ElementTarget.keys[3], ElementTarget.keys[4])
        let hasPoint = object.object["x"] != nil || object.object["y"] != nil
        let hasElement = (ElementTarget.keys + ["occurrence"]).contains { object.object[$0] != nil }
        if hasPoint, hasElement {
            reader.problem("is a point (\"x\" and \"y\") or an element, not both", at: path)
            return nil
        }
        if hasPoint { return readPosition(&object, reader).map(Spot.position) }
        return readElement(&object, reader).map(Spot.element)
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
