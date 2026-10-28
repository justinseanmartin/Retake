import ArgumentParser
import Foundation
import RetakeCore

/// A flag's value, or when the flag isn't given, its environment variable's, with which variable it
/// came from; empty counts as unset. See Documentation/cli.md, "Environment variables".
func flagOrEnvironment(
    _ flag: String?,
    _ variable: String,
    in environment: [String: String],
) -> (value: String, variable: String?)? {
    if let flag { return (flag, nil) }
    if let value = environment[variable], !value.isEmpty { return (value, variable) }
    return nil
}

/// A path given on the command line or in the environment, relative to the current directory.
func path(_ value: String, isDirectory: Bool, in currentDirectory: String) -> URL {
    URL(
        filePath: value,
        directoryHint: isDirectory ? .isDirectory : .notDirectory,
        relativeTo: URL(filePath: currentDirectory, directoryHint: .isDirectory),
    )
}

/// `--config <path>`, with `RETAKE_CONFIG` standing in when it isn't given; see Documentation/cli.md,
/// "Finding the project".
struct ConfigOption: ParsableArguments {
    static let environmentVariable = "RETAKE_CONFIG"

    @Option(
        help: ArgumentHelp(
            "The project's configuration file (default: $RETAKE_CONFIG, then retake.json or "
                + "Retake/retake.json in the current directory). The project's folders, and relative paths "
                + "in the file, are found beside it.",
            valueName: "path",
        ),
        completion: .file(extensions: ["json"]),
    )
    var config: String?

    /// The project, from the configuration file named, else `retake.json` or `Retake/retake.json` in
    /// the current directory; `output` moves where it writes.
    func locate(
        output: URL? = nil,
        environment: [String: String],
        currentDirectory: String,
    ) throws(RetakeError) -> Project {
        let configuration = flagOrEnvironment(config, Self.environmentVariable, in: environment)
        do {
            let project = try Project.locate(
                configuration: configuration.map { path($0.value, isDirectory: false, in: currentDirectory) },
                output: output,
                currentDirectory: URL(filePath: currentDirectory, directoryHint: .isDirectory),
            )
            for warning in project.warnings { Console.warn(warning.description) }
            return project
        } catch {
            // Say where the path came from, since nothing on the command line names it.
            guard let variable = configuration?.variable else { throw error }
            throw RetakeError(error.status, "\(error.message) (\(variable) names it.)")
        }
    }

    /// For a command that can run outside a project, such as `devices`: the project when a
    /// configuration file is named or one is found unnamed, otherwise nil. A file that's named must
    /// exist.
    func locateIfPresent(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
    ) throws(RetakeError) -> Project? {
        let named = flagOrEnvironment(config, Self.environmentVariable, in: environment) != nil
        let local = Project.unnamedConfiguration(in: URL(filePath: currentDirectory, directoryHint: .isDirectory))
        guard named || local != nil else { return nil }
        return try locate(environment: environment, currentDirectory: currentDirectory)
    }
}

/// `--config <path>` and `--output-dir <dir>`, for commands that run in a project, with
/// `RETAKE_CONFIG` and `RETAKE_OUTPUT_DIR` standing in when they aren't given; see Documentation/cli.md,
/// "Finding the project".
struct ProjectOptions: ParsableArguments {
    static let outputDirEnvironmentVariable = "RETAKE_OUTPUT_DIR"

    @OptionGroup var configOption: ConfigOption

    @Option(
        help: ArgumentHelp(
            "Where to write takes, cuts and builds (default: $RETAKE_OUTPUT_DIR, then the configuration "
                + "file's output, then output/ beside it). It holds the takes edits pin, so somewhere temporary "
                + "loses them when it's cleared.",
            valueName: "dir",
        ),
        completion: .directory,
    )
    var outputDir: String?

    func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
    ) throws(RetakeError) -> Project {
        let output = flagOrEnvironment(outputDir, Self.outputDirEnvironmentVariable, in: environment)
        return try configOption.locate(
            output: output.map { path($0.value, isDirectory: true, in: currentDirectory) },
            environment: environment,
            currentDirectory: currentDirectory,
        )
    }
}

/// `--device <device>`, with `RETAKE_DEVICE` standing in when it isn't given; see Documentation/cli.md,
/// "Choosing a device".
struct DeviceOptions: ParsableArguments {
    static let environmentVariable = "RETAKE_DEVICE"

    @Option(
        help: ArgumentHelp(
            "An alias from `retake devices add`, a UDID, or a device's name as devicectl reports it. "
                + "Defaults to $RETAKE_DEVICE, then the configuration file's device, then the one device "
                + "connected by USB.",
            valueName: "device",
        ),
    )
    var device: String?

    /// The device the command line or the environment names, or nil to fall back to the
    /// configuration file's, then the one device connected.
    func named(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> (device: String, variable: String?)? {
        flagOrEnvironment(device, Self.environmentVariable, in: environment).map { ($0.value, $0.variable) }
    }

    /// The device to use, and what chose it, from what's named, the configuration file's `device`, and
    /// the devices connected by USB; nil when none applies.
    func choice(
        configuration: (device: String, file: URL)?,
        connected: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> DeviceChoice? {
        DeviceChoice.choose(named: named(environment: environment), configuration: configuration, connected: connected)
    }
}

/// `--identity <identity>` and `--profile <path>`, which re-sign an app with something other than
/// what it was signed with, with `RETAKE_SIGNING_IDENTITY` and `RETAKE_PROVISIONING_PROFILE`
/// standing in when they aren't given; see Documentation/cli.md, "retake embed".
struct SigningOptions: ParsableArguments {
    static let identityEnvironmentVariable = "RETAKE_SIGNING_IDENTITY"
    static let profileEnvironmentVariable = "RETAKE_PROVISIONING_PROFILE"

    @Option(
        help: ArgumentHelp(
            "The signing identity, as codesign takes it, instead of the one the app was signed with "
                + "(default: $RETAKE_SIGNING_IDENTITY, then the app's).",
            valueName: "identity",
        ),
    )
    var identity: String?

    @Option(
        help: ArgumentHelp(
            "The provisioning profile, instead of the app's own "
                + "(default: $RETAKE_PROVISIONING_PROFILE, then the app's).",
            valueName: "path",
        ),
        completion: .file(extensions: ["mobileprovision"]),
    )
    var profile: String?

    /// What to sign with in place of the app's own; nil in either field keeps the app's.
    func overrides(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
    ) -> SigningOverrides {
        SigningOverrides(
            identity: flagOrEnvironment(identity, Self.identityEnvironmentVariable, in: environment)?.value,
            profile: flagOrEnvironment(profile, Self.profileEnvironmentVariable, in: environment)
                .map { path($0.value, isDirectory: false, in: currentDirectory) },
        )
    }
}

/// `--json`, for commands that report something; see Documentation/cli.md, "Output".
struct OutputOptions: ParsableArguments {
    @Flag(help: "Print a stable, machine-readable form instead.")
    var json = false
}

extension DeviceType: ExpressibleByArgument {}
