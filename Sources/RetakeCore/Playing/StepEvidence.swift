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

    public init(began: Date? = nil, ended: Date? = nil, elements: [ScreenElement]? = nil) {
        self.began = began
        self.ended = ended
        self.elements = elements
    }

    /// The evidence in a result as The Button Heist encodes it, found by shape rather than by path,
    /// since actions and waits nest it differently: each `observation` holds a `baseline` and a
    /// `current` interface, each with its `timestamp`. The earliest baseline is when the step began;
    /// the latest current interface is when it ended, and what was on screen then.
    public static func from(encoded result: some Encodable) -> StepEvidence {
        guard let data = try? JSONEncoder().encode(result), let value = try? JSONParser.parse(String(decoding: data, as: UTF8.self)) else {
            return StepEvidence()
        }
        return from(json: value)
    }

    static func from(json value: JSONValue) -> StepEvidence {
        var baselines: [Double] = []
        var currents: [(time: Double, interface: JSONValue)] = []
        func walk(_ value: JSONValue) {
            switch value {
            case .object(let object):
                for entry in object.entries {
                    if entry.key == "baseline" || entry.key == "current", let interface = entry.value[path: "interface"],
                       case .number(let time)? = interface[path: "timestamp"] {
                        if entry.key == "baseline" { baselines.append(time) } else { currents.append((time, interface)) }
                    }
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
        )
    }

    static func interface(_ value: JSONValue) -> Interface? {
        try? JSONDecoder().decode(Interface.self, from: Data(JSONWriter.write(value).utf8))
    }
}
