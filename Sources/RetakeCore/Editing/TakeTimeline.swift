import Foundation

/// A take's steps on its movie's clock, which an edit's anchors and elements resolve against, the
/// same way while preparing and validating a `cut`. See README.md, "Anchors: times that follow the app".
public struct TakeTimeline: Sendable {
    public let log: TakeLog

    public init(_ log: TakeLog) {
        self.log = log
    }

    /// The screen in points as the device faced `time` seconds into the take: turned from upright
    /// when the frame was wider than tall.
    public func screen(at time: Double) -> CGSize {
        let screen = log.screen
        let shape = log.shapes.last { $0.at <= time + 1e-9 }
        let landscape = shape.map { $0.width > $0.height } ?? false
        return landscape == (screen.width > screen.height) ? screen : CGSize(width: screen.height, height: screen.width)
    }

    /// Why an anchor or element didn't resolve, in a sentence to follow where it's named.
    public struct Unresolved: Error, Equatable, Sendable {
        public var message: String

        init(_ message: String) {
            self.message = message
        }
    }

    /// A step's place: when it starts and ends, and where the gaps either side of it end, the take's
    /// own start and end standing in past the first and last steps; nil where there's no step on
    /// that side, as before `start` or after `end`.
    struct Place {
        var start: Double
        var end: Double
        var previousEnd: Double?
        var nextStart: Double?
    }

    var steps: [TakeLog.Entry] { log.steps.sorted { $0.number < $1.number } }

    func place(of reference: Anchor.StepReference) throws(Unresolved) -> Place {
        let steps = self.steps
        let index: Int
        switch reference {
        case .start:
            return Place(start: 0, end: 0, previousEnd: nil, nextStart: steps.first?.start ?? log.duration)
        case .end:
            return Place(start: log.duration, end: log.duration, previousEnd: steps.last?.end ?? 0, nextStart: nil)
        case .id(let id):
            guard let found = steps.firstIndex(where: { $0.id == id }) else { throw Unresolved("the take has no step \"\(id)\"") }
            index = found
        case .number(let number):
            let found = number > 0 ? number - 1 : steps.count + number
            guard number != 0, steps.indices.contains(found) else {
                throw Unresolved("the take has \(steps.count) step\(steps.count == 1 ? "" : "s"), so there's no step \(number)")
            }
            index = found
        }
        return Place(
            start: steps[index].start, end: steps[index].end,
            previousEnd: index > 0 ? steps[index - 1].end : 0,
            nextStart: index + 1 < steps.count ? steps[index + 1].start : log.duration,
        )
    }

    /// The moment `anchor` names, in seconds from the take's first frame: from its step's start, or
    /// its end with `edge` `end`, its offset in seconds, or its fraction of the way to the
    /// neighbouring step, forward to the next step's start or back to the previous step's end.
    public func time(of anchor: Anchor) throws(Unresolved) -> Double {
        guard case .step(let anchor) = anchor else {
            if case .seconds(let seconds) = anchor { return seconds }
            return 0
        }
        let place = try place(of: anchor.step)
        let reference = anchor.edge == .end ? place.end : place.start
        if let offset = anchor.offset {
            return reference + offset
        }
        if let fraction = anchor.fraction, fraction != 0 {
            let forward = fraction > 0
            guard let toward = forward ? place.nextStart : place.previousEnd else {
                throw Unresolved("a fraction \(forward ? "forward from the take's end" : "back from the take's start") has no step to go toward")
            }
            return reference + abs(fraction) * (toward - reference)
        }
        return reference
    }

    /// The element `target` names, as the screen was read at the latest step to end at or before
    /// `time`, or before any step has, as it was read just before the first step; matched as a
    /// step's target is: the one that matches, or with `occurrence`, the one it picks.
    public func element(_ target: ElementTarget, at time: Double) throws(Unresolved) -> ScreenElement {
        // A step's end is logged to the millisecond, and so is the moment it's asked about.
        let elements: [ScreenElement], when: String
        if let reading = steps.filter({ $0.elements != nil && $0.end <= time + 0.0005 }).max(by: { $0.end < $1.end }),
           let read = reading.elements {
            (elements, when) = (read, "on screen after step \(reading.number), at \(Self.seconds(reading.end))")
        } else if let reading = log.beforeSteps {
            (elements, when) = (reading.elements, "on screen before the first step, at \(Self.seconds(reading.at))")
        } else {
            throw Unresolved("the take has no reading of the screen at or before \(Self.seconds(time))")
        }
        let matches = elements.filter(target.matches)
        let found: ScreenElement
        if let occurrence = target.occurrence {
            guard matches.indices.contains(occurrence - 1) else {
                throw Unresolved("\(matches.count) element\(matches.count == 1 ? "" : "s") \(matches.count == 1 ? "matches" : "match") \(target) \(when), so there's no occurrence \(occurrence)")
            }
            found = matches[occurrence - 1]
        } else {
            guard !matches.isEmpty else { throw Unresolved("\(target) isn't \(when)") }
            guard matches.count == 1 else {
                throw Unresolved("\(matches.count) elements match \(target) \(when); name it more closely, or give occurrence, from 1 to \(matches.count)")
            }
            found = matches[0]
        }
        guard found.frame != nil else { throw Unresolved("\(target) is off screen \(when.dropFirst("on screen ".count))") }
        return found
    }

    public static func seconds(_ value: Double) -> String {
        "\(Point.number((value * 1000).rounded() / 1000)) s"
    }
}
