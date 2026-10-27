import Foundation

/// What commands print besides their output: notes and warnings, on standard error, so that
/// output meant for a pipe or `--json` stays clean.
enum Console {
    static func note(_ message: String) {
        FileHandle.standardError.write(Data("note: \(message)\n".utf8))
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }
}

/// Asking a person a question at the terminal, only when there's one to ask.
enum Prompt {
    /// Whether standard input is a terminal someone can answer at.
    static var isInteractive: Bool { isatty(STDIN_FILENO) == 1 }

    /// One of `choices`, picked by number or name, or nil when no one can be asked or no answer
    /// is given.
    static func choose(_ question: String, from choices: [String]) -> String? {
        guard isInteractive else { return nil }
        FileHandle.standardError.write(Data("\(question)\n".utf8))
        for (index, choice) in choices.enumerated() {
            FileHandle.standardError.write(Data("  \(index + 1). \(choice)\n".utf8))
        }
        FileHandle.standardError.write(Data("> ".utf8))
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces), !answer.isEmpty else { return nil }
        if let number = Int(answer), choices.indices.contains(number - 1) { return choices[number - 1] }
        return choices.first { $0 == answer }
    }
}
