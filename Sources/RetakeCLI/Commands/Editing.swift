import ArgumentParser
import Foundation
import RetakeCore

struct Cut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Renders videos.",
        discussion: """
            Renders each edit, for each device type it names, from each scene's take, to a ProRes \
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
            throw RetakeError(.usage, "There's no edit \"\(missing)\" (\(located.displayPath(files.editURL(missing))))\(files.whyMissing(files.editURL(missing))).")
        }
        if names.isEmpty, let misnamed = files.misnamedFolder(located.edits) {
            throw RetakeError(.failed, "There are no edits in \(located.displayPath(located.edits)): \(misnamed).")
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
            var prepared: [DeviceType] = []
            for deviceType in types {
                do {
                    try Cutter.prepare(name, for: deviceType, in: located) { Swift.print($0) }
                    prepared.append(deviceType)
                } catch {
                    Swift.print("✖ \(name) (\(deviceType.rawValue)): \(error.message)")
                    worst = max(worst, error.status)
                }
            }
            for deviceType in prepared {
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
        discussion: "Reports; never fails on what it finds, except an earlier Retake's numbered takes, which it refuses.",
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func run() async throws {
        let located = try project.locate()
        try TakeStore.refuseOldLayout(for: DeviceType.allCases, in: located)
        let status = await ProjectStatus.of(located)
        if output.json {
            print(JSONWriter.write(status.json), terminator: "")
        } else {
            StatusOutput.text(status)
        }
    }
}

/// What `status` prints for people; `ProjectStatus.json` is what it prints as JSON.
enum StatusOutput {
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }

    static func text(_ status: ProjectStatus) {
        guard !status.sections.isEmpty else { return print("No scenes, edits or videos yet.") }
        for (index, section) in status.sections.enumerated() {
            if index > 0 { print() }
            print("\(section.type.rawValue):")
            if !section.scenes.isEmpty {
                let width = section.scenes.map(\.name.count).max()!
                func name(_ scene: ProjectStatus.Scene) -> String { scene.name.padding(toLength: width, withPad: " ", startingAt: 0) }
                print("  Scenes")
                for scene in section.scenes {
                    var parts: [String] = []
                    if let take = scene.take {
                        parts.append(take.recorded.map { "take \(date($0.recordedAt))" } ?? "take")
                        if !take.successful { parts.append(take.recorded?.failure.map { "failed: \($0)" } ?? take.problem ?? "failed") }
                    } else {
                        parts.append("no take")
                    }
                    if let previous = scene.previous { parts.append(previous.recorded.map { "previous \(date($0.recordedAt))" } ?? "previous") }
                    if let failed = scene.failed {
                        parts.append((failed.recorded.map { "failed \(date($0.recordedAt))" } ?? "failed") + (failed.recorded?.failure.map { ": \($0)" } ?? ""))
                    }
                    print("    \(name(scene))  \(parts.joined(separator: ", "))")
                }
            }
            if !section.edits.isEmpty {
                let width = section.edits.map(\.name.count).max()!
                func name(_ edit: ProjectStatus.Edit) -> String { edit.name.padding(toLength: width, withPad: " ", startingAt: 0) }
                print("  Edits")
                for edit in section.edits {
                    if let problem = edit.problem {
                        print("    \(name(edit))  can't be read: \(problem)")
                        continue
                    }
                    let uses = edit.uses.map { use in use.recordedAt.map { "\(use.scene) (\(date($0)))" } ?? "\(use.scene) (no successful take)" }
                    print("    \(name(edit))  \(uses.isEmpty ? "uses no scenes" : uses.joined(separator: ", "))")
                }
            }
            if !section.videos.isEmpty {
                let width = section.videos.map(\.file.lastPathComponent.count).max()!
                print("  Videos")
                for video in section.videos {
                    var parts = [video.renderedAt.map { "rendered \(date($0))" } ?? "rendered"]
                    parts.append(video.changes.isEmpty ? "up to date" : "out of date: " + video.changes.joined(separator: "; "))
                    if !video.mixed.isEmpty { parts.append("its takes span more than one of: \(video.mixed.joined(separator: ", "))") }
                    print("    \(video.file.lastPathComponent.padding(toLength: width, withPad: " ", startingAt: 0))  \(parts.joined(separator: ", "))")
                }
            }
        }
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
        var worst = ExitStatus.done
        var records: [JSONValue] = []
        for (index, path) in movies.enumerated() {
            let movie = URL(filePath: path)
            do {
                let info = try await MovieInfo.read(movie)
                if output.json {
                    records.append(info.json(movie: path))
                } else {
                    if index > 0 { print() }
                    print("\(path): " + info.lines.joined(separator: "\n"))
                }
            } catch {
                FileHandle.standardError.write(Data("error: \(path): \(error.message)\n".utf8))
                worst = max(worst, error.status)
            }
        }
        if output.json { print(JSONWriter.write(.array(records)), terminator: "") }
        if worst != .done { throw ExitCode(worst.rawValue) }
    }
}
