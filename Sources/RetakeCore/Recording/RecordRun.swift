import Foundation

/// `retake record`: choosing the scenes, then recording a take of each, or with `--dry-run`, playing
/// each without recording it. See Documentation/cli.md, "retake record".
public enum RecordRun {
    /// The scenes to record, in order, as Documentation/cli.md's table says: those named; or every scene in
    /// `scenes/<type>/`, or every one `edit` uses, either way only those with no take yet unless
    /// `force`. A failure is never cut from, so it isn't a take for this. Misuse (2) for a scene or
    /// edit that doesn't exist, or an edit not cut for this device type; a failure (1) when
    /// `scenes/<type>/` lists nothing because it's named in another case, or when the takes folder
    /// holds an earlier Retake's numbered takes. With `stillsOnly`, the scenes are those with
    /// `capture` steps, and those that have their captures are already taken: misuse (2) for a
    /// scene named that captures nothing.
    public static func scenes(
        named: [String], edit: String?, force: Bool, stillsOnly: Bool = false, for type: DeviceType, in project: Project,
    ) throws(RetakeError) -> (chosen: [String], alreadyTaken: [String]) {
        try TakeStore.refuseOldLayout(for: [type], in: project)
        let files = ProjectFiles(project: project)
        let available = files.sceneNames(for: type)
        if available.isEmpty, let misnamed = files.misnamedFolder(project.scenes(for: type)) {
            throw RetakeError(.failed, "There are no \(type.rawValue) scenes in \(project.displayPath(project.scenes(for: type))): \(misnamed).")
        }
        if !named.isEmpty {
            if let missing = named.first(where: { !available.contains($0) }) {
                throw RetakeError(
                    .usage,
                    "There's no \(type.rawValue) scene \"\(missing)\" (\(project.displayPath(files.sceneURL(missing, for: type))))"
                        + files.whyMissing(files.sceneURL(missing, for: type))
                        + (available.isEmpty ? "." : "; there's \(available.joined(separator: ", ")).")
                )
            }
            if stillsOnly, let none = named.first(where: { capturesNothing($0, for: type, in: project) }) {
                throw RetakeError(.usage, "\(none) has no capture steps, so --stills-only has nothing to take of it.")
            }
            var seen = Set<String>()
            return (named.filter { seen.insert($0).inserted }, [])
        }
        if stillsOnly {
            let candidates = available.filter { !capturesNothing($0, for: type, in: project) }
            if force { return (candidates, []) }
            let taken = Set(CaptureStore.scenes(for: type, in: project))
            return (candidates.filter { !taken.contains($0) }, candidates.filter { taken.contains($0) })
        }
        var candidates = available
        if let edit {
            guard FileManager.default.fileExists(atPath: files.editURL(edit).path) else {
                throw RetakeError(.usage, "There's no edit \"\(edit)\" (\(project.displayPath(files.editURL(edit))))\(files.whyMissing(files.editURL(edit))).")
            }
            let report = ProjectFiles.Report()
            guard let file = files.readEdit(edit, into: report) else { throw report.error }
            guard let video = file.videos[type] else {
                throw RetakeError(.usage, "\(edit) isn't cut for \(type.rawValue): its devices are \(file.devices.map(\.rawValue).joined(separator: ", ")).")
            }
            var seen = Set<String>()
            candidates = video.clips.flatMap { [$0.take] + $0.stills.map(\.take) }.filter { seen.insert($0).inserted }
            if let missing = candidates.first(where: { !available.contains($0) }) {
                throw RetakeError(.usage, "\(edit) uses the scene \"\(missing)\", which has no \(project.displayPath(files.sceneURL(missing, for: type))).")
            }
        }
        if force { return (candidates, []) }
        let taken = candidates.filter { scene in TakeStore.take(of: scene, for: type, in: project).map { !$0.failed } ?? false }
        return (candidates.filter { !taken.contains($0) }, taken)
    }

    /// Whether a scene has no `capture` step. One that can't be read is taken to have one, for
    /// playing it to say what's wrong with it.
    static func capturesNothing(_ scene: String, for type: DeviceType, in project: Project) -> Bool {
        guard let file = ProjectFiles(project: project).readScene(scene, for: type, into: ProjectFiles.Report()) else { return false }
        return !file.steps.contains { $0.action?.capture != nil }
    }

    /// What became of one scene: its new take, or why it failed, or for a dry run, that it played.
    public struct Outcome: Sendable {
        public var scene: String
        /// Its captures, once a recording kept them: the folder, and each one's name and size.
        public var captures: URL?
        public var captured: [CaptureSize] = []
        /// Where its take is, once it's recorded one, whether or not it succeeded: `<scene>.mov`, or
        /// `<scene>.failed.mov`.
        public var movie: URL?
        public var duration: Double?
        public var failure: RetakeError?
    }

    /// Records, or with `dryRun` plays, each scene in turn, carrying on past a failure unless
    /// `stopOnFailure`; then, when any scene's set wasn't `live`, launches the app once more to
    /// delete the last take's copy of its data from the device. A failure to launch or reach the app
    /// at all is the environment's, and ends the run.
    public static func run(
        _ scenes: [String],
        in project: Project,
        on device: Device,
        capture: CaptureDevice?,
        dryRun: Bool,
        stillsOnly: Bool = false,
        stopOnFailure: Bool,
        player: Player,
    ) async -> [Outcome] {
        var outcomes: [Outcome] = []
        var needsCleanUp = false
        var player = player
        if player.screen == nil { player.screen = Devicectl().screenPoints(of: device) }
        for name in scenes {
            var outcome = Outcome(scene: name)
            do throws(RetakeError) {
                guard let type = device.type else {
                    throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
                }
                let (scene, set) = try AppSession.scene(name, in: project, for: type)
                needsCleanUp = needsCleanUp || set.state != .live
                if dryRun {
                    player.report(.scene(name, recording: false))
                    try await AppSession.run("dry-run-\(name)", in: project, set: set, scene: scene, on: device, report: player.report, cleanUp: false) { driver, _ throws(RetakeError) in
                        try await player.play(scene, named: name, on: driver)
                    }
                } else if stillsOnly {
                    guard let capture else { throw RetakeError(.environment, "\(device.name)'s screen isn't offered for recording.") }
                    player.report(.scene(name, recording: true))
                    try await TakeRecording.captureStills(of: name, scene: scene, set: set, in: project, on: device, capture: capture, player: player, cleanUp: false)
                    outcome.keptCaptures(of: name, for: type, in: project)
                } else {
                    guard let capture else { throw RetakeError(.environment, "\(device.name)'s screen isn't offered for recording.") }
                    player.report(.scene(name, recording: true))
                    let target = TakeRecording.Target(scene: name, folder: project.takes(for: type))
                    let started = Date()
                    do throws(RetakeError) {
                        let log = try await TakeRecording.record(target, scene: scene, set: set, in: project, on: device, capture: capture, player: player, cleanUp: false)
                        outcome.duration = log.duration
                        outcome.movie = target.kept(.take).movie
                        if scene.steps.contains(where: { $0.action?.capture != nil }) { outcome.keptCaptures(of: name, for: type, in: project) }
                    } catch {
                        // A failure kept now, rather than one from before that a recording which
                        // couldn't write anything left alone.
                        if let kept = ProjectStatus.modified(target.kept(.failed).log), kept >= started.addingTimeInterval(-1) {
                            outcome.movie = target.kept(.failed).movie
                        }
                        throw error
                    }
                }
            } catch {
                outcome.failure = error
            }
            outcomes.append(outcome)
            if let failure = outcome.failure, stopOnFailure || failure.status == .environment { break }
        }
        if needsCleanUp, let bundleID = try? Installer.bundleID(for: project) {
            do {
                try Launcher.cleanUp(bundleID: bundleID, on: device)
            } catch {
                player.report(.warning("\(error.message) Run `retake clean --on-device` to delete what's left."))
            }
        }
        return outcomes
    }
}

/// A capture's name and its size, in pixels.
public struct CaptureSize: Equatable, Sendable {
    public var name: String
    public var width: Int
    public var height: Int
}

extension RecordRun.Outcome {
    mutating func keptCaptures(of scene: String, for type: DeviceType, in project: Project) {
        let folder = CaptureStore.folder(of: scene, for: type, in: project)
        captures = folder
        captured = CaptureStore.captures(in: folder).map { CaptureSize(name: $0.name, width: $0.width, height: $0.height) }
    }
}
