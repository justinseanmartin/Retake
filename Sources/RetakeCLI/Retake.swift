import ArgumentParser
import Foundation
import RetakeCore

/// `retake`: the root command. Its contract is Documentation/cli.md.
public struct Retake: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "retake",
        abstract: "Makes App Store preview videos from your running iOS app.",
        version: RetakeVersion.current.version,
        subcommands: [
            Init.self,
            Doctor.self,
            Devices.self,
            Embed.self,
            Install.self,
            Compose.self,
            Record.self,
            Takes.self,
            Clean.self,
            Conform.self,
            Cut.self,
            Status.self,
            Info.self,
            Check.self,
            Validate.self,
            Schema.self,
            Version.self,
        ],
    )

    public init() {}

    /// Runs the command `arguments` name (the process's own when nil) and exits with the status
    /// Documentation/cli.md gives it, which differs from ArgumentParser's own for misuse (2, not 64).
    public static func runAndExit(_ arguments: [String]? = nil) async -> Never {
        let outcome = await run(arguments)
        // What the command printed comes before how it ended, though only standard error is unbuffered.
        fflush(stdout)
        if !outcome.output.isEmpty {
            FileHandle.standardOutput.write(Data((outcome.output + "\n").utf8))
        }
        if !outcome.error.isEmpty {
            FileHandle.standardError.write(Data((outcome.error + "\n").utf8))
        }
        Foundation.exit(outcome.status)
    }

    /// What a command run ends with, before it's printed: what goes to standard output and standard
    /// error at the end (help, a usage message, an error), and the exit status.
    struct Outcome {
        var status: Int32
        var output = ""
        var error = ""
    }

    static func run(_ arguments: [String]?) async -> Outcome {
        do {
            var command = try parseAsRoot(arguments.map(optionalValuesGiven) ?? optionalValuesGiven(Array(CommandLine.arguments.dropFirst())))
            if var command = command as? AsyncParsableCommand {
                try await command.run()
            } else {
                try command.run()
            }
            return Outcome(status: ExitStatus.done.rawValue)
        } catch {
            return outcome(of: error)
        }
    }

    /// `clean`'s `--takes` and `--cuts` may be given without a value, meaning every one, which
    /// ArgumentParser can't parse; each given bare is passed on as `*`, every one, instead.
    static func optionalValuesGiven(_ arguments: [String]) -> [String] {
        guard arguments.first == "clean" else { return arguments }
        return arguments.enumerated().map { index, argument in
            guard Clean.optionalValues.contains(argument) else { return argument }
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            return next == nil || next!.hasPrefix("-") ? "\(argument)=*" : argument
        }
    }

    static func outcome(of error: Error) -> Outcome {
        if let error = error as? RetakeError {
            return Outcome(status: error.status.rawValue, error: "✖ \(error.message)")
        }
        let message = fullMessage(for: error)
        switch exitCode(for: error) {
        case .success:
            // Help and --version, which are printed as the command's output.
            return Outcome(status: ExitStatus.done.rawValue, output: message)
        case .validationFailure:
            return Outcome(status: ExitStatus.usage.rawValue, error: message)
        case let code:
            return Outcome(status: code.rawValue, error: message)
        }
    }
}
