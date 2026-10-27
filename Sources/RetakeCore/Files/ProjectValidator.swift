import Foundation

/// What `retake validate` checks without takes: every file read strictly, then what a schema
/// can't say, across the files. See docs/cli.md, "retake validate".
public struct ProjectValidator {
    public let files: ProjectFiles
    let fileManager: FileManager

    public init(files: ProjectFiles, fileManager: FileManager = .default) {
        self.files = files
        self.fileManager = fileManager
    }

    var project: Project { files.project }

    /// A project file named on the command line, by what kind of file it is.
    public enum Target: Equatable, Sendable {
        case configuration
        case set(String)
        case scene(String, DeviceType)
        case edit(String)
    }

    /// Which of the project's files `url` is, or nil when it isn't one Retake reads.
    public func target(for url: URL) -> Target? {
        let path = url.standardizedFileURL.path
        if path == project.configuration.path { return .configuration }
        guard path.hasSuffix(".json") else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let folder = url.standardizedFileURL.deletingLastPathComponent().path
        if folder == project.sets.standardizedFileURL.path.trimmingSlash { return .set(name) }
        if folder == project.edits.standardizedFileURL.path.trimmingSlash { return .edit(name) }
        for type in DeviceType.allCases where folder == project.scenes(for: type).standardizedFileURL.path.trimmingSlash {
            return .scene(name, type)
        }
        return nil
    }

    /// Every file of the project, or only `targets`, each checked; problems in files only read to
    /// check a target's references aren't reported.
    public func validate(_ targets: [Target]? = nil) -> ProjectFiles.Report {
        let report = ProjectFiles.Report()
        let all = targets == nil
        let sets = targets?.compactMap { if case .set(let name) = $0 { name } else { nil } } ?? files.names(in: project.sets)
        let edits = targets?.compactMap { if case .edit(let name) = $0 { name } else { nil } } ?? files.names(in: project.edits)
        var scenes: [(String, DeviceType)] = targets?.compactMap { if case .scene(let name, let type) = $0 { (name, type) } else { nil } } ?? []
        if all {
            for type in DeviceType.allCases { scenes += files.names(in: project.scenes(for: type)).map { ($0, type) } }
        }

        if all || targets?.contains(.configuration) == true { checkConfiguration(report) }
        for name in sets { checkSet(name, report) }
        for (name, type) in scenes { checkScene(name, type, report) }
        for name in edits { checkEdit(name, report) }
        return report
    }

    // MARK: - Each kind of file

    func checkConfiguration(_ report: ProjectFiles.Report) {
        guard let defaultSet = project.settings.defaultSet, !exists(files.setURL(defaultSet)) else { return }
        report.problem(FileProblem(
            file: project.configuration.lastPathComponent,
            path: JSONPath.root.appending("defaultSet"),
            message: noSet(defaultSet),
        ))
    }

    func checkSet(_ name: String, _ report: ProjectFiles.Report) {
        guard let set = files.readSet(name, into: report) else { return }
        let file = project.displayPath(files.setURL(name))
        // A loop or a missing base is found by resolving it; its own problems are reported above.
        if set.extends != nil {
            let chain = ProjectFiles.Report()
            _ = files.resolveSet(name, into: chain)
            for problem in chain.problems where problem.file == file && problem.path == JSONPath.root.appending("extends") {
                report.problem(problem)
            }
        }
        for copy in set.files {
            let source = project.root.appending(path: copy.source)
            var isFolder: ObjCBool = false
            let at = JSONPath.root.appending("files").appending(copy.destination)
            if !fileManager.fileExists(atPath: source.path, isDirectory: &isFolder) {
                report.problem(FileProblem(file: file, path: at, message: "\"\(copy.source)\" doesn't exist in the project"))
            } else if isFolder.boolValue != copy.isFolder {
                report.problem(FileProblem(
                    file: file,
                    path: at,
                    message: copy.isFolder ? "\"\(copy.source)\" is a file, not a folder" : "\"\(copy.source)\" is a folder, not a file",
                ))
            }
        }
    }

    func checkScene(_ name: String, _ type: DeviceType, _ report: ProjectFiles.Report) {
        guard let scene = files.readScene(name, for: type, into: report) else { return }
        let file = project.displayPath(files.sceneURL(name, for: type))
        if let set = scene.set {
            if !exists(files.setURL(set)) {
                report.problem(FileProblem(file: file, path: JSONPath.root.appending("set"), message: noSet(set)))
            }
        } else if project.settings.defaultSet == nil {
            report.problem(FileProblem(file: file, path: .root, message: "names no set, and \(project.configuration.lastPathComponent) has no defaultSet"))
        }
    }

    func checkEdit(_ name: String, _ report: ProjectFiles.Report) {
        guard let edit = files.readEdit(name, into: report) else { return }
        let file = project.displayPath(files.editURL(name))
        func problem(_ path: JSONPath, _ message: String, for type: DeviceType? = nil) {
            let source = type.map { edit.source(of: path, for: $0) } ?? path
            let found = FileProblem(file: file, path: source, message: message)
            if !report.problems.contains(found) { report.problem(found) }
        }

        // Scenes are read once each, for every device type the edit names.
        var scenes: [DeviceType: [String: SceneFile]] = [:]
        func loadScene(_ name: String, _ type: DeviceType) -> SceneFile? {
            if let scene = scenes[type]?[name] { return scene }
            let quiet = ProjectFiles.Report()
            guard exists(files.sceneURL(name, for: type)), let scene = files.readScene(name, for: type, into: quiet) else { return nil }
            scenes[type, default: [:]][name] = scene
            return scene
        }
        func checkScene(_ name: String, _ type: DeviceType, at path: JSONPath) -> SceneFile? {
            guard exists(files.sceneURL(name, for: type)) else {
                problem(path, "there's no scene \"\(name)\" for \(type.rawValue) (\(project.displayPath(files.sceneURL(name, for: type))))", for: type)
                return nil
            }
            return loadScene(name, type)
        }
        func checkAnchor(_ anchor: Anchor?, in scene: SceneFile?, sceneName: String, _ type: DeviceType, at path: JSONPath) {
            guard let scene, case .step(let step)? = anchor else { return }
            let sceneFile = project.displayPath(files.sceneURL(sceneName, for: type))
            switch step.step {
            case .id(let id) where !scene.steps.contains(where: { $0.id == id }):
                problem(path.appending("step"), "\(sceneFile) has no step \"\(id)\"", for: type)
            case .number(let number) where abs(number) > scene.steps.count:
                problem(path.appending("step"), "\(sceneFile) has \(scene.steps.count) step\(scene.steps.count == 1 ? "" : "s"), so there's no step \(number)", for: type)
            default:
                break
            }
        }
        func checkFile(_ relative: String, at path: JSONPath, for type: DeviceType) {
            if !exists(project.root.appending(path: relative)) {
                problem(path, "\"\(relative)\" doesn't exist in the project", for: type)
            }
        }

        for type in edit.devices {
            for pinned in edit.takes[type] ?? [] where !exists(files.sceneURL(pinned.name, for: type)) {
                problem(JSONPath.root.appending("takes").appending(type.rawValue).appending(pinned.name), "there's no scene \"\(pinned.name)\" for \(type.rawValue) (\(project.displayPath(files.sceneURL(pinned.name, for: type))))")
            }
            guard let video = edit.videos[type] else { continue }
            if let music = video.music { checkFile(music.file, at: JSONPath.root.appending("music").appending("file"), for: type) }
            if let sound = video.touchSound { checkFile(sound.file, at: JSONPath.root.appending("touchSound").appending("file"), for: type) }
            let clipIDs = Dictionary(video.clips.enumerated().compactMap { index, clip in clip.id.map { ($0, index) } }, uniquingKeysWith: { first, _ in first })
            for (index, clip) in video.clips.enumerated() {
                let at = JSONPath.root.appending("clips").appending(index)
                let scene = checkScene(clip.take, type, at: at.appending("take"))
                checkAnchor(clip.from, in: scene, sceneName: clip.take, type, at: at.appending("from"))
                checkAnchor(clip.to, in: scene, sceneName: clip.take, type, at: at.appending("to"))
                for (captionIndex, caption) in clip.captions.enumerated() {
                    let captionAt = at.appending("captions").appending(captionIndex)
                    checkAnchor(caption.from, in: scene, sceneName: clip.take, type, at: captionAt.appending("from"))
                    if let end = caption.to {
                        if let later = end.clip, let target = clipIDs[later], video.clips.indices.contains(target) {
                            let laterClip = video.clips[target]
                            checkAnchor(end.anchor, in: loadScene(laterClip.take, type), sceneName: laterClip.take, type, at: captionAt.appending("to"))
                        } else if end.clip == nil {
                            checkAnchor(end.anchor, in: scene, sceneName: clip.take, type, at: captionAt.appending("to"))
                        }
                    }
                }
                for (soundIndex, sound) in clip.sounds.enumerated() {
                    let soundAt = at.appending("sounds").appending(soundIndex)
                    checkFile(sound.file, at: soundAt.appending("file"), for: type)
                    checkAnchor(sound.at, in: scene, sceneName: clip.take, type, at: soundAt.appending("at"))
                }
                if let spotlight = clip.spotlight {
                    checkAnchor(spotlight.from, in: scene, sceneName: clip.take, type, at: at.appending("spotlight").appending("from"))
                    checkAnchor(spotlight.to, in: scene, sceneName: clip.take, type, at: at.appending("spotlight").appending("to"))
                }
                for (blurIndex, blur) in clip.blurs.enumerated() {
                    checkAnchor(blur.from, in: scene, sceneName: clip.take, type, at: at.appending("blurs").appending(blurIndex).appending("from"))
                    checkAnchor(blur.to, in: scene, sceneName: clip.take, type, at: at.appending("blurs").appending(blurIndex).appending("to"))
                }
                for (stillIndex, still) in clip.stills.enumerated() {
                    let stillAt = at.appending("stills").appending(stillIndex)
                    let stillScene = checkScene(still.take, type, at: stillAt.appending("take"))
                    checkAnchor(still.at, in: stillScene, sceneName: still.take, type, at: stillAt.appending("at"))
                }
            }
        }

        // A scene the edit cuts on more than one device type must have the same step ids on each,
        // since its anchors name them on every type.
        guard edit.devices.count > 1 else { return }
        let used = Set(edit.videos.values.flatMap { $0.clips.flatMap { [$0.take] + $0.stills.map(\.take) } })
        for name in used.sorted() {
            let present = edit.devices.compactMap { type in loadScene(name, type).map { (type, $0) } }
            guard let (firstType, first) = present.first else { continue }
            for (type, other) in present.dropFirst() {
                let firstIDs = first.steps.compactMap(\.id)
                let otherIDs = other.steps.compactMap(\.id)
                guard firstIDs != otherIDs else { continue }
                let missing = firstIDs.filter { !otherIDs.contains($0) }
                let extra = otherIDs.filter { !firstIDs.contains($0) }
                var differences: [String] = []
                if !missing.isEmpty { differences.append("it lacks \(missing.map { "\"\($0)\"" }.joined(separator: ", "))") }
                if !extra.isEmpty { differences.append("it has \(extra.map { "\"\($0)\"" }.joined(separator: ", ")), which the other hasn't") }
                if differences.isEmpty { differences.append("they're in a different order") }
                report.problem(FileProblem(
                    file: project.displayPath(files.sceneURL(name, for: type)),
                    path: JSONPath.root.appending("steps"),
                    message: "its step ids differ from \(project.displayPath(files.sceneURL(name, for: firstType)))'s, which \(file) cuts both from: \(differences.joined(separator: "; "))",
                ))
            }
        }
    }

    // MARK: -

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func noSet(_ name: String) -> String {
        "there's no set \"\(name)\" (\(project.displayPath(files.setURL(name))))"
    }
}

private extension String {
    var trimmingSlash: String { hasSuffix("/") && count > 1 ? String(dropLast()) : self }
}
