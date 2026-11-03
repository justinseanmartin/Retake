import Foundation
import TheScore

/// What The Button Heist saw of a step on the device: when it began and ended, on the device's own
/// clock, and the screen once it had settled. A take's step log is built from it.
public struct StepEvidence: Equatable, Sendable {
    /// When the screen was read before the step acted, on the device's clock.
    public var began: Date?
    /// When the screen was last read, once the step had settled, or a wait's element had come or
    /// gone, on the device's clock.
    public var ended: Date?
    /// What was on screen at `ended`.
    public var elements: [ScreenElement]?
    /// Where a step on an element touched: the activation point of the element The Button Heist
    /// resolved just before acting on it.
    public var touched: Point?
    /// Where a drag lifted, as the player worked it out.
    public var lifted: Point?
    /// Seconds the action's touch took, from `began`: a tap's press, or a drag from down to up.
    public var interaction: Double?

    public init(began: Date? = nil, ended: Date? = nil, elements: [ScreenElement]? = nil, touched: Point? = nil, interaction: Double? = nil) {
        self.began = began
        self.ended = ended
        self.elements = elements
        self.touched = touched
        self.interaction = interaction
    }

    /// The evidence in a result as The Button Heist encodes it, found by shape rather than by path,
    /// since actions and waits nest it differently: each `observation` holds a `baseline` and a
    /// `current` interface, each with its `timestamp`. The earliest baseline is when the step began;
    /// the latest current interface is when it ended, and what was on screen then. A step on an
    /// element also has its `subjectEvidence`, the element it resolved before acting, and a touch its
    /// `interactionMs`, how long the touch took.
    public static func from(encoded result: some Encodable) -> StepEvidence {
        guard let data = try? JSONEncoder().encode(result), let value = try? JSONParser.parse(String(decoding: data, as: UTF8.self)) else {
            return StepEvidence()
        }
        return from(json: value)
    }

    static func from(json value: JSONValue) -> StepEvidence {
        var baselines: [Double] = []
        var currents: [(time: Double, interface: JSONValue)] = []
        var subject: JSONValue?
        var interaction: Double?
        func walk(_ value: JSONValue) {
            switch value {
            case .object(let object):
                for entry in object.entries {
                    if entry.key == "baseline" || entry.key == "current", let interface = entry.value[path: "interface"],
                       case .number(let time)? = interface[path: "timestamp"] {
                        if entry.key == "baseline" { baselines.append(time) } else { currents.append((time, interface)) }
                    }
                    if entry.key == "subjectEvidence", subject == nil { subject = entry.value[path: "element"] }
                    if entry.key == "interactionMs", interaction == nil, case .number(let ms) = entry.value { interaction = ms / 1000 }
                    walk(entry.value)
                }
            case .array(let values):
                values.forEach(walk)
            default:
                break
            }
        }
        walk(value)
        let latest = currents.max { $0.time < $1.time }
        return StepEvidence(
            began: baselines.min().map(Date.init(timeIntervalSinceReferenceDate:)),
            ended: latest.map { Date(timeIntervalSinceReferenceDate: $0.time) },
            elements: latest.flatMap { interface($0.interface) }?.projectedElements.map(ButtonHeistDriver.element),
            touched: subject.flatMap(element).flatMap { ButtonHeistDriver.element($0).activationPoint },
            interaction: interaction,
        )
    }

    static func element(_ value: JSONValue) -> HeistElement? {
        try? JSONDecoder().decode(HeistElement.self, from: Data(JSONWriter.write(value).utf8))
    }

    static func interface(_ value: JSONValue) -> Interface? {
        try? JSONDecoder().decode(Interface.self, from: Data(JSONWriter.write(value).utf8))
    }
}
