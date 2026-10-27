import ArgumentParser
import Foundation
import RetakeCore

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Creates a project.",
        discussion: """
            Creates retake.json and beside it the folders sets/, scenes/iphone/, scenes/ipad/ and \
            edits/, in Retake/ unless --config or RETAKE_CONFIG names the file to create, and \
            gitignores the output directory and devices.json. At a terminal, offers to name each device \
            connected. Fails (2) if the configuration file already exists.
            """,
    )

    @Option(
        help: ArgumentHelp(
            "The configuration file to create (default: $RETAKE_CONFIG, then Retake/retake.json). The "
                + "project's folders go beside it.",
            valueName: "path",
        ),
        completion: .file(extensions: ["json"]),
    )
    var config: String?

    @Option(
        help: ArgumentHelp(
            "Where the project's takes, cuts and builds go (default: output/ beside the configuration "
                + "file), written into retake.json as its output.",
            valueName: "dir",
        ),
        completion: .directory,
    )
    var outputDir: String?

    @Option(help: ArgumentHelp("The app's bundle ID.", valueName: "id"))
    var bundleID: String?

    @Option(help: ArgumentHelp("The Xcode scheme that builds the app.", valueName: "name"))
    var scheme: String?

    func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let currentPath = FileManager.default.currentDirectoryPath
        let current = URL(filePath: currentPath, directoryHint: .isDirectory)
        let named = flagOrEnvironment(config, ConfigOption.environmentVariable, in: environment)
        let configuration = try named.map { path($0.value, isDirectory: false, in: currentPath) }
            ?? ProjectInitializer.defaultConfiguration(in: current)
        let result = try ProjectInitializer.initialize(
            configuration: configuration,
            output: outputDir.map { path($0, isDirectory: true, in: currentPath) },
            currentDirectory: current,
            bundleID: bundleID,
            scheme: scheme,
        ) { schemes in
            Prompt.choose("Which scheme builds the app?", from: schemes)
        }
        let project = Project(configuration: result.configuration, settings: result.settings)
        let shown = ProjectInitializer.relativePath(of: project.root, from: current)
        print("Created \(shown)/: \(Project.configurationFileName), sets/, scenes/iphone/, scenes/ipad/ and edits/.")
        if case .scheme(let build)? = result.settings.build {
            print("Builds the \(build.scheme) scheme with xcodebuild.")
        }
        for note in result.notes {
            Console.note(note)
        }
        if Prompt.isInteractive { nameDevices(in: project) }

        if named == nil {
            print(
                "Commands find it from here, or from inside \(shown)/. If you move or rename it, name its "
                    + "\(Project.configurationFileName) with --config or \(ConfigOption.environmentVariable).",
            )
        } else if named?.variable == nil {
            let file = ProjectInitializer.relativePath(of: result.configuration, from: current)
            print("""
                Commands need --config or \(ConfigOption.environmentVariable) to find it. To name it for every \
                command in the repository, add this to a mise.toml in this directory, its root:

                [env]
                \(ConfigOption.environmentVariable) = "{{config_root}}/\(file)"
                """)
        }
    }

    /// Offers to name each device connected that no alias names yet, once through. Nothing here
    /// stops `init`: a device can always be named later with `devices add`.
    private func nameDevices(in project: Project) {
        guard var directory = try? DeviceDirectory.current(project) else { return }
        for device in DeviceNaming.unnamed(in: directory) {
            guard let suggestion = DeviceNaming.suggestedName(for: device, besides: directory.aliases),
                  let name = Prompt.answer("Call \(device.name)\((device.marketingName ?? device.model).map { " (\($0))" } ?? "")", suggesting: suggestion)
            else { continue }
            do {
                let alias = try DeviceNaming.alias(name, for: device.udid, in: directory, finder: ScreenCaptureDevices())
                directory.aliases.aliases.append(alias)
                try directory.aliases.save(to: project.devicesFile)
                print("\"\(alias.name)\" is \(alias.deviceName).")
            } catch {
                Console.warn("\(error.message) Name it later with `retake devices add`.")
            }
        }
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Checks the setup end to end.",
        discussion: """
            Checks Xcode and its tools, the device, signing, the installed app and its embed, and that \
            the app launches and answers. Exits 0 when everything passed, otherwise with the status of \
            the first failure.
            """,
    )

    @OptionGroup var project: ProjectOptions
    @OptionGroup var device: DeviceOptions

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("doctor")
    }
}

struct Devices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lists devices, and names them.",
        discussion: """
            With no subcommand, lists each connected device's name, UDID, type, model, and whether it's \
            wired, and each alias, whether connected or not; then which device commands would use, and \
            what chose it. Needs no project, but reads one's aliases and device when there is one.
            """,
        subcommands: [Add.self, Remove.self],
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var config: ConfigOption

    func run() async throws {
        let project = try config.locateIfPresent()
        let directory = try DeviceDirectory.current(project)
        let choice = DeviceChoice.choose(
            named: flagOrEnvironment(nil, DeviceOptions.environmentVariable, in: ProcessInfo.processInfo.environment)
                .map { ($0.value, $0.variable) },
            configuration: project.flatMap { project in project.settings.device.map { ($0, project.configuration) } },
            connected: directory.recordable.map(\.udid),
        )
        let shown = directory.devices.filter { $0.state == .connected }
        if output.json {
            print(JSONWriter.write(DevicesReport(directory: directory, shown: shown, choice: choice).json), terminator: "")
            return
        }
        if shown.isEmpty {
            print("No devices connected.")
        } else {
            print("Connected:")
            for device in shown {
                let details = [
                    device.type?.rawValue ?? "not an iPhone or iPad",
                    device.marketingName ?? device.model,
                    device.osVersion.map { "iOS \($0)" },
                    device.transport == .wired ? "USB" : "network, so it can't be recorded",
                ].compactMap(\.self)
                print("  \(device.name)  \(device.udid)\n    \(details.joined(separator: ", "))")
            }
        }
        if !directory.aliases.aliases.isEmpty {
            print("Aliases:")
            for alias in directory.aliases.aliases {
                let connected = directory.devices.first { $0.udid == alias.udid }
                let state = connected?.isConnectedByUSB == true ? "connected by USB" : connected?.state == .connected ? "on the network" : "not connected"
                print("  \(alias.name) → \(alias.deviceName), \(state)")
            }
        }
        if let choice {
            let shownAs = switch directory.match(choice.device) {
            case .alias(let alias, _)?: "\(alias.name), \(alias.deviceName)"
            case .device(let device)?: device.name
            case nil: choice.device
            }
            print("→ \(shownAs) (\(choice.reason))")
        } else if directory.recordable.isEmpty {
            print("→ none: no iPhone or iPad is connected by USB")
        } else {
            print("→ none chosen: several are connected; name one with --device or RETAKE_DEVICE")
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Names a device.",
            discussion: """
                Records the device's UDID and its screen-capture identity in the project's \
                devices.json, beside retake.json. Names the device given, or with none given, the one \
                connected; with several, asks which. Fails (2) if the alias is taken, or there's no \
                project. Notes when RETAKE_DEVICE names another device, which the shell's commands will \
                still use.
                """,
        )

        @Argument(help: ArgumentHelp("The name to call the device by.", valueName: "alias"))
        var alias: String

        // Not --device, nor RETAKE_DEVICE: those name the device to use, not which one to name.
        @Argument(
            help: ArgumentHelp(
                "The connected device to name, by UDID or name as devicectl reports it "
                    + "(default: the one connected).",
                valueName: "device",
            ),
        )
        var device: String?

        @OptionGroup var config: ConfigOption

        func run() async throws {
            let project = try config.locate(
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: FileManager.default.currentDirectoryPath,
            )
            var directory = try DeviceDirectory.current(project)
            let alias = try DeviceNaming.alias(self.alias, for: device, in: directory, finder: ScreenCaptureDevices()) { devices in
                let names = devices.map { "\($0.name) (\($0.udid))" }
                guard let chosen = Prompt.choose("Which device should be \"\(self.alias)\"?", from: names) else { return nil }
                return devices[names.firstIndex(of: chosen)!]
            }
            directory.aliases.aliases.append(alias)
            try directory.aliases.save(to: project.devicesFile)
            print("\"\(alias.name)\" is \(alias.deviceName).")
            let environment = ProcessInfo.processInfo.environment
            if let named = environment[DeviceOptions.environmentVariable], !named.isEmpty,
               let note = DeviceChoice.noteAfterNaming(
                   alias: alias.name, udid: alias.udid, name: alias.deviceName,
                   environmentDevice: (named, DeviceOptions.environmentVariable),
               ) {
                Console.note(note)
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Forgets an alias.")

        @Argument(help: ArgumentHelp("The alias to forget.", valueName: "alias"))
        var alias: String

        @OptionGroup var config: ConfigOption

        func run() async throws {
            let file = try config.locate(
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: FileManager.default.currentDirectoryPath,
            ).devicesFile
            var aliases = try DeviceAliases.load(from: file)
            guard let existing = aliases[alias] else {
                throw RetakeError(.usage, "There's no alias \"\(alias)\".")
            }
            aliases.aliases.removeAll { $0.name == alias }
            try aliases.save(to: file)
            print("Forgot \"\(alias)\", which was \(existing.deviceName).")
        }
    }
}

struct Embed: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Adds what Retake needs to a built app, for installing it yourself.",
        discussion: """
            Adds TheInsideJob and Retake's support library to a development-signed .app for iOS \
            devices, records the embed in its Info.plist, and re-signs it. Changes the app in place \
            unless --output says where to write a copy. Needs no project and no device.
            """,
    )

    @Argument(help: ArgumentHelp("The built .app.", valueName: "app"), completion: .directory)
    var app: String

    @Option(help: ArgumentHelp("Where to write the embedded copy, leaving the app as it is.", valueName: "path"))
    var output: String?

    @OptionGroup var signing: SigningOptions

    @OptionGroup var outputFormat: OutputOptions

    func run() async throws {
        let current = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let result = try Embedder.embed(
            URL(filePath: app, directoryHint: .isDirectory, relativeTo: current),
            output: output.map { URL(filePath: $0, directoryHint: .isDirectory, relativeTo: current) },
            signing: signing.overrides(),
            framework: try InsideJobFramework.locate(),
            support: try SupportLibrary.locate(),
        )
        if outputFormat.json {
            print(JSONWriter.write(.object(JSONObject([
                .init(key: "app", value: .string(result.app.path)),
                .init(key: "retake", value: .string(result.record.retakeVersion)),
                .init(key: "supportContract", value: .number(Double(result.record.supportContract))),
                .init(key: "buttonHeist", value: .string(result.record.buttonHeistVersion)),
                .init(key: "identity", value: .string(result.identity)),
                .init(key: "added", value: .array(result.record.added.map(JSONValue.string))),
            ]))), terminator: "")
        } else {
            print(result.app.path)
        }
    }
}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds the app if asked, embeds Retake in it, and installs it.",
        discussion: """
            The app comes from --app, else a build of --scheme, else retake.json's build. Retake embeds \
            into a copy, in the output directory's build/installed/, a clone where the disk allows, and \
            installs that.
            """,
    )

    @Option(help: ArgumentHelp("An already built, development-signed .app.", valueName: "path"), completion: .directory)
    var app: String?

    @Option(help: ArgumentHelp("Build this scheme with xcodebuild.", valueName: "name"))
    var scheme: String?

    @Option(help: ArgumentHelp("The workspace holding --scheme.", valueName: "path"), completion: .directory)
    var workspace: String?

    @Option(help: ArgumentHelp("The project holding --scheme.", valueName: "path"), completion: .directory)
    var xcodeproj: String?

    @Option(help: ArgumentHelp("The build configuration for --scheme (default: Debug).", valueName: "name"))
    var configuration: String?

    @Flag(help: "Let xcodebuild register the device and update profiles on your team.")
    var allowProvisioningUpdates = false

    @OptionGroup var device: DeviceOptions
    @OptionGroup var signing: SigningOptions

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if app != nil, scheme != nil {
            throw ValidationError("Give --app or --scheme, not both.")
        }
        if workspace != nil, xcodeproj != nil {
            throw ValidationError("Give --workspace or --xcodeproj, not both.")
        }
        if scheme == nil {
            if workspace != nil { throw ValidationError("--workspace needs --scheme.") }
            if xcodeproj != nil { throw ValidationError("--xcodeproj needs --scheme.") }
            if configuration != nil { throw ValidationError("--configuration needs --scheme.") }
        }
        if app != nil, allowProvisioningUpdates {
            throw ValidationError(
                "--allow-provisioning-updates only applies when Retake runs xcodebuild, not to --app.",
            )
        }
    }

    func run() async throws {
        let located = try project.locate()
        let current = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        func given(_ path: String) -> URL { URL(filePath: path, relativeTo: current).standardizedFileURL }
        let directory = try DeviceDirectory.current(located)
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        let scheme = self.scheme.map { scheme in
            ProjectSettings.SchemeBuild(
                scheme: scheme,
                container: workspace.map { .workspace(given($0).path) } ?? xcodeproj.map { .project(given($0).path) },
                configuration: configuration,
                allowProvisioningUpdates: allowProvisioningUpdates,
            )
        }
        let source = try Installer.source(app: app.map(given), scheme: scheme, project: located)
        switch source {
        case .scheme(let build, _): print("Building \(build.scheme) for \(target.name)...")
        case .command(let build, _): print("Running \(build.command)...")
        case .app: break
        }
        let built = try Installer.app(from: source, for: target, project: located, allowProvisioningUpdates: allowProvisioningUpdates)

        let folder = Installer.installedFolder(located)
        try? FileManager.default.removeItem(at: folder)
        let result = try Embedder.embed(
            built,
            output: folder.appending(path: built.lastPathComponent, directoryHint: .isDirectory),
            signing: signing.overrides(),
            framework: try InsideJobFramework.locate(),
            support: try SupportLibrary.locate(),
        )
        print("Installing \(built.lastPathComponent) on \(target.name)...")
        try Installer.install(result.app, on: target)
        let bundleID = AppBundle(url: result.app).bundleID ?? "the app"
        print("Installed \(bundleID), with Retake embedded, on \(target.name).")
    }
}
