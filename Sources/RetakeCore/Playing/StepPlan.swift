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
    /// Print what's on screen.
    case inspect
    /// Nothing but the step's hold.
    case pause

    /// The plan for `step`, or why The Button Heist can't take it, as a failure (1) naming nothing:
    /// the caller names the step.
    public static func make(for step: Step) throws(RetakeError) -> StepPlay {
        guard let action = step.action else { return .pause }
        do {
            switch action {
            case .tapPoint(let point):
                return .heist(try plan(.oneFingerTap(TapTarget(selection: .coordinate(screenPoint(point))))))
            case .tapElement(let element):
                return .heist(try plan(.oneFingerTap(TapTarget(selection: .element(target(element))))))
            case .drag(let from, let to, let duration):
                let start = GesturePointSelection.coordinate(try screenPoint(from))
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
            case .inspect:
                return .inspect
            }
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "The Button Heist can't take it: \(error)")
        }
    }

    /// An action as a plan of its own, with The Button Heist's default expectation: the action
    /// settles, whether or not it changed anything.
    static func plan(_ command: HeistActionCommand) throws -> HeistPlan {
        try HeistPlan(body: [.action(ActionStep(command: command))])
    }

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
        )
        return .predicate(predicate, ordinal: element.occurrence.map { $0 - 1 })
    }
}

extension Step {
    /// How the step reads in what `record` prints: `tap "New Note"`.
    public var summary: String {
        guard let action else { return "hold \(Self.seconds(hold))" }
        switch action {
        case .tapPoint(let point): return "tap \(point)"
        case .tapElement(let element): return "tap \(element)"
        case .drag(let from, let to, _): return "drag \(from) to \(to)"
        case .type(let text, let into):
            let typed = "type \(JSONWriter.quote(text))"
            return into.map { "\(typed) into \($0)" } ?? typed
        case .activate(let element): return "activate \(element)"
        case .orientation(let orientation): return "turn to \(orientation.rawValue)"
        case .waitFor(let element, let gone, _): return gone ? "wait for \(element) to go" : "wait for \(element)"
        case .inspect: return "inspect"
        }
    }

    static func seconds(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) s" : "\(value) s"
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
