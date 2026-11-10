import ArgumentParser
import Foundation
import RetakeCore

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Creates a project.",
        discussion: """
            Creates retake.json and beside it the folders sets/, scenes/iphone/, scenes/ipad/ and \
            edits/, in Retake/ unless --config or RETAKE_CONFIG names the file to create, and \
            gitignores the output directory. At a terminal, offers to name each device \
            connected, then any others connected while it waits. Fails (2) if the configuration file already exists.
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
            "Where the project's takes and cuts go (default: output/ beside the configuration "
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
        if Prompt.isInteractive { nameDevices() }

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
    private func nameDevices() {
        guard var directory = try? DeviceDirectory.current() else { return }
        var offered = Set<String>()
        offer(DeviceNaming.unnamed(in: directory), directory: &directory, offered: &offered)
        while Prompt.confirm("Is there another device to name?") {
            print("Connect it by USB, unlocked and trusting this Mac; waiting up to a minute...")
            var found: [Device] = []
            for _ in 0..<60 {
                guard let now = try? DeviceDirectory.current() else { break }
                directory.devices = now.devices
                found = DeviceNaming.newlyConnected(in: directory, besides: offered)
                if !found.isEmpty { break }
                Thread.sleep(forTimeInterval: 1)
            }
            if found.isEmpty { Console.note("No new iPhone or iPad was connected by USB.") }
            offer(found, directory: &directory, offered: &offered)
        }
    }

    /// Offers to name each of `devices`, saving each alias as it's made.
    private func offer(_ devices: [Device], directory: inout DeviceDirectory, offered: inout Set<String>) {
        for device in devices {
            offered.insert(device.udid)
            guard let suggestion = DeviceNaming.suggestedName(for: device, besides: directory.aliases),
                  let name = Prompt.answer("Call \(device.name)\((device.marketingName ?? device.model).map { " (\($0))" } ?? "")", suggesting: suggestion)
            else { continue }
            do {
                let alias = try DeviceNaming.alias(name, for: device.udid, in: directory, finder: ScreenCaptureDevices())
                directory.aliases.aliases.append(alias)
                try directory.aliases.save(to: DeviceAliases.defaultFile)
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
            Checks Xcode and its tools, the device, signing, the installed app, and that the app \
            launches with Retake and answers. A check that needs one that failed is skipped. Exits 0 \
            when nothing failed, otherwise with the status of the first failure.
            """,
    )

    @OptionGroup var project: ProjectOptions
    @OptionGroup var device: DeviceOptions
    @OptionGroup var output: OutputOptions

    typealias Check = RetakeCore.Doctor.Check

    func run() async throws {
        let located = try project.locate()
        var checks: [Check] = []
        func add(_ check: Check) {
            checks.append(check)
            if !output.json { Self.show(check) }
        }

        add(Self.tools())
        var target: Device?
        if checks.last?.outcome == .failed {
            add(.skipped("device", needing: "Xcode's tools"))
        } else {
            do {
                let (found, chosen) = try device.target(configuration: located.settings.device.map { ($0, located.configuration) })
                add(Self.device(chosen, in: found))
                if checks.last?.outcome != .failed { target = chosen }
            } catch {
                add(.failed("device", error))
            }
        }

        let bundleID = Result { () throws(RetakeError) in try Installer.bundleID(for: located) }
        guard let target else {
            for name in ["signing", "app", "launch"] { add(.skipped(name, needing: "a device")) }
            return try finish(checks)
        }
        switch bundleID {
        case .success(let id): add(Self.signing(bundleID: id, device: target))
        case .failure(let error): add(Check("signing", .warned, "Can't tell which app to check signing for: \(error.message)"))
        }
        switch bundleID {
        case .success(let id):
            if let installed = Launcher.installedVersion(bundleID: id, on: target) {
                let version = [installed.version, installed.build.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
                add(Check("app", .passed, "\(id)\(version.isEmpty ? "" : " \(version)") is installed on \(target.name)."))
            } else {
                add(Check("app", .failed, "\(id) isn't installed on \(target.name); run `retake install`.", status: .environment))
            }
        case .failure(let error):
            add(.failed("app", error))
        }
        if checks.last?.outcome == .failed {
            add(.skipped("launch", needing: "the app installed"))
        } else {
            add(await Self.launch(located, on: target))
        }
        try finish(checks)
    }

    func finish(_ checks: [Check]) throws {
        if output.json {
            print(JSONWriter.write(.array(checks.map { check in
                .object(JSONObject([
                    .init(key: "check", value: .string(check.name)),
                    .init(key: "outcome", value: .string(check.outcome.rawValue)),
                    .init(key: "detail", value: .string(check.detail)),
                ]))
            })), terminator: "")
        }
        let status = RetakeCore.Doctor.status(of: checks)
        guard status == .done else {
            let failed = checks.filter { $0.outcome == .failed }.count
            throw RetakeError(status, "\(failed) check\(failed == 1 ? "" : "s") failed.")
        }
    }

    static func show(_ check: Check) {
        let mark = switch check.outcome {
        case .passed: "✓"
        case .warned: "!"
        case .failed: "✖"
        case .skipped: "-"
        }
        Swift.print("\(mark) \(check.name): \(check.detail)")
    }

    /// Xcode, `devicectl` and `codesign`.
    static func tools() -> Check {
        guard let developer = try? Subprocess.run("/usr/bin/xcode-select", ["-p"]), developer.status == 0 else {
            return Check("tools", .failed, "Xcode isn't installed, or xcode-select doesn't name it.", status: .environment)
        }
        let missing = ["devicectl", "codesign"].filter { tool in
            (try? Subprocess.run("/usr/bin/xcrun", ["--find", tool]))?.status != 0
        }
        let folder = developer.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard missing.isEmpty else {
            return Check("tools", .failed, "\(missing.joined(separator: " and ")) isn't found in \(folder).", status: .environment)
        }
        return Check("tools", .passed, "devicectl and codesign, from \(folder).")
    }

    /// Connected by USB, paired, and its screen offered for capture.
    static func device(_ device: Device, in directory: DeviceDirectory) -> Check {
        let described = "\(device.name) (\([device.marketingName ?? device.model, device.osVersion.map { "iOS \($0)" }].compactMap(\.self).joined(separator: ", ")))"
        guard device.isPaired else {
            return Check("device", .failed, "\(described) isn't paired with this Mac: unlock it, and trust this Mac.", status: .environment)
        }
        let alias = directory.aliases.aliases.first { $0.udid == device.udid }
        let screens = ScreenCaptureDevices().captureDevices(waitingFor: device.name, timeout: 10)
        guard screens.contains(where: { $0.uniqueID == alias?.captureID || $0.name == device.name }) else {
            return Check("device", .failed, "\(described)'s screen isn't offered for recording: is it unlocked?", status: .environment)
        }
        return Check("device", .passed, "\(described), connected by USB, paired, its screen offered for recording.")
    }

    /// A development identity, and a profile that covers the app and the device.
    static func signing(bundleID: String, device: Device) -> Check {
        let listed = (try? Subprocess.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]))?.outputText ?? ""
        let identities = RetakeCore.Doctor.identities(fromFindIdentity: listed)
        guard identities.contains(where: \.isDevelopment) else {
            return Check("signing", .failed, "There's no development signing identity in the keychain; add your account in Xcode.", status: .environment)
        }
        let folders = ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"]
            .map { FileManager.default.homeDirectoryForCurrentUser.appending(path: $0, directoryHint: .isDirectory) }
        let profiles = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".mobileprovision") }
                .compactMap { name in (try? Signing.profile(at: folder.appending(path: name))).flatMap(RetakeCore.Doctor.Profile.init) }
        }
        let (profile, why) = RetakeCore.Doctor.covering(profiles, bundleID: bundleID, udid: device.udid, identities: identities)
        guard let profile else {
            return Check(
                "signing", .failed,
                "\(why) Building with `retake install --allow-provisioning-updates` lets Xcode make one.", status: .environment,
            )
        }
        let until = profile.expires.formatted(date: .abbreviated, time: .omitted)
        let identity = identities.first { $0.isDevelopment && profile.certificates.contains($0.sha1) }
        return Check("signing", .passed, "\(identity?.name ?? "A development identity"), with \"\(profile.name)\" for \(bundleID), until \(until).")
    }

    /// The app launched with Retake, its support library reporting in and The Button Heist answering.
    static func launch(_ project: Project, on device: Device) async -> Check {
        let started = Date()
        do {
            let set = try project.settings.defaultSet.map { name throws(RetakeError) in try AppSession.set(name, in: project, namedBy: "retake.json's defaultSet") }
                ?? ResolvedSet(name: "(none)")
            try await AppSession.run("doctor", in: project, set: set, scene: SceneFile(set: set.name, steps: []), on: device, report: { _ in }) { _, _ in }
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            return Check(
                "launch", .passed,
                "Launched on \(set.name == "(none)" ? "a clean state" : set.name) and cleaned up, in \(seconds) s: Retake's support library "
                    + "(contract \(SupportLibrary.contractVersion)) and The Button Heist \(RetakeVersion.current.buttonHeist.version) answered.",
            )
        } catch {
            return .failed("launch", error)
        }
    }
}

struct Devices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lists devices, and names them.",
        discussion: """
            With no subcommand, lists each connected device's name, UDID, type, model, and whether it's \
            wired, and each alias, whether connected or not; then which device commands would use, and \
            what chose it. Needs no project, but reads one's device when there is one.
            """,
        subcommands: [Add.self, Remove.self],
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var config: ConfigOption

    func run() async throws {
        let project = try config.locateIfPresent()
        let directory = try DeviceDirectory.current()
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
                Records the device's UDID and its screen-capture identity in \
                ~/Library/Caches/retake/devices.json, for every project. Names the device given, or with \
                none given, the one connected; with several, asks which. Fails (2) if the alias is taken. \
                Notes when RETAKE_DEVICE names another device, which the shell's commands will still use.
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

        func run() async throws {
            var directory = try DeviceDirectory.current()
            let alias = try DeviceNaming.alias(self.alias, for: device, in: directory, finder: ScreenCaptureDevices()) { devices in
                let names = devices.map { "\($0.name) (\($0.udid))" }
                guard let chosen = Prompt.choose("Which device should be \"\(self.alias)\"?", from: names) else { return nil }
                return devices[names.firstIndex(of: chosen)!]
            }
            directory.aliases.aliases.append(alias)
            try directory.aliases.save(to: DeviceAliases.defaultFile)
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

        func run() async throws {
            let file = DeviceAliases.defaultFile
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
            into a copy, a clone where the disk allows, kept with the build in \
            ~/Library/Caches/retake/builds/, and installs that.
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

    @Flag(help: "Build as the configuration says, rather than with the compiler's optimization on.")
    var noOptimize = false

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
        if app != nil, noOptimize {
            throw ValidationError("--no-optimize only applies when Retake runs xcodebuild, not to --app.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        let current = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        func given(_ path: String) -> URL { URL(filePath: path, relativeTo: current).standardizedFileURL }
        let target = try device.target(configuration: located.settings.device.map { ($0, located.configuration) }).device
        let scheme = self.scheme.map { scheme in
            ProjectSettings.SchemeBuild(
                scheme: scheme,
                container: workspace.map { .workspace(given($0).path) } ?? xcodeproj.map { .project(given($0).path) },
                configuration: configuration,
                allowProvisioningUpdates: allowProvisioningUpdates,
                optimize: !noOptimize,
            )
        }
        var source = try Installer.source(app: app.map(given), scheme: scheme, project: located)
        if noOptimize, case .scheme(var build, let root) = source {
            build.optimize = false
            source = .scheme(build, root: root)
        } else if noOptimize, case .command = source {
            Console.note("--no-optimize doesn't change a build command's build, which is the project's own.")
        }
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
        guard let bundleID = AppBundle(url: result.app).bundleID else {
            throw RetakeError(.failed, "\(built.lastPathComponent) has no bundle ID in its Info.plist.")
        }
        try Installer.recordInstalled(bundleID: bundleID, in: located)
        print("Installed \(bundleID), with Retake embedded, on \(target.name).")
    }
}
