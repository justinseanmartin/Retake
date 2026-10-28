import ArgumentParser
import Foundation
import RetakeCore

struct Conform: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pins an edit to the latest takes of its scenes.",
        discussion: """
            Pins the latest successful take of each scene the edit uses; to cut from an earlier take, \
            delete the takes after it with clean --takes. Checks every anchor resolves in the new \
            takes, and rewrites the edit in place; fails (1), writing nothing, if one doesn't.
            """,
    )

    @Argument(help: ArgumentHelp("The edit to conform.", valueName: "edit"))
    var edit: String

    @Option(help: ArgumentHelp("Only this device type's pins.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Print the changes without writing them.")
    var dryRun = false

    @OptionGroup var project: ProjectOptions

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("conform")
    }
}

struct Cut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Renders videos.",
        discussion: """
            Renders each edit, for each device type it names, from the takes it pins, to a ProRes \
            master and an .mp4 for App Store Connect in the output directory's cuts/<type>/<edit>/; \
            with --draft, a quick, smaller .mp4 alone.
            """,
    )

    @Argument(help: ArgumentHelp("The edits to render.", valueName: "edit"))
    var edits: [String] = []

    @Flag(help: "Render every edit.")
    var all = false

    @Option(help: ArgumentHelp("Only this device type's video.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Render a quick, smaller H.264 alone: for checking timing, or for sharing where the full size isn't needed.")
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
        let located = try project.locate()
        let files = ProjectFiles(project: located)
        let names = all ? files.names(in: located.edits) : edits
        if let missing = names.first(where: { !FileManager.default.fileExists(atPath: files.editURL($0).path) }) {
            throw RetakeError(.usage, "There's no edit \"\(missing)\" (\(located.displayPath(files.editURL(missing)))).")
        }
        var worst = ExitStatus.done
        var written: [URL] = []
        for name in names {
            let report = ProjectFiles.Report()
            guard let edit = files.readEdit(name, into: report) else {
                Swift.print("✖ \(name): \(report.error.message)")
                worst = max(worst, .failed)
                continue
            }
            let types = edit.devices.filter { type == nil || $0 == type }
            if types.isEmpty, let type {
                Swift.print("✖ \(name) isn't cut for \(type.rawValue).")
                worst = max(worst, .usage)
            }
            for deviceType in types {
                do {
                    let result = try await Cutter.cut(name, for: deviceType, in: located, draft: draft) { Swift.print($0) }
                    for warning in result.warnings { Console.warn(warning) }
                    let shown = result.files.map(located.displayPath).joined(separator: " and ")
                    Swift.print("✓ \(name) (\(deviceType.rawValue)): \(String(format: "%.1f", result.duration)) s, in \(shown)")
                    written += result.files.filter { $0.pathExtension == "mp4" }
                } catch {
                    Swift.print("✖ \(name) (\(deviceType.rawValue)): \(error.message)")
                    worst = max(worst, error.status)
                }
            }
        }
        if open, !written.isEmpty {
            _ = try? Subprocess.run("/usr/bin/open", written.map(\.path))
        }
        if worst != .done { throw ExitCode(worst.rawValue) }
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
