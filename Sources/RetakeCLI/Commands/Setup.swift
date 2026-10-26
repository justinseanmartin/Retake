import ArgumentParser
import RetakeCore

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Creates a project.",
        discussion: """
            Creates retake.json and the folders sets/, scenes/iphone/, scenes/ipad/ and edits/ in the \
            current directory, and adds RetakeOutput/ to .gitignore. Fails (2) if retake.json already exists.
            """,
    )

    @Option(help: ArgumentHelp("The app's bundle ID.", valueName: "id"))
    var bundleID: String?

    @Option(help: ArgumentHelp("The Xcode scheme that builds the app.", valueName: "name"))
    var scheme: String?

    func run() async throws {
        throw RetakeError.notImplemented("init")
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
            what chose it. Needs no project, but reads the configuration file's device when there is one.
            """,
        subcommands: [Add.self, Remove.self],
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var config: ConfigOption

    func run() async throws {
        _ = try config.locateIfPresent()
        throw RetakeError.notImplemented("devices")
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Names a device.",
            discussion: """
                Records the device's UDID and its screen-capture identity in \
                ~/.config/retake/devices.json. Names the device given, or with none given, the one \
                connected; with several, asks which. Fails (2) if the alias is taken. Notes when \
                RETAKE_DEVICE names another device, which the shell's commands will still use.
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
            throw RetakeError.notImplemented("devices add")
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Forgets an alias.")

        @Argument(help: ArgumentHelp("The alias to forget.", valueName: "alias"))
        var alias: String

        func run() async throws {
            throw RetakeError.notImplemented("devices remove")
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
        throw RetakeError.notImplemented("embed")
    }
}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds the app if asked, embeds Retake in it, and installs it.",
        discussion: """
            The app comes from --app, else a build of --scheme, else retake.json's build. Retake embeds \
            into a copy, in RetakeOutput/build/, and installs that.
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
        _ = try project.locate()
        throw RetakeError.notImplemented("install")
    }
}
