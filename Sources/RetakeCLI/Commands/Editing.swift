import ArgumentParser
import Foundation
import RetakeCore

struct Cut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Renders videos.",
        discussion: """
            Renders each edit, for each device type it names, from each scene's take, to a ProRes \
            master and an .mp4 for App Store Connect in the output directory's cuts/<type>/<edit>/.
            """,
    )

    @Argument(help: ArgumentHelp("The edits to render.", valueName: "edit"))
    var edits: [String] = []

    @Flag(help: "Render every edit.")
    var all = false

    @Option(help: ArgumentHelp("Only this device type's video.", valueName: "type"))
    var type: DeviceType?

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
                    let result = try await Cutter.cut(name, for: deviceType, in: located) { Swift.print($0) }
                    for warning in result.warnings { Console.warn(warning) }
                    let shown = result.files.map(located.displayPath).joined(separator: " and ")
                    Swift.print("✓ \(name) (\(deviceType.rawValue)): \(String(format: "%.1f", result.duration)) s, in \(shown)")
                    written += result.files.filter { $0.pathExtension == "mp4" }
                } catch {
                    Swift.print("✖ \(name) (\(deviceType.rawValue)): \(error.message)")
                    worst = max(worst, error.status)
                }
            }
            // Against every device type's video of the edit, those cut before too.
            if !prepared.isEmpty, let mismatch = Cutter.lengthMismatch(of: name, await Cutter.lengths(of: name, for: edit.devices, in: located)) {
                Console.warn(mismatch)
            }
        }
        if open, !written.isEmpty {
            _ = try? Subprocess.run("/usr/bin/open", written.map(\.path))
        }
        if worst != .done { throw ExitCode(worst.rawValue) }
    }
}

struct Share: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Makes small videos to share, of cuts or takes side by side.",
        discussion: """
            Writes each video named, its clips joined by +, side by side in the order given, as a \
            small H.264 for sharing, such as on social media, in the output directory's share/. A clip \
            is an edit, for its cut's master, or a scene, for its take, with its device type after a /, \
            or every clip's from --type.
            """,
    )

    @Argument(
        help: ArgumentHelp(
            "Each video to make: clips joined by +, each an edit or a scene and its device type, as showcase/iphone+showcase/ipad.",
            valueName: "clips",
        ),
    )
    var shares: [String] = []

    @Option(help: ArgumentHelp("Every clip's device type, for clips that don't give their own.", valueName: "type"))
    var type: DeviceType?

    @Option(help: ArgumentHelp(
        "Which clip's sound each video has, counting from 1 (default: the first; asked, or required, when its clips' lengths differ).",
        valueName: "n",
    ))
    var audio: Int?

    @Option(help: ArgumentHelp("The colour around and between clips side by side, as #RRGGBB (default: black).", valueName: "color"))
    var background: String?

    @Flag(help: "Open the results.")
    var open = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if shares.isEmpty {
            throw ValidationError("Name what to share, as showcase/iphone\(ProjectFiles.shareJoin)showcase/ipad.")
        }
        if let audio, audio < 1 {
            throw ValidationError("--audio counts a video's clips from 1.")
        }
        if let background, Color(hex: background).map({ $0.alpha < 1 }) ?? true {
            throw ValidationError("--background is a colour as #RRGGBB, not \"\(background)\".")
        }
    }

    func run() async throws {
        let located = try project.locate()
        // Every video is read before any is made, so a mistake in the last fails before the first is written.
        let requests = try shares.map { text throws(RetakeError) in try ShareRequest.parse(text, type: type) }
        if let audio, let (text, request) = zip(shares, requests).first(where: { $0.1.clips.count < audio }) {
            throw RetakeError(.usage, "--audio \(audio) names a clip \(text) doesn't have; it joins \(request.clips.count).")
        }
        let color = background.flatMap(Color.init(hex:)) ?? .black

        var worst = ExitStatus.done
        var written: [URL] = []
        var status: ProjectStatus?
        for (text, request) in zip(shares, requests) {
            do {
                var sources: [Sharer.Source] = []
                for clip in request.clips { sources.append(try await Sharer.source(clip, in: located)) }
                for source in sources where !source.isTake {
                    if status == nil { status = await ProjectStatus.of(located) }
                    let preview = Cutter.folder(source.clip.name, for: source.clip.type, in: located)
                        .appending(path: "\(source.clip.name)-\(source.clip.type.rawValue).mp4").standardizedFileURL
                    let video = status?.sections.first { $0.type == source.clip.type }?.videos.first { $0.file.standardizedFileURL == preview }
                    if let video, !video.changes.isEmpty {
                        Console.warn("\(source.clip)'s cut is out of date: \(video.changes.joined(separator: "; ")); cut it again to share what its edit says now.")
                    }
                }
                let sound = try soundClip(of: text, sources)
                let file = located.shares.appending(path: "\(request.fileName).mp4")
                let shared = try await Sharer.share(sources, audio: sound - 1, background: color, to: file)
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                Swift.print("✓ \(text): \(TakeTimeline.seconds(shared.duration)), \(Int(shared.size.width))×\(Int(shared.size.height)), \(String(format: "%.1f", Double(size) / 1_000_000)) MB, in \(located.displayPath(file))")
                written.append(file)
            } catch let error as RetakeError {
                Swift.print("✖ \(error.message)")
                worst = max(worst, error.status)
            }
        }
        if open, !written.isEmpty {
            _ = try? Subprocess.run("/usr/bin/open", written.map(\.path))
        }
        if worst != .done { throw ExitCode(worst.rawValue) }
    }

    /// Which of `sources`, from 1, the video's sound is from: `--audio`'s, else the first's, unless
    /// another runs more than a second longer, so the first's sound would end well before the
    /// video does; then it's asked, or with no one to ask, required.
    func soundClip(of text: String, _ sources: [Sharer.Source]) throws(RetakeError) -> Int {
        if let audio { return audio }
        let longer = Sharer.outrunning(sources)
        guard !longer.isEmpty, let first = sources.first else { return 1 }
        let clips = sources.map { "\($0.clip), \(TakeTimeline.seconds($0.duration))\($0.hasSound ? "" : ", silent")" }
        let runs = longer.map { "\($0.clip) runs \(TakeTimeline.seconds($0.duration - first.duration)) longer" }.joined(separator: ", ")
        let why = "\(text): \(runs) than \(first.clip), so the first's sound, which it has unless --audio says, would end that much before the video does"
        if Prompt.isInteractive { Console.warn("\(why); give --audio to choose it.") }
        guard let chosen = Prompt.number("Which clip's sound should \(text) have?", from: clips, suggesting: 1) else {
            let asked = Prompt.isInteractive ? "and none was chosen" : "and there's no terminal to ask which"
            throw RetakeError(.usage, "\(why), \(asked): give --audio, from 1 to \(sources.count), or --audio 1 for the first's.")
        }
        return chosen
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
