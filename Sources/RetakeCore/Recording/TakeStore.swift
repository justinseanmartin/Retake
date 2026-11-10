import Foundation

/// Takes on disk, as `record` keeps them, `takes` lists them and `clean` deletes them. A scene has,
/// for each device type, in `output/takes/<type>/`: its take, `<scene>.mov` with its step log
/// `<scene>.json`, the latest that succeeded, which edits are cut from; the take that one replaced,
/// `<scene>.previous.*`; and its latest failure, `<scene>.failed.*`, until a take succeeds. See
/// Documentation/cli.md, "retake takes" and "retake clean".
public enum TakeStore {
    /// Which of a scene's takes it is.
    public enum Kind: String, CaseIterable, Sendable {
        /// The latest successful take, which edits are cut from.
        case take
        /// The take the current one replaced, for `takes --restore` to put back.
        case previous
        /// The latest take that failed, kept to show what went wrong.
        case failed

        /// What follows the scene in its files' names: nothing, `.previous` or `.failed`.
        public var suffix: String { self == .take ? "" : ".\(rawValue)" }
    }

    /// What follows the scene in the names of a take still being recorded, which is renamed into
    /// place once it's done.
    static let recordingSuffix = ".recording"
    /// What follows it in a take's names while `takes --restore` swaps it with the previous one.
    static let restoringSuffix = ".restoring"

    /// A take: its movie and step log, either of which may be missing, and what its step log says.
    public struct Take: Equatable, Sendable {
        public var type: DeviceType
        public var scene: String
        public var kind: Kind
        public var movie: URL
        public var log: URL
        /// What the step log says; nil when it's missing or can't be read, `problem` saying why.
        public var recorded: TakeLog?
        public var problem: String?
        /// The edits cut from it, by name: those that use its scene, when it's the scene's take.
        public var usedBy: [String] = []

        /// A take that failed, or whose step log can't say it didn't, which no edit is cut from.
        public var failed: Bool { recorded == nil || recorded?.failure != nil }
        /// A complete take whose recording succeeded and whose movie and log can both be read.
        public var successful: Bool { !failed && problem == nil }

        /// How messages name it: `create-note`, `create-note (previous)`, `create-note (failed)`.
        public var name: String { kind == .take ? scene : "\(scene) (\(kind.rawValue))" }
    }

    /// A take's movie and step log in a device type's takes folder: `<scene><suffix>.mov` and `.json`.
    static func files(of scene: String, _ suffix: String, in folder: URL) -> (movie: URL, log: URL) {
        (folder.appending(path: "\(scene)\(suffix).mov"), folder.appending(path: "\(scene)\(suffix).json"))
    }

    /// The scene and kind a file in a takes folder belongs to, from its name; nil for one that isn't
    /// a take's, or is one being recorded or restored.
    static func parse(_ name: String) -> (scene: String, kind: Kind)? {
        let url = URL(filePath: name)
        guard !name.hasPrefix("."), ["json", "mov"].contains(url.pathExtension) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        if base.hasSuffix(recordingSuffix) || base.hasSuffix(restoringSuffix) { return nil }
        for kind in [Kind.previous, .failed] where base.hasSuffix(kind.suffix) {
            let scene = String(base.dropLast(kind.suffix.count))
            return scene.isEmpty ? nil : (scene, kind)
        }
        return (base, .take)
    }

    /// Every take of `scene`, or of every scene, for each of `types` in turn: by scene, then its
    /// take, previous and failure.
    public static func takes(of scene: String? = nil, for types: [DeviceType], in project: Project) -> [Take] {
        let users = users(in: project)
        return types.flatMap { type -> [Take] in
            let folder = project.takes(for: type)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            var found = Set<String>()
            var keys: [(scene: String, kind: Kind)] = []
            for name in names {
                guard let (fileScene, kind) = parse(name), scene == nil || fileScene == scene,
                      found.insert("\(fileScene)\(kind.suffix)").inserted else { continue }
                keys.append((fileScene, kind))
            }
            keys.sort { ($0.scene, Kind.allCases.firstIndex(of: $0.kind)!) < ($1.scene, Kind.allCases.firstIndex(of: $1.kind)!) }
            return keys.map { key in
                var take = take(key.scene, key.kind, for: type, in: folder, project: project)
                if key.kind == .take, take.successful { take.usedBy = users[SceneKey(type: type, scene: key.scene)] ?? [] }
                return take
            }
        }
    }

    /// The take of `scene` that edits are cut from, if it has one, whether or not it can be read.
    public static func take(of scene: String, for type: DeviceType, in project: Project) -> Take? {
        let folder = project.takes(for: type)
        let (movie, log) = files(of: scene, Kind.take.suffix, in: folder)
        guard [movie, log].contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        return take(scene, .take, for: type, in: folder, project: project)
    }

    static func take(_ scene: String, _ kind: Kind, for type: DeviceType, in folder: URL, project: Project) -> Take {
        let (movie, log) = files(of: scene, kind.suffix, in: folder)
        var recorded: TakeLog?, problem: String?
        if let data = FileManager.default.contents(atPath: log.path) {
            let reader = JSONReader(file: project.displayPath(log))
            recorded = TakeLog.read(String(decoding: data, as: UTF8.self), with: reader)
            if recorded == nil { problem = reader.problems.map(\.description).joined(separator: "\n") }
        } else {
            problem = "\(project.displayPath(log)) is missing"
        }
        if recorded != nil, !FileManager.default.fileExists(atPath: movie.path) { problem = "\(project.displayPath(movie)) is missing" }
        return Take(type: type, scene: scene, kind: kind, movie: movie, log: log, recorded: recorded, problem: problem)
    }

    struct SceneKey: Hashable {
        var type: DeviceType
        var scene: String
    }

    /// Which edits use each scene, playing it or taking a still from it. An edit that can't be read
    /// uses nothing here; `validate` says why.
    static func users(in project: Project) -> [SceneKey: [String]] {
        let files = ProjectFiles(project: project)
        var users: [SceneKey: [String]] = [:]
        for edit in files.names(in: project.edits) {
            guard let file = files.readEdit(edit, into: ProjectFiles.Report()) else { continue }
            for (type, video) in file.videos {
                for scene in video.scenes { users[SceneKey(type: type, scene: scene), default: []].append(edit) }
            }
        }
        return users
    }

    // MARK: - Takes from an earlier Retake

    /// The scenes' folders an earlier Retake left in the takes folders of `types`: one per scene,
    /// `<scene>/`, of numbered takes, `<n>.mov` and `<n>.json`, which this Retake doesn't read.
    public static func oldFolders(for types: [DeviceType], in project: Project) -> [URL] {
        let files = FileManager.default
        return types.flatMap { type -> [URL] in
            let folder = project.takes(for: type)
            return ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
                let url = folder.appending(path: name, directoryHint: .isDirectory)
                let names = (try? files.contentsOfDirectory(atPath: url.path)) ?? []
                let numbered = names.contains { name in
                    name == ".last-take" || name.range(of: #"^[0-9]+\.(json|mov)$"#, options: .regularExpression) != nil
                }
                return numbered ? url : nil
            }
        }
    }

    /// Fails (1) when the takes folders of `types` hold an earlier Retake's numbered takes, saying
    /// to delete them and record the scenes again.
    public static func refuseOldLayout(for types: [DeviceType], in project: Project) throws(RetakeError) {
        let old = oldFolders(for: types, in: project)
        guard !old.isEmpty else { return }
        let scenes = old.map(\.lastPathComponent).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let one = old.count == 1
        throw RetakeError(
            .failed,
            "\(old.map { project.displayPath($0) + "/" }.joined(separator: ", ")) \(one ? "holds" : "hold") numbered takes from an earlier Retake, "
                + "which this one doesn't read. Delete \(one ? "it" : "them") with `retake clean --takes \(scenes.joined(separator: ","))`, "
                + "or remove \(one ? "the folder" : "the folders"), and record \(scenes.count == 1 ? "the scene" : "the scenes") again.",
        )
    }

    // MARK: - Recording

    /// Where a take of `scene` is written while it's recorded, in the device type's takes folder:
    /// `<scene>.recording.mov` and `.json`, renamed into place by `keepRecording` once it's done.
    public static func recording(of scene: String, in folder: URL) -> (movie: URL, log: URL) {
        files(of: scene, recordingSuffix, in: folder)
    }

    /// Deletes what's left of a recording of `scene` that didn't finish, leaving its takes alone.
    public static func discardRecording(of scene: String, in folder: URL) {
        let (movie, log) = recording(of: scene, in: folder)
        for url in [movie, log] { try? FileManager.default.removeItem(at: url) }
    }

    /// Keeps the finished recording of `scene`. One that succeeded becomes the take, the take it
    /// replaces becomes the previous one, the old previous one is deleted, and so is the scene's
    /// latest failure, which is no longer news. One that failed becomes the latest failure,
    /// replacing the last, and leaves the take and the previous one alone.
    public static func keepRecording(of scene: String, in folder: URL, failed: Bool) throws {
        let recording = recording(of: scene, in: folder)
        if failed {
            try move(recording, to: files(of: scene, Kind.failed.suffix, in: folder))
            return
        }
        let take = files(of: scene, Kind.take.suffix, in: folder)
        try move(take, to: files(of: scene, Kind.previous.suffix, in: folder))
        try move(recording, to: take)
        try remove(files(of: scene, Kind.failed.suffix, in: folder))
    }

    /// Moves a take's movie and log, replacing those at `destination`; one that's missing leaves
    /// none in its place. Nothing is touched when neither is there to move.
    static func move(_ source: (movie: URL, log: URL), to destination: (movie: URL, log: URL)) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: source.movie.path) || files.fileExists(atPath: source.log.path) else { return }
        try remove(destination)
        for (from, to) in [(source.movie, destination.movie), (source.log, destination.log)] where files.fileExists(atPath: from.path) {
            try files.moveItem(at: from, to: to)
        }
    }

    static func remove(_ take: (movie: URL, log: URL)) throws {
        for url in [take.movie, take.log] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// `takes --restore`: puts back the take of `scene` that the current one replaced, the two
    /// swapping places, so restoring again undoes it. Misuse (2) when there's no previous take.
    public static func restore(_ scene: String, for type: DeviceType, in project: Project) throws(RetakeError) {
        let folder = project.takes(for: type)
        let take = files(of: scene, Kind.take.suffix, in: folder)
        let previous = files(of: scene, Kind.previous.suffix, in: folder)
        guard [previous.movie, previous.log].contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw RetakeError(.usage, "There's no previous \(type.rawValue) take of \(scene) to put back.")
        }
        let aside = files(of: scene, restoringSuffix, in: folder)
        do {
            try move(take, to: aside)
            try move(previous, to: take)
            try move(aside, to: previous)
        } catch {
            throw RetakeError(.failed, "Couldn't put back the previous take of \(scene) in \(project.displayPath(folder)): \(error.localizedDescription)")
        }
    }

    // MARK: - Cleaning

    /// What `clean` deletes.
    public struct Cleaning: Equatable, Sendable {
        public var takes: [Take]
        /// Scenes' folders of an earlier Retake's numbered takes.
        public var oldTakes: [URL] = []
        /// Each edit's folder of cuts, for a device type.
        public var cuts: [URL]
        /// Scene definitions no edit uses, for a device type.
        public var scenes: [URL] = []
        /// Scenes' folders of captures, for a device type.
        public var captures: [URL] = []

        /// The takes it deletes that an edit is cut from; its next cut needs the scene recorded again.
        public var used: [Take] { takes.filter { !$0.usedBy.isEmpty } }

        public var isEmpty: Bool { takes.isEmpty && oldTakes.isEmpty && cuts.isEmpty && scenes.isEmpty && captures.isEmpty }
        public var count: Int { takes.count + oldTakes.count + cuts.count + scenes.count + captures.count }
    }

    /// What `clean` would delete: with none of `takes`, `cuts` and `captures` given, every take,
    /// cut and capture; otherwise those given, where an empty list is every one. A scene named
    /// loses its take, its previous one and its failure, and any folder of an earlier Retake's
    /// numbered takes; or with `captures`, its captures. Misuse (2) for a scene or edit named that
    /// has nothing to delete.
    public static func cleaning(
        takes: [String]?, cuts: [String]?, captures: [String]? = nil, for types: [DeviceType], in project: Project,
    ) throws(RetakeError) -> Cleaning {
        let everything = takes == nil && cuts == nil && captures == nil
        var chosen: [Take] = [], old: [URL] = []
        if everything || takes != nil {
            let all = Self.takes(for: types, in: project), allOld = oldFolders(for: types, in: project)
            if let scenes = takes, !scenes.isEmpty {
                for scene in scenes where !all.contains(where: { $0.scene == scene }) && !allOld.contains(where: { $0.lastPathComponent == scene }) {
                    throw RetakeError(.usage, "There's no take of \(scene)\(types.count == 1 ? " for \(types[0].rawValue)" : "") to delete.")
                }
                chosen = all.filter { scenes.contains($0.scene) }
                old = allOld.filter { scenes.contains($0.lastPathComponent) }
            } else {
                (chosen, old) = (all, allOld)
            }
        }
        var folders: [URL] = []
        if everything || cuts != nil {
            let all = types.flatMap { type in
                let folder = project.cuts(for: type)
                return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
                    .map { folder.appending(path: $0, directoryHint: .isDirectory) }
            }
            if let edits = cuts, !edits.isEmpty {
                for edit in edits where !all.contains(where: { $0.lastPathComponent == edit }) {
                    throw RetakeError(.usage, "There's no cut of \(edit)\(types.count == 1 ? " for \(types[0].rawValue)" : "") to delete.")
                }
                folders = all.filter { edits.contains($0.lastPathComponent) }
            } else {
                folders = all
            }
        }
        var stills: [URL] = []
        if everything || captures != nil {
            let all = types.flatMap { type in CaptureStore.scenes(for: type, in: project).map { CaptureStore.folder(of: $0, for: type, in: project) } }
            if let scenes = captures, !scenes.isEmpty {
                for scene in scenes where !all.contains(where: { $0.lastPathComponent == scene }) {
                    throw RetakeError(.usage, "There are no captures of \(scene)\(types.count == 1 ? " for \(types[0].rawValue)" : "") to delete.")
                }
                stills = all.filter { scenes.contains($0.lastPathComponent) }
            } else {
                stills = all
            }
        }
        return Cleaning(takes: chosen, oldTakes: old, cuts: folders, captures: stills)
    }

    /// What `clean --unused` deletes: every take but the take of a scene an edit uses, so every
    /// previous take and failure too; every scene definition no edit uses that has no `capture`
    /// step, which its captures need; and the captures of every scene that no longer has a capture
    /// step, or is gone. A scene that can't be read is kept, with its captures. Fails before
    /// choosing anything if an edit can't be read, since its dependencies aren't safe to infer, or
    /// if an earlier Retake's numbered takes are there.
    public static func unused(for types: [DeviceType], in project: Project) throws(RetakeError) -> Cleaning {
        try refuseOldLayout(for: types, in: project)
        let projectFiles = ProjectFiles(project: project)
        var needed = Dictionary(uniqueKeysWithValues: types.map { ($0, Set<String>()) })
        for name in projectFiles.names(in: project.edits) {
            let report = ProjectFiles.Report()
            guard let edit = projectFiles.readEdit(name, into: report) else { throw report.error }
            for type in types {
                guard let video = edit.videos[type] else { continue }
                needed[type, default: []].formUnion(video.scenes)
            }
        }
        let unneeded = takes(for: types, in: project).filter { take in
            take.kind != .take || needed[take.type]?.contains(take.scene) != true
        }
        // Whether each scene captures, so its definition and captures are needed: nil when it can't be read.
        func captures(_ scene: String, for type: DeviceType) -> Bool? {
            guard FileManager.default.fileExists(atPath: projectFiles.sceneURL(scene, for: type).path) else { return false }
            return projectFiles.readScene(scene, for: type, into: ProjectFiles.Report()).map { $0.steps.contains { $0.action?.capture != nil } }
        }
        let unusedScenes = types.flatMap { type in
            projectFiles.names(in: project.scenes(for: type)).filter { needed[type]?.contains($0) != true && captures($0, for: type) == false }
                .map { projectFiles.sceneURL($0, for: type) }
        }
        let unusedCaptures = types.flatMap { type in
            CaptureStore.scenes(for: type, in: project).filter { captures($0, for: type) == false }.map { CaptureStore.folder(of: $0, for: type, in: project) }
        }
        return Cleaning(takes: unneeded, cuts: [], scenes: unusedScenes, captures: unusedCaptures)
    }

    /// Deletes what `cleaning` chose.
    public static func delete(_ cleaning: Cleaning, in project: Project) throws(RetakeError) {
        let files = FileManager.default
        do {
            for take in cleaning.takes { try remove((take.movie, take.log)) }
            for folder in cleaning.oldTakes + cleaning.cuts + cleaning.scenes + cleaning.captures where files.fileExists(atPath: folder.path) {
                try files.removeItem(at: folder)
            }
        } catch {
            throw RetakeError(.failed, "Couldn't delete everything: \(error.localizedDescription)")
        }
    }
}

extension TakeStore.Take {
    /// As `takes --json` prints it, named as its step log names what it gives. See
    /// Documentation/cli.md, "retake takes".
    public var json: JSONValue {
        var fields: [JSONObject.Entry] = [
            .init(key: "deviceType", value: .string(type.rawValue)),
            .init(key: "scene", value: .string(scene)),
            .init(key: "kind", value: .string(kind.rawValue)),
        ]
        if let log = recorded {
            fields += [
                .init(key: "recordedAt", value: .string(ISO8601DateFormatter().string(from: log.recordedAt))),
                .init(key: "app", value: TakeLog.object([("version", log.app.version.map(JSONValue.string)), ("build", log.app.build.map(JSONValue.string))])),
                .init(key: "device", value: TakeLog.object([
                    ("model", .string(log.device.model)), ("marketingName", log.device.marketingName.map(JSONValue.string)), ("os", .string(log.device.os)),
                ])),
                .init(key: "duration", value: .number(log.duration)),
                .init(key: "frames", value: .number(Double(log.frames))),
                .init(key: "dropped", value: .number(Double(log.dropped))),
            ]
        }
        fields.append(.init(key: "successful", value: .bool(successful)))
        if let failure = recorded?.failure { fields.append(.init(key: "failure", value: .string(failure))) }
        if let problem { fields.append(.init(key: "problem", value: .string(problem))) }
        fields.append(.init(key: "usedBy", value: .array(usedBy.map(JSONValue.string))))
        return .object(JSONObject(fields))
    }
}
