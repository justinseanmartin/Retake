import Foundation

/// Takes and cuts on disk, as `takes` lists them and `clean` deletes them. See Documentation/cli.md,
/// "retake takes" and "retake clean".
public enum TakeStore {
    /// A take: its movie and step log, in `output/takes/<type>/<scene>/`, either of which may be
    /// missing, and what its step log says.
    public struct Take: Equatable, Sendable {
        public var type: DeviceType
        public var scene: String
        public var number: Int
        public var movie: URL
        public var log: URL
        /// What the step log says; nil when it's missing or can't be read, `problem` saying why.
        public var recorded: TakeLog?
        public var problem: String?
        /// The edits that pin it, by name.
        public var pinnedBy: [String]

        /// A take that failed, or whose step log can't say it didn't, which no edit can pin.
        public var failed: Bool { recorded == nil || recorded?.failure != nil }
        /// A complete take whose recording succeeded and whose movie and log can both be read.
        public var successful: Bool { !failed && problem == nil }

        /// How messages name it: `create-note@3`.
        public var name: String { "\(scene)@\(number)" }
    }

    /// Every take of `scene`, or of every scene, for each of `types` in turn, by scene and number.
    public static func takes(of scene: String? = nil, for types: [DeviceType], in project: Project) -> [Take] {
        let files = FileManager.default
        let pins = pins(in: project)
        return types.flatMap { type -> [Take] in
            let folder = project.takes(for: type)
            let scenes = scene.map { [$0] } ?? ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
            return scenes.flatMap { scene -> [Take] in
                let sceneFolder = folder.appending(path: scene, directoryHint: .isDirectory)
                let names = (try? files.contentsOfDirectory(atPath: sceneFolder.path)) ?? []
                let numbers = Set(names.compactMap { name -> Int? in
                    let url = URL(filePath: name)
                    guard ["json", "mov"].contains(url.pathExtension), let number = Int(url.deletingPathExtension().lastPathComponent), number > 0 else { return nil }
                    return number
                })
                return numbers.sorted().map { number in
                    take(number, of: scene, for: type, in: sceneFolder, pinnedBy: pins[Pin(type: type, scene: scene, take: number)] ?? [], project: project)
                }
            }
        }
    }

    static func take(_ number: Int, of scene: String, for type: DeviceType, in folder: URL, pinnedBy: [String], project: Project) -> Take {
        let movie = folder.appending(path: "\(number).mov"), log = folder.appending(path: "\(number).json")
        var recorded: TakeLog?, problem: String?
        if let data = FileManager.default.contents(atPath: log.path) {
            let reader = JSONReader(file: project.displayPath(log))
            recorded = TakeLog.read(String(decoding: data, as: UTF8.self), with: reader)
            if recorded == nil { problem = reader.problems.map(\.description).joined(separator: "\n") }
        } else {
            problem = "\(project.displayPath(log)) is missing"
        }
        if recorded != nil, !FileManager.default.fileExists(atPath: movie.path) { problem = "\(project.displayPath(movie)) is missing" }
        return Take(type: type, scene: scene, number: number, movie: movie, log: log, recorded: recorded, problem: problem, pinnedBy: pinnedBy)
    }

    struct Pin: Hashable {
        var type: DeviceType
        var scene: String
        var take: Int
    }

    /// Which edits pin each take. An edit that can't be read pins nothing here; `validate` says why.
    static func pins(in project: Project) -> [Pin: [String]] {
        let files = ProjectFiles(project: project)
        var pins: [Pin: [String]] = [:]
        for edit in files.names(in: project.edits) {
            guard let file = files.readEdit(edit, into: ProjectFiles.Report()) else { continue }
            for (type, takes) in file.takes {
                for take in takes { pins[Pin(type: type, scene: take.name, take: take.value), default: []].append(edit) }
            }
        }
        return pins
    }

    /// Which takes `clean --takes` names: a scene's every take, or one take of it.
    public enum TakeChoice: Equatable, Sendable {
        case scene(String)
        case take(String, Int)

        /// `create-note`, or `create-note@3`.
        public static func parse(_ text: String) throws(RetakeError) -> TakeChoice {
            let parts = text.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
            guard let scene = parts.first, !scene.isEmpty, parts.count <= 2 else {
                throw RetakeError(.usage, "\"\(text)\" isn't a scene, or a scene's take as <scene>@<take>, such as create-note@3.")
            }
            guard parts.count == 2 else { return .scene(scene) }
            guard let number = Int(parts[1]), number >= 1 else {
                throw RetakeError(.usage, "\"\(text)\": takes are numbered from 1, so give one such as \(scene)@3.")
            }
            return .take(scene, number)
        }

        func includes(_ take: Take) -> Bool {
            switch self {
            case .scene(let scene): take.scene == scene
            case .take(let scene, let number): take.scene == scene && take.number == number
            }
        }

        var name: String {
            switch self {
            case .scene(let scene): scene
            case .take(let scene, let number): "\(scene)@\(number)"
            }
        }
    }

    /// What `clean` deletes.
    public struct Cleaning: Equatable, Sendable {
        public var takes: [Take]
        /// Each edit's folder of cuts, for a device type.
        public var cuts: [URL]
        /// Scene definitions no edit uses, for a device type.
        public var scenes: [URL] = []

        /// The takes it deletes that an edit last cut from; its next cut selects another take.
        public var pinned: [Take] { takes.filter { !$0.pinnedBy.isEmpty } }
    }

    /// What `clean` would delete: with neither `takes` nor `cuts` given, every take and cut;
    /// otherwise those given, where an empty list is every one. Misuse (2) for a scene, take or
    /// edit named that has nothing to delete.
    public static func cleaning(takes: [TakeChoice]?, cuts: [String]?, for types: [DeviceType], in project: Project) throws(RetakeError) -> Cleaning {
        let everything = takes == nil && cuts == nil
        var chosen: [Take] = []
        if everything || takes != nil {
            let all = Self.takes(for: types, in: project)
            if let choices = takes, !choices.isEmpty {
                for choice in choices where !all.contains(where: choice.includes) {
                    throw RetakeError(.usage, "There's no take \(choice.name)\(types.count == 1 ? " for \(types[0].rawValue)" : "") to delete.")
                }
                chosen = all.filter { take in choices.contains { $0.includes(take) } }
            } else {
                chosen = all
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
        return Cleaning(takes: chosen, cuts: folders)
    }

    /// What `clean --unused` deletes: every take except the latest successful one of a scene an
    /// edit uses, and every scene definition no edit uses. Fails before choosing anything if an
    /// edit can't be read, since its dependencies aren't safe to infer.
    public static func unused(for types: [DeviceType], in project: Project) throws(RetakeError) -> Cleaning {
        let projectFiles = ProjectFiles(project: project)
        var needed = Dictionary(uniqueKeysWithValues: types.map { ($0, Set<String>()) })
        for name in projectFiles.names(in: project.edits) {
            let report = ProjectFiles.Report()
            guard let edit = projectFiles.readEdit(name, into: report) else { throw report.error }
            for type in types {
                guard let video = edit.videos[type] else { continue }
                for clip in video.clips {
                    needed[type, default: []].insert(clip.take)
                    needed[type, default: []].formUnion(clip.stills.map(\.take))
                }
            }
        }

        let allTakes = takes(for: types, in: project)
        let latest = Dictionary(grouping: allTakes.filter { $0.successful }) { "\($0.type.rawValue)/\($0.scene)" }
            .mapValues { $0.map(\.number).max()! }
        let oldTakes = allTakes.filter { take in
            guard needed[take.type]?.contains(take.scene) == true else { return true }
            return take.number != latest["\(take.type.rawValue)/\(take.scene)"]
        }
        let unusedScenes = types.flatMap { type in
            projectFiles.names(in: project.scenes(for: type)).filter { needed[type]?.contains($0) != true }
                .map { projectFiles.sceneURL($0, for: type) }
        }
        return Cleaning(takes: oldTakes, cuts: [], scenes: unusedScenes)
    }

    /// Deletes what `cleaning` chose, and a scene's folder once its last take is gone.
    public static func delete(_ cleaning: Cleaning, in project: Project) throws(RetakeError) {
        let files = FileManager.default
        do {
            for take in cleaning.takes {
                for url in [take.movie, take.log] where files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
                let folder = take.movie.deletingLastPathComponent()
                if (try? files.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try files.removeItem(at: folder) }
            }
            for folder in cleaning.cuts { try files.removeItem(at: folder) }
            for scene in cleaning.scenes { try files.removeItem(at: scene) }
        } catch {
            throw RetakeError(.failed, "Couldn't delete everything: \(error.localizedDescription)")
        }
    }
}
