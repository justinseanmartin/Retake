import Foundation
import ThePlans

/// What playing a step comes to: a plan The Button Heist runs in the app, or something Retake does
/// itself. See README.md, "Scenes: the walk through the app".
public enum StepPlay: Equatable, Sendable {
    /// Run in the app, as one plan.
    case heist(HeistPlan)
    /// Sent to the app as one of The Button Heist's direct commands, outside a plan: only a drag
    /// at other than its default speed, which 0.7.1 doesn't admit in a plan.
    case direct(HeistActionCommand)
    /// Turn the device, then wait for the app to turn with it.
    case turn(SceneFile.Orientation)
    /// Save the screen as a still, by this name, as it is now.
    case capture(String)
    /// Nothing but the step's hold.
    case pause

    /// The plan for `step`, its touch at `touch`, and a drag's end at `end`, as the player works
    /// them out where the step gives an element or a share of the screen; or why The Button Heist
    /// can't take it, as a failure (1) naming nothing: the caller names the step. A tap on an element,
    /// or a drag that starts on one, with no offset, is aimed at it wherever The Button Heist finds it.
    public static func make(for step: Step, touch: Point? = nil, end: Point? = nil) throws(RetakeError) -> StepPlay {
        guard let action = step.action else { return .pause }
        do {
            switch action {
            case .tapPoint(let position):
                guard let point = touch ?? position.point(on: nil) else { throw RetakeError(.failed, "its point is a share of a screen whose size isn't known") }
                return .heist(try plan(.oneFingerTap(TapTarget(selection: .coordinate(screenPoint(point))))))
            case .tapElement(let element, let offset) where offset.isNone:
                return .heist(try plan(.oneFingerTap(TapTarget(selection: .element(target(element))))))
            case .tapElement(let element, _):
                guard let touch else { throw RetakeError(.failed, "where it touches, \(element) moved by its offset, wasn't looked for on the screen") }
                return .heist(try plan(.oneFingerTap(TapTarget(selection: .coordinate(screenPoint(touch))))))
            case .drag(let fromSpot, let toSpot, let duration):
                let start: GesturePointSelection
                switch fromSpot {
                case .element(let element, let offset) where offset.isNone: start = .element(target(element))
                case .element(let element, _):
                    guard let touch else { throw RetakeError(.failed, "where it starts, \(element) moved by its offset, wasn't looked for on the screen") }
                    start = .coordinate(try screenPoint(touch))
                case .position(let position):
                    guard let point = touch ?? position.point(on: nil) else { throw RetakeError(.failed, "where it starts is a share of a screen whose size isn't known") }
                    start = .coordinate(try screenPoint(point))
                }
                let to: Point
                switch toSpot {
                case .element(let element, _):
                    guard let end else { throw RetakeError(.failed, "where it ends, \(element), wasn't looked for on the screen") }
                    to = end
                case .position(let position):
                    guard let point = end ?? position.point(on: nil) else { throw RetakeError(.failed, "where it ends is a share of a screen whose size isn't known") }
                    to = point
                }
                guard duration != DragTarget.defaultDuration.seconds else {
                    return .heist(try plan(.drag(DragTarget(start: start, end: try screenPoint(to)))))
                }
                let timed = DragTarget(start: start, end: try screenPoint(to), duration: try GestureDuration(validatingSeconds: duration))
                return .direct(.drag(timed))
            case .type(let text, let into):
                return .heist(try plan(.typeText(TypeTextTarget(text: try TextInputText(validating: text), target: into.map(target)))))
            case .activate(let element):
                return .heist(try plan(.activate(target(element))))
            case .waitFor(let element, let gone, let timeout):
                let predicate: AccessibilityPredicate = gone ? .missing(target(element)) : .exists(target(element))
                return .heist(try HeistPlan(body: [.wait(WaitStep(predicate: predicate, timeout: try WaitTimeout(validatingSeconds: timeout)))]))
            case .orientation(let orientation):
                return .turn(orientation)
            case .capture(let name):
                return .capture(name)
            }
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "The Button Heist can't take it: \(error)")
        }
    }

    /// An action as a plan of its own, expecting nothing of it. The default expectation, that the
    /// action settles, reads the app's accessibility tree on its main thread until it does, which
    /// freezes the recording for up to half a second after a tap on an animating screen.
    static func plan(_ command: HeistActionCommand) throws -> HeistPlan {
        try HeistPlan(body: [.action(ActionStep(command: command, expectationPolicy: .waived(try ActionExpectationWaiver(validating: Self.waiver))))])
    }

    static let waiver = "A recording can't wait for the app to settle: reading the screen freezes it."

    static func screenPoint(_ point: Point) throws -> ScreenPoint {
        ScreenPoint(x: try FiniteCoordinate(validating: point.x), y: try FiniteCoordinate(validating: point.y))
    }

    /// An element as The Button Heist finds it: every field given must match exactly, an empty
    /// `value` matching a field with nothing in it, and `occurrence`, counted from 1, becoming its
    /// ordinal, counted from 0.
    public static func target(_ element: ElementTarget) -> AccessibilityTarget {
        let predicate = ElementPredicate(
            label: element.label.map(StringMatch.exact),
            identifier: element.identifier.map(StringMatch.exact),
            value: element.value.map { $0.isEmpty ? .isEmpty : .exact($0) },
            traits: (element.traits ?? []).compactMap(HeistTrait.init(rawValue:)),
            hint: element.hint.map(StringMatch.exact),
        )
        return .predicate(predicate, ordinal: element.occurrence.map { $0 - 1 })
    }
}

extension Step {
    /// How the step reads in what `record` prints: `tap "New Note"`.
    public var summary: String {
        guard let action else { return "hold \(Self.seconds(hold ?? 0))" }
        switch action {
        case .tapPoint(let position): return "tap \(position)"
        case .tapElement(let element, let offset): return "tap \(Spot.element(element, offset: offset))"
        case .drag(let from, let to, _): return "drag \(from) to \(to)"
        case .type(let text, let into):
            let typed = "type \(JSONWriter.quote(text))"
            return into.map { "\(typed) into \($0)" } ?? typed
        case .activate(let element): return "activate \(element)"
        case .orientation(let orientation): return "turn to \(orientation.rawValue)"
        case .waitFor(let element, let gone, _): return gone ? "wait for \(element) to go" : "wait for \(element)"
        case .capture(let name): return "capture \(JSONWriter.quote(name))"
        }
    }

    /// Its summary with its hold, as `compose` lists steps: `tap "New Note", hold 0.8 s`.
    public var line: String {
        if action != nil, let hold, hold > 0 { "\(summary), hold \(Self.seconds(hold))" } else { summary }
    }

    static func seconds(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) s" : "\(value) s"
    }
}

extension Position: CustomStringConvertible {
    /// `(417, 50%)`.
    public var description: String { "(\(x), \(y))" }
}

extension Length: CustomStringConvertible {
    public var description: String {
        switch self {
        case .points(let points): Point.number(points)
        case .share(let share): "\(Point.number(share * 100))%"
        }
    }
}

extension SpotOffset: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if points != SpotOffset.none.points { parts.append("(\(Point.number(points.x)), \(Point.number(points.y))) points") }
        if percent != SpotOffset.none.percent { parts.append("(\(Point.number(percent.x))%, \(Point.number(percent.y))%) of its size") }
        return parts.isEmpty ? "nothing" : parts.joined(separator: " and ")
    }
}

extension Spot: CustomStringConvertible {
    public var description: String {
        switch self {
        case .position(let position): position.description
        case .element(let element, let offset) where offset.isNone: element.description
        case .element(let element, let offset): "\(element) moved by \(offset)"
        }
    }
}

extension Point: CustomStringConvertible {
    public var description: String { "(\(Self.number(x)), \(Self.number(y)))" }

    /// A coordinate to at most two decimals, as The Button Heist's frames often aren't round:
    /// `728.9`, not `728.9000000000001`.
    static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

extension ElementTarget: CustomStringConvertible {
    /// `"Send"`, or each field named when there's more than a label: `value "Title"`,
    /// `"Delete" (2nd)`.
    public var description: String {
        var parts: [String] = []
        if let label { parts.append(JSONWriter.quote(label)) }
        if let value { parts.append("value \(JSONWriter.quote(value))") }
        if let identifier { parts.append("identifier \(JSONWriter.quote(identifier))") }
        if let hint { parts.append("hint \(JSONWriter.quote(hint))") }
        if let traits { parts.append(traits.joined(separator: " ")) }
        let named = parts.joined(separator: " ")
        guard let occurrence else { return named }
        return "\(named) (\(Self.ordinal(occurrence)))"
    }

    static func ordinal(_ number: Int) -> String {
        let suffix = switch (number % 10, number % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }
}

extension ElementTarget {
    /// The trait names The Button Heist knows, which a scene's `traits` may give.
    static let knownTraits = Set(HeistTrait.allCases.map(\.rawValue))
}
