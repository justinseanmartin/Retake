import Foundation

/// One line given to `compose`: an action and its options, such as `tap --label "New Note"`. See
/// Documentation/cli.md, "retake compose".
public enum ComposeAction: Equatable, Sendable {
    /// A step to run, and add to the scene when it runs.
    case step(Step)
    /// Print what's on screen, or only the elements that match.
    case inspect(ElementTarget?)
    /// Change the last step's hold, its id, or both.
    case set(hold: Double?, id: String?)
    /// Drop the last steps, as many as given, then launch again and replay the rest.
    case undo(Int)
    /// Launch again and replay every step.
    case replay
    case steps
    case help(String?)
    case quit

    /// What went wrong with a line: options that are missing, which a terminal can ask for, or a
    /// mistake, which it can't.
    public enum Problem: Error, Equatable, Sendable {
        case missing(action: String, [ComposeOption])
        case wrong(String)

        public var message: String {
            switch self {
            case .missing(let action, let options):
                "\(action) needs \(options.map(\.need).joined(separator: ", and ")); `help \(action)` lists its options."
            case .wrong(let message):
                message
            }
        }
    }

    /// Reads one line. Throws `.missing` naming what an action lacks, in the order to ask for them.
    public static func parse(_ line: String) throws(Problem) -> ComposeAction {
        let words = try tokens(line)
        guard let name = words.first else { throw .wrong("Give an action; `help` lists them.") }
        guard let spec = ComposeActionSpec.all.first(where: { $0.name == name }) else {
            throw .wrong("There's no action \"\(name)\"; `help` lists them.")
        }
        // `help tap` and `undo 3` give their one option bare, as a person would type it.
        if name == "help", words.count == 2, !words[1].hasPrefix("--") { return .help(words[1]) }
        if name == "undo", words.count == 2, !words[1].hasPrefix("--") {
            guard let count = Int(words[1]), count >= 1 else { throw .wrong("undo takes how many steps to drop, from 1, not \"\(words[1])\".") }
            return .undo(count)
        }
        let given = try options(Array(words.dropFirst()), for: spec)
        return try spec.build(given)
    }

    /// The words of a line: spaces separate them, and double quotes keep a word's spaces, with `\n`,
    /// `\t`, `\"` and `\\` inside them standing for a return, a tab, a quote and a backslash.
    static func tokens(_ line: String) throws(Problem) -> [String] {
        var words: [String] = []
        var word = "", inWord = false, quoted = false, escaped = false
        for character in line {
            if quoted {
                if escaped {
                    switch character {
                    case "n": word.append("\n")
                    case "t": word.append("\t")
                    default: word.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    quoted = false
                } else {
                    word.append(character)
                }
            } else if character == "\"" {
                quoted = true
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(character)
                inWord = true
            }
        }
        if quoted { throw .wrong("A quote isn't closed.") }
        if inWord { words.append(word) }
        return words
    }

    /// `--name value` pairs, and `--flag`s, checked against the action's options.
    static func options(_ words: [String], for spec: ComposeActionSpec) throws(Problem) -> [String: String] {
        var given: [String: String] = [:]
        var index = 0
        while index < words.count {
            let word = words[index]
            guard word.hasPrefix("--"), let option = spec.options.first(where: { "--\($0.name)" == word }) else {
                if word.hasPrefix("--") {
                    throw .wrong("\(spec.name) has no option \(word); `help \(spec.name)` lists its options.")
                }
                throw .wrong("\"\(word)\" isn't an option; give each as --name, such as --label \"Share\".")
            }
            if given[option.name] != nil { throw .wrong("\(word) is given twice.") }
            if option.isFlag {
                given[option.name] = "true"
                index += 1
            } else {
                guard index + 1 < words.count else { throw .wrong("\(word) needs \(option.value).") }
                given[option.name] = words[index + 1]
                index += 2
            }
        }
        return given
    }
}

/// An option an action takes.
public struct ComposeOption: Equatable, Sendable {
    public var name: String
    /// What its value is, as `help` shows it: `<seconds>`; empty for a flag.
    public var value: String
    public var help: String
    /// What it is when it's not given, for an optional one.
    public var defaultValue: String?

    var isFlag: Bool { value.isEmpty }

    /// How a missing option is named in a message: `--text <text>`, or for an element's options,
    /// "an element (--label, --value or --identifier)".
    public var need: String {
        name == "element" ? "an element (--label, --value, --identifier, --hint or --traits)" : "--\(name) \(value)"
    }

    static func option(_ name: String, _ value: String, _ help: String, default defaultValue: String? = nil) -> ComposeOption {
        ComposeOption(name: name, value: value, help: help, defaultValue: defaultValue)
    }

    static func flag(_ name: String, _ help: String) -> ComposeOption {
        ComposeOption(name: name, value: "", help: help)
    }

    /// Stands for "an element", when one's needed and none was given.
    static let element = ComposeOption(name: "element", value: "", help: "")
}

/// An action `compose` takes: its options, which it needs, and how it becomes an action.
public struct ComposeActionSpec: Sendable {
    public var name: String
    public var summary: String
    /// Every option it takes; `required` names those it needs, in the order to ask for them, the
    /// element as `element`.
    public var options: [ComposeOption]
    public var required: [String]
    /// Whether it's a step, which also takes `--id` and `--hold`.
    public var isStep: Bool
    /// What it needs, said outright, when that's a choice the required list can't say.
    public var needsNote: String? = nil
    let make: @Sendable ([String: String]) throws(ComposeAction.Problem) -> ComposeAction

    func build(_ given: [String: String]) throws(ComposeAction.Problem) -> ComposeAction {
        let missing = required.filter { name in
            name == "element" ? ElementOptions.names.allSatisfy { given[$0] == nil } : given[name] == nil
        }
        if !missing.isEmpty {
            throw .missing(action: self.name, missing.map { name in name == "element" ? .element : options.first { $0.name == name }! })
        }
        let action = try make(given)
        guard case .step(var step) = action else { return action }
        step.id = given["id"]
        if let hold = given["hold"] { step.hold = try Self.number(hold, "--hold", atLeast: 0) }
        return .step(step)
    }

    /// One action's options, as `help <action>` prints them: what it needs, then what's optional,
    /// each with what it is when not given.
    public var usage: String {
        func line(_ option: ComposeOption) -> String {
            let value = option.isFlag ? "" : " \(option.value)"
            return "  --\(option.name)\(value)  \(option.help)\(option.defaultValue.map { " (\($0) if not given)" } ?? "")"
        }
        var lines = ["\(name): \(summary)"]
        let needs = needsNote.map { ["  \($0)"] } ?? required.map { name in
            name == "element" ? "  an element: --label, --value, --identifier, --hint or --traits, one at least" : line(options.first { $0.name == name }!)
        }
        if !needs.isEmpty { lines += ["Required:"] + needs }
        let elementRequired = required.contains("element") || needsNote != nil
        let optional = options.filter { option in
            !required.contains(option.name) && !(elementRequired && ElementOptions.names.contains(option.name)) && !(needsNote != nil && ["x", "y"].contains(option.name))
        }
        if !optional.isEmpty { lines += ["Optional:"] + optional.map(line) }
        return lines.joined(separator: "\n")
    }

    static func number(_ text: String, _ option: String, atLeast minimum: Double? = nil, above floor: Double? = nil) throws(ComposeAction.Problem) -> Double {
        guard let value = Double(text), value.isFinite else { throw .wrong("\(option) takes a number, not \"\(text)\".") }
        if let minimum, value < minimum { throw .wrong("\(option) can't be less than \(Point.number(minimum)).") }
        if let floor, value <= floor { throw .wrong("\(option) must be more than \(Point.number(floor)).") }
        return value
    }

    static func point(_ text: String, _ option: String) throws(ComposeAction.Problem) -> Point {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { throw .wrong("\(option) takes a point as <x>,<y>, such as 120,590.") }
        return Point(x: try number(parts[0], option, atLeast: 0), y: try number(parts[1], option, atLeast: 0))
    }
}

/// An element's options, which several actions take.
enum ElementOptions {
    static let names = ["label", "value", "identifier", "hint", "traits"]
    /// What a terminal asks for when an element is missing, in turn: the ways most elements are named.
    static let asked = ["label", "value", "identifier"]
    static let options: [ComposeOption] = [
        .option("label", "<text>", "its accessibility label"),
        .option("value", "<text>", "its value, such as a text field's placeholder"),
        .option("identifier", "<text>", "its accessibility identifier"),
        .option("hint", "<text>", "its accessibility hint"),
        .option("traits", "<trait>,<trait>", "traits it has, every one, such as header or button,selected"),
        .option("occurrence", "<n>", "which of several that match, from 1", default: "the first"),
    ]
    /// The options that name an element, without `--occurrence`.
    static var naming: [ComposeOption] { options.filter { $0.name != "occurrence" } }

    /// The element given, or nil when none was.
    static func target(_ given: [String: String]) throws(ComposeAction.Problem) -> ElementTarget? {
        guard names.contains(where: { given[$0] != nil }) else {
            if given["occurrence"] != nil { throw .wrong("--occurrence picks one of the elements an element's options match, so give one, such as --label.") }
            return nil
        }
        var occurrence: Int?
        if let text = given["occurrence"] {
            guard let number = Int(text), number >= 1 else { throw .wrong("--occurrence counts from 1, not \"\(text)\".") }
            occurrence = number
        }
        if let label = given["label"], label.isEmpty { throw .wrong("--label can't be empty.") }
        if let identifier = given["identifier"], identifier.isEmpty { throw .wrong("--identifier can't be empty.") }
        if let hint = given["hint"], hint.isEmpty { throw .wrong("--hint can't be empty.") }
        var traits: [String]?
        if let text = given["traits"] {
            let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !names.isEmpty else { throw .wrong("--traits names at least one trait, such as header.") }
            if let unknown = names.first(where: { !ElementTarget.knownTraits.contains($0) }) {
                throw .wrong("\"\(unknown)\" isn't a trait The Button Heist knows; `inspect` shows each element's.")
            }
            traits = names.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        return ElementTarget(label: given["label"], value: given["value"], identifier: given["identifier"], hint: given["hint"], traits: traits, occurrence: occurrence)
    }
}

extension ElementTarget {
    /// As `compose` takes it: `--label "Delete" --traits button --occurrence 2`.
    public var options: String {
        func quoted(_ text: String) -> String {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        }
        var parts: [String] = []
        if let label { parts.append("--label \(quoted(label))") }
        if let value { parts.append("--value \(quoted(value))") }
        if let identifier { parts.append("--identifier \(quoted(identifier))") }
        if let hint { parts.append("--hint \(quoted(hint))") }
        if let traits { parts.append("--traits \(traits.joined(separator: ","))") }
        if let occurrence { parts.append("--occurrence \(occurrence)") }
        return parts.joined(separator: " ")
    }
}

extension ComposeActionSpec {
    static let stepOptions: [ComposeOption] = [
        .option("id", "<name>", "names the step, for edits to anchor to", default: "none"),
        .option("hold", "<seconds>", "the pause after it", default: "the scene's defaultHold"),
    ]

    /// Every action, in the order `help` lists them.
    public static let all: [ComposeActionSpec] = [
        ComposeActionSpec(
            name: "tap", summary: "Taps an element, or a point.",
            options: ElementOptions.options + [.option("x", "<x>", "in screen points"), .option("y", "<y>", "in screen points")] + stepOptions,
            required: [], isStep: true,
            needsNote: "an element (--label, --value, --identifier, --hint or --traits, one at least), or a point (--x <x> --y <y>)",
        ) { given throws(ComposeAction.Problem) in
            if given["x"] != nil || given["y"] != nil {
                guard ElementOptions.names.allSatisfy({ given[$0] == nil }) else { throw .wrong("tap takes an element or --x and --y, not both.") }
                guard let x = given["x"], let y = given["y"] else { throw .wrong("tap at a point needs both --x and --y.") }
                return .step(Step(.tapPoint(Position(Point(x: try number(x, "--x", atLeast: 0), y: try number(y, "--y", atLeast: 0))))))
            }
            guard let element = try ElementOptions.target(given) else {
                throw .missing(action: "tap", [.element])
            }
            return .step(Step(.tapElement(element)))
        },
        ComposeActionSpec(
            name: "drag", summary: "Drags in a straight line from one point to another.",
            options: [
                .option("from", "<x>,<y>", "where it starts, in screen points"),
                .option("to", "<x>,<y>", "where it ends"),
                .option("duration", "<seconds>", "how long it takes", default: "0.5"),
            ] + stepOptions,
            required: ["from", "to"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            let duration = try given["duration"].map { text throws(ComposeAction.Problem) in try number(text, "--duration", above: 0) } ?? Step.defaultDragDuration
            let from = Spot.position(Position(try point(given["from"]!, "--from"))), to = Spot.position(Position(try point(given["to"]!, "--to")))
            return .step(Step(.drag(from: from, to: to, duration: duration)))
        },
        ComposeActionSpec(
            name: "type", summary: "Types text on the on-screen keyboard.",
            options: [.option("text", "<text>", "what to type, in quotes; \\n presses return")] + ElementOptions.options + stepOptions,
            required: ["text"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            guard let text = given["text"], !text.isEmpty else { throw .wrong("--text can't be empty.") }
            return .step(Step(.type(text: text, into: try ElementOptions.target(given))))
        },
        ComposeActionSpec(
            name: "activate", summary: "Activates an element as VoiceOver would, with no touch.",
            options: ElementOptions.options + stepOptions, required: ["element"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            .step(Step(.activate(try ElementOptions.target(given)!)))
        },
        ComposeActionSpec(
            name: "waitFor", summary: "Waits for an element to be on screen, or with --gone, not to be.",
            options: ElementOptions.options + [
                .flag("gone", "waits for it to go instead"),
                .option("timeout", "<seconds>", "how long to wait before failing", default: "10"),
            ] + stepOptions,
            required: ["element"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            let timeout = try given["timeout"].map { text throws(ComposeAction.Problem) in try number(text, "--timeout", above: 0) } ?? Step.defaultWaitTimeout
            if let problem = Step.waitTimeoutProblem(timeout) { throw .wrong("--timeout \(problem).") }
            return .step(Step(.waitFor(try ElementOptions.target(given)!, gone: given["gone"] != nil, timeout: timeout)))
        },
        ComposeActionSpec(
            name: "orientation", summary: "Turns the device, and waits for the app to turn with it.",
            options: [.option("to", "<orientation>", "portrait, portrait-upside-down, landscape-left or landscape-right")] + stepOptions,
            required: ["to"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            guard let orientation = SceneFile.Orientation(rawValue: given["to"]!) else {
                throw .wrong("--to is one of \(SceneFile.Orientation.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            return .step(Step(.orientation(orientation)))
        },
        ComposeActionSpec(
            name: "hold", summary: "A step that's only a pause.",
            options: [.option("seconds", "<seconds>", "how long"), .option("id", "<name>", "names the step", default: "none")],
            required: ["seconds"], isStep: true,
        ) { given throws(ComposeAction.Problem) in
            .step(Step(nil, hold: try number(given["seconds"]!, "--seconds", above: 0)))
        },
        ComposeActionSpec(
            name: "inspect", summary: "Prints what's on screen, or only the elements that match, each with the shortest options that pick it out.",
            options: ElementOptions.naming, required: [], isStep: false,
        ) { given throws(ComposeAction.Problem) in
            .inspect(try ElementOptions.target(given))
        },
        ComposeActionSpec(
            name: "set", summary: "Changes the last step's hold, the pause after it, or its id, for edits to anchor to.",
            options: [.option("hold", "<seconds>", "the pause after it"), .option("id", "<name>", "its id")], required: [], isStep: false,
            needsNote: "--hold <seconds> or --id <name>, or both",
        ) { given throws(ComposeAction.Problem) in
            guard given["hold"] != nil || given["id"] != nil else { throw .wrong("set needs --hold <seconds> or --id <name>, or both.") }
            return .set(hold: try given["hold"].map { text throws(ComposeAction.Problem) in try number(text, "--hold", atLeast: 0) }, id: given["id"])
        },
        ComposeActionSpec(
            name: "undo", summary: "Drops the last step, or with a number, `undo 3`, that many; then launches the app again and replays the rest.",
            options: [], required: [], isStep: false,
        ) { _ in .undo(1) },
        ComposeActionSpec(name: "replay", summary: "Launches the app again and replays every step, dropping none.", options: [], required: [], isStep: false) { _ in .replay },
        ComposeActionSpec(name: "steps", summary: "Lists the scene's steps.", options: [], required: [], isStep: false) { _ in .steps },
        ComposeActionSpec(
            name: "help", summary: "Lists the actions, or one action's options.",
            options: [], required: [], isStep: false,
        ) { _ in .help(nil) },
        ComposeActionSpec(name: "quit", summary: "Ends.", options: [], required: [], isStep: false) { _ in .quit },
    ]

    /// Every action, a line each, as `help` prints them.
    public static var overview: String {
        let width = all.map(\.name.count).max() ?? 0
        return (all.map { "  \($0.name.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.summary)" }
            + ["`help <action>` lists an action's options."]).joined(separator: "\n")
    }
}
