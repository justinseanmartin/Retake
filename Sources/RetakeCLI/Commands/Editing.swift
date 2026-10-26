import ArgumentParser
import RetakeCore

struct Conform: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pins an edit to newer takes of its scenes.",
        discussion: """
            By default, pins the latest successful take of each scene the edit uses. Checks every \
            anchor resolves in the new takes, and rewrites the edit in place; fails (1), writing \
            nothing, if one doesn't.
            """,
    )

    /// What `--to` pins: the latest take of every scene, or one scene's take.
    enum Target: ExpressibleByArgument, Equatable {
        case latest
        case take(scene: String, take: Int)

        init?(argument: String) {
            if argument == "latest" {
                self = .latest
                return
            }
            let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, let take = Int(parts[1]), take >= 1 else {
                return nil
            }
            self = .take(scene: String(parts[0]), take: take)
        }
    }

    @Argument(help: ArgumentHelp("The edit to conform.", valueName: "edit"))
    var edit: String

    @Option(help: ArgumentHelp("Only this device type's pins.", valueName: "type"))
    var type: DeviceType?

    @Option(
        help: ArgumentHelp(
            "`latest` (the default), or a scene's take as <scene>=<take>, repeated for each scene.",
            valueName: "target",
        ),
    )
    var to: [Target] = []

    @Flag(help: "Print the changes without writing them.")
    var dryRun = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if to.count > 1, to.contains(.latest) {
            throw ValidationError("Give --to latest alone, or --to <scene>=<take> for each scene.")
        }
        var seen = Set<String>()
        for case let .take(scene, _) in to where !seen.insert(scene).inserted {
            throw ValidationError("--to names \(scene) more than once.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("conform")
    }
}

struct Cut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Renders videos.",
        discussion: """
            Renders each edit, for each device type it names, to a ProRes master and an .mp4 for App \
            Store Connect in RetakeOutput/videos/<type>/<video>/.
            """,
    )

    @Argument(help: ArgumentHelp("The edits to render.", valueName: "edit"))
    var edits: [String] = []

    @Flag(help: "Render every edit.")
    var all = false

    @Option(help: ArgumentHelp("Only this device type's video.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Render a quick, smaller H.264 alone, for checking timing.")
    var draft = false

    @Flag(help: "Open the result.")
    var open = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if all, !edits.isEmpty {
            throw ValidationError("Name edits or give --all, not both.")
        }
        if !all, edits.isEmpty {
            throw ValidationError("Name an edit to cut, or give --all.")
        }
        if all, open {
            throw ValidationError("--open opens the edits named; it can't be used with --all.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("cut")
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Summarizes scenes, takes, edits and videos.",
        discussion: "Reports; never fails on what it finds.",
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("status")
    }
}

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints how a take or video was made.",
        discussion: """
            Prints the metadata Retake wrote into each movie, wherever it's been moved to. Fails (1) \
            for a movie Retake didn't write.
            """,
    )

    @Argument(
        help: ArgumentHelp("A take, a master, or an .mp4.", valueName: "movie"),
        completion: .file(extensions: ["mov", "mp4"]),
    )
    var movies: [String]

    @OptionGroup var output: OutputOptions

    func validate() throws {
        if movies.isEmpty {
            throw ValidationError("Name at least one movie.")
        }
    }

    func run() async throws {
        throw RetakeError.notImplemented("info")
    }
}
