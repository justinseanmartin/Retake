import ArgumentParser
import RetakeCore

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints what's on screen.",
        discussion: """
            Launches the app on a set and prints each element's label, traits, frame and activation \
            point, in screen points.
            """,
    )

    @Option(help: ArgumentHelp("The set to launch on (default: retake.json's defaultSet).", valueName: "set"))
    var set: String?

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Print again whenever the screen changes, until stopped.")
    var watch = false

    @OptionGroup var project: ProjectOptions

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("inspect")
    }
}

struct Rehearse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Plays a scene without recording it.",
        discussion: "Writes nothing. Fails (1) at the first step that doesn't run, naming it.",
    )

    @Argument(help: ArgumentHelp("The scene to play.", valueName: "scene"))
    var scene: String

    @OptionGroup var device: DeviceOptions

    @Option(
        name: .customLong("from"),
        help: ArgumentHelp(
            "Skip to this step, numbered from 1, playing the steps before it without their holds.",
            valueName: "step",
        ),
    )
    var fromStep: Int?

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if let fromStep, fromStep < 1 {
            throw ValidationError("--from numbers steps from 1.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("rehearse")
    }
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Records takes.",
        discussion: """
            With no scenes named, records every scene in scenes/<type>/ with no take yet, or every one \
            with --force. With --for, the scenes an edit uses. Scenes named are recorded whether or not \
            they have takes. A new take never replaces one.
            """,
    )

    @Argument(help: ArgumentHelp("The scenes to record.", valueName: "scene"))
    var scenes: [String] = []

    @Option(name: .customLong("for"), help: ArgumentHelp("Record the scenes this edit uses.", valueName: "edit"))
    var edit: String?

    @Flag(help: "Add a new take to scenes that already have one.")
    var force = false

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Stop at the first scene that fails, rather than carrying on with the next.")
    var stopOnFailure = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if !scenes.isEmpty, edit != nil {
            throw ValidationError("Name scenes or give --for, not both.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("record")
    }
}

struct Takes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lists takes.",
        discussion: "Without --device or --type, lists takes of both device types.",
    )

    @Argument(help: ArgumentHelp("Only this scene's takes.", valueName: "scene"))
    var scene: String?

    @OptionGroup var device: DeviceOptions

    @Option(help: ArgumentHelp("Only this device type's takes.", valueName: "type"))
    var type: DeviceType?

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if device.device != nil, type != nil {
            throw ValidationError("Give --device or --type, not both.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("takes")
    }
}

struct Discard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes a take.",
        discussion: "Fails (1), deleting nothing, if an edit pins one of them.",
    )

    @Argument(help: ArgumentHelp("The scene the takes are of.", valueName: "scene"))
    var scene: String

    @Argument(help: ArgumentHelp("The takes' numbers.", valueName: "take"))
    var takes: [Int]

    @Option(help: ArgumentHelp("The device type the takes are of.", valueName: "type"))
    var type: DeviceType?

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if takes.isEmpty {
            throw ValidationError("Name at least one take.")
        }
        if let take = takes.first(where: { $0 < 1 }) {
            throw ValidationError("Takes are numbered from 1, not \(take).")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("discard")
    }
}

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes takes and videos, or take data left on the device.",
        discussion: """
            Deletes every take and every rendered video, of both device types unless --type names one. \
            Edits' pins are left as they are. With --on-device, deletes instead what Retake leaves in the \
            app's container on the device (takes' copies of its data, and staged set files), which \
            record and rehearse do at the end of a run.
            """,
    )

    @Flag(help: "Delete only takes.")
    var takes = false

    @Flag(help: "Delete only videos.")
    var videos = false

    @Option(help: ArgumentHelp("Only this device type's.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Don't ask first.")
    var yes = false

    @Flag(help: "Delete takes' copies of the app's data, and staged set files, from the device instead.")
    var onDevice = false

    @OptionGroup var device: DeviceOptions
    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if takes, videos {
            throw ValidationError("Give --takes or --videos, not both; with neither, both are deleted.")
        }
        if onDevice, takes || videos || type != nil || yes {
            throw ValidationError(
                "--on-device deletes only what's on the device; it takes no --takes, --videos, --type or --yes.",
            )
        }
        if !onDevice, device.device != nil {
            throw ValidationError("--device applies only with --on-device.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented(onDevice ? "clean --on-device" : "clean")
    }
}
