import Foundation

/// `retake record`: choosing the scenes, then recording a take of each, or with `--dry-run`, playing
/// each without recording it. See docs/cli.md, "retake record".
public enum RecordRun {
    /// A take on disk: its number, and whether it failed.
    public struct ExistingTake: Equatable, Sendable {
        public var number: Int
        public var failed: Bool
    }

    /// A scene's takes for a device type, in `RetakeOutput/takes/<type>/<scene>/`, by number: each
    /// `<n>.json` step log, failed when it says so.
    public static func takes(of scene: String, for type: DeviceType, in project: Project) -> [ExistingTake] {
        let folder = project.takes(for: type).appending(path: scene)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name -> ExistingTake? in
            guard name.hasSuffix(".json"), let number = Int(name.dropLast(5)), number > 0 else { return nil }
            let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8)
            let failed = text.flatMap { try? JSONParser.parse($0) }.map { $0[path: "failure"] != nil } ?? true
            return ExistingTake(number: number, failed: failed)
        }.sorted { $0.number < $1.number }
    }

    /// The next take's number: one more than the scene's last, failed takes included, since takes
    /// are never renumbered.
    public static func nextTake(of scene: String, for type: DeviceType, in project: Project) -> Int {
        (takes(of: scene, for: type, in: project).last?.number ?? 0) + 1
    }

    /// The scenes to record, in order, as docs/cli.md's table says: those named; or every scene in
    /// `scenes/<type>/`, or every one `edit` uses, either way only those with no take yet unless
    /// `force`. A failed take can't be pinned, so it isn't a take for this. Misuse (2) for a scene
    /// or edit that doesn't exist, or an edit not cut for this device type.
    public static func scenes(
        named: [String], edit: String?, force: Bool, for type: DeviceType, in project: Project,
    ) throws(RetakeError) -> (chosen: [String], alreadyTaken: [String]) {
        let files = ProjectFiles(project: project)
        let available = files.names(in: project.scenes(for: type))
        if !named.isEmpty {
            if let missing = named.first(where: { !available.contains($0) }) {
                throw RetakeError(
                    .usage,
                    "There's no \(type.rawValue) scene \"\(missing)\" (\(project.displayPath(files.sceneURL(missing, for: type))))"
                        + (available.isEmpty ? "." : "; there's \(available.joined(separator: ", ")).")
                )
            }
            var seen = Set<String>()
            return (named.filter { seen.insert($0).inserted }, [])
        }
        var candidates = available
        if let edit {
            guard FileManager.default.fileExists(atPath: files.editURL(edit).path) else {
                throw RetakeError(.usage, "There's no edit \"\(edit)\" (\(project.displayPath(files.editURL(edit)))).")
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
        let taken = candidates.filter { scene in takes(of: scene, for: type, in: project).contains { !$0.failed } }
        return (candidates.filter { !taken.contains($0) }, taken)
    }

    /// What became of one scene: its new take, or why it failed, or for a dry run, that it played.
    public struct Outcome: Sendable {
        public var scene: String
        public var take: Int?
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
        stopOnFailure: Bool,
        player: Player,
    ) async -> [Outcome] {
        var outcomes: [Outcome] = []
        var needsCleanUp = false
        for name in scenes {
            var outcome = Outcome(scene: name)
            do throws(RetakeError) {
                guard let type = device.type else {
                    throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
                }
                let (scene, set) = try AppSession.scene(name, in: project, for: type)
                needsCleanUp = needsCleanUp || set.state != .live
                if dryRun {
                    player.report(.scene(name, take: nil))
                    try await AppSession.run("dry-run-\(name)", in: project, set: set, scene: scene, on: device, report: player.report, cleanUp: false) { driver, _ throws(RetakeError) in
                        try await player.play(scene, named: name, on: driver)
                    }
                } else {
                    guard let capture else { throw RetakeError(.environment, "\(device.name)'s screen isn't offered for recording.") }
                    let number = nextTake(of: name, for: type, in: project)
                    outcome.take = number
                    player.report(.scene(name, take: number))
                    let movie = project.takes(for: type).appending(path: "\(name)/\(number).mov")
                    let target = TakeRecording.Target(scene: name, take: number, movie: movie)
                    let log = try await TakeRecording.record(target, scene: scene, set: set, in: project, on: device, capture: capture, player: player, cleanUp: false)
                    outcome.duration = log.duration
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
