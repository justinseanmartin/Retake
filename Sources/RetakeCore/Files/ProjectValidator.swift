import Foundation

/// What `retake validate` checks: every file read strictly, then what a schema can't say, across
/// the files, and unless `offline`, what only the takes can: that each edit's anchors resolve in
/// the takes it pins, and the elements it names are on screen there. See Documentation/cli.md, "retake
/// validate".
public struct ProjectValidator {
    public let files: ProjectFiles
    /// Whether to leave out the checks that need takes.
    public let offline: Bool
    let fileManager: FileManager

    public init(files: ProjectFiles, offline: Bool = true, fileManager: FileManager = .default) {
        self.files = files
        self.offline = offline
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
            if let sound = video.tapSound { checkFile(sound.file, at: JSONPath.root.appending("tapSound").appending("file"), for: type) }
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
            if !offline {
                checkTakes(of: edit, video, for: type, problem: { problem($0, $1, for: type) }, warning: { path, message in
                    let found = FileProblem(file: file, path: edit.source(of: path, for: type), message: message)
                    if !report.warnings.contains(found) { report.warning(found) }
                }, reported: { path in
                    let source = edit.source(of: path, for: type)
                    return report.problems.contains { $0.file == file && $0.path == source }
                })
            }
        }

    }

    // MARK: - Against the takes

    /// What `cut` will check of `video`, in the latest successful takes recorded here: each clip's
    /// anchors resolving inside its take, in order; its captions', sounds', spotlight's and blurs'
    /// within the stretch the clip plays; and the elements a spotlight or blur names on screen as it
    /// starts. Takes aren't in a repository, so a scene without a successful take only warns that
    /// what's cut from it isn't checked.
    func checkTakes(
        of edit: EditFile, _ video: Edit, for type: DeviceType, problem: (JSONPath, String) -> Void, warning: (JSONPath, String) -> Void,
        reported: (JSONPath) -> Bool,
    ) {
        var timelines: [String: TakeTimeline?] = [:]
        func pinned(_ scene: String, at path: JSONPath) -> TakeTimeline? {
            if let known = timelines[scene] { return known }
            let take = TakeStore.takes(of: scene, for: [type], in: project).last(where: { $0.successful })
            let found: TakeTimeline?
            if let log = take?.recorded {
                found = TakeTimeline(log)
            } else {
                found = nil
                warning(path, "there's no successful \(type.rawValue) take of \(scene), so what's cut from it isn't checked; record it")
            }
            timelines[scene] = found
            return found
        }
        func resolve(_ anchor: Anchor, in timeline: TakeTimeline, at path: JSONPath) -> Double? {
            do {
                let time = try timeline.time(of: anchor)
                guard time >= 0, time <= timeline.log.duration else {
                    problem(path, "is \(TakeTimeline.seconds(time)) into the take, outside it: it's \(TakeTimeline.seconds(timeline.log.duration)) long")
                    return nil
                }
                return time
            } catch {
                // A step the scene lacks is named already, by the checks that need no take.
                if !reported(path.appending("step")) { problem(path, "doesn't resolve: \(error.message)") }
                return nil
            }
        }
        func within(_ time: Double?, _ range: ClosedRange<Double>?, at path: JSONPath) {
            guard let time, let range, !range.contains(time) else { return }
            problem(path, "is \(TakeTimeline.seconds(time)) into the take, outside the stretch its clip plays, \(TakeTimeline.seconds(range.lowerBound)) to \(TakeTimeline.seconds(range.upperBound))")
        }

        // Each clip's stretch of its take, where it resolves; what's in a clip is checked against it.
        var stretches: [Int: ClosedRange<Double>] = [:]
        var ranges: [String: ClosedRange<Double>] = [:]
        let clips = video.clips.enumerated().map { index, clip in (index, clip, JSONPath.root.appending("clips").appending(index)) }
        for (index, clip, at) in clips {
            guard let timeline = pinned(clip.take, at: at.appending("take")) else { continue }
            let from = resolve(clip.from, in: timeline, at: at.appending("from"))
            let to = resolve(clip.to, in: timeline, at: at.appending("to"))
            guard let from, let to else { continue }
            guard from < to else {
                problem(at.appending("to"), "is \(TakeTimeline.seconds(to)) into the take, not after from, at \(TakeTimeline.seconds(from))")
                continue
            }
            stretches[index] = from...to
            if let id = clip.id { ranges[id] = from...to }
        }
        for (index, clip, at) in clips {
            guard let played = stretches[index], let timeline = pinned(clip.take, at: at.appending("take")) else { continue }
            let from = played.lowerBound
            for (index, caption) in clip.captions.enumerated() {
                let captionAt = at.appending("captions").appending(index)
                within(caption.from.flatMap { resolve($0, in: timeline, at: captionAt.appending("from")) }, played, at: captionAt.appending("from"))
                guard let end = caption.to, let anchor = end.anchor else { continue }
                if let later = end.clip {
                    guard let laterClip = video.clips.first(where: { $0.id == later }),
                          let laterTimeline = pinned(laterClip.take, at: captionAt.appending("to")) else { continue }
                    within(resolve(anchor, in: laterTimeline, at: captionAt.appending("to")), ranges[later], at: captionAt.appending("to"))
                } else {
                    within(resolve(anchor, in: timeline, at: captionAt.appending("to")), played, at: captionAt.appending("to"))
                }
            }
            for (index, sound) in clip.sounds.enumerated() {
                let soundAt = at.appending("sounds").appending(index).appending("at")
                within(resolve(sound.at, in: timeline, at: soundAt), played, at: soundAt)
            }
            var regions: [(Edit.Region, Anchor?, Anchor?, JSONPath)] = []
            if let spotlight = clip.spotlight { regions.append((spotlight.region, spotlight.from, spotlight.to, at.appending("spotlight"))) }
            for (index, blur) in clip.blurs.enumerated() { regions.append((blur.region, blur.from, blur.to, at.appending("blurs").appending(index))) }
            for (region, regionFrom, regionTo, regionAt) in regions {
                let starts = regionFrom.flatMap { resolve($0, in: timeline, at: regionAt.appending("from")) }
                within(starts, played, at: regionAt.appending("from"))
                within(regionTo.flatMap { resolve($0, in: timeline, at: regionAt.appending("to")) }, played, at: regionAt.appending("to"))
                guard case .element(let element) = region else { continue }
                do {
                    _ = try timeline.element(element, at: starts ?? from)
                } catch {
                    problem(regionAt.appending("element"), error.message)
                }
            }
            for (index, still) in clip.stills.enumerated() {
                let stillAt = at.appending("stills").appending(index)
                guard let stillTimeline = pinned(still.take, at: stillAt.appending("take")) else { continue }
                _ = resolve(still.at, in: stillTimeline, at: stillAt.appending("at"))
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
