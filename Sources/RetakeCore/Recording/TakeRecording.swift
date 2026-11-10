import ButtonHeist
import Foundation

/// Recording one take of a scene: its movie and its step log. See Documentation/cli.md, "retake record",
/// steps 1 to 4.
public enum TakeRecording {
    /// Seconds a device takes to finish turning, so a take recorded from before launch starts
    /// after it.
    static let turnSettles = 1.0

    /// Where a take is written, and what it's of.
    public struct Target: Sendable {
        public var scene: String
        /// The device type's takes folder, which the take is kept in as `<scene>.mov` and
        /// `<scene>.json`, or `<scene>.failed.*`, and recorded into first as `<scene>.recording.*`.
        public var folder: URL

        public init(scene: String, folder: URL) {
            self.scene = scene
            self.folder = folder
        }

        /// The movie and step log it's recorded into, until it's done.
        public var recording: (movie: URL, log: URL) { TakeStore.recording(of: scene, in: folder) }

        /// Where it's kept, once done, as `kind`.
        public func kept(_ kind: TakeStore.Kind) -> (movie: URL, log: URL) { TakeStore.files(of: scene, kind.suffix, in: folder) }
    }

    /// Records `target`'s take of `scene` on its set, through `capture`: launches the app, plays the
    /// setup, records the lead-in, the steps with their holds, and the tail, and writes the movie
    /// and its step log, under a name of their own until they're done. Then a take that succeeded
    /// becomes the scene's take, the one it replaces its previous take, as
    /// `TakeStore.keepRecording` says. A take whose step doesn't run is kept as the scene's
    /// latest failure, for its footage to show what went wrong, and the failure is thrown after;
    /// one that couldn't record at all, or is interrupted, keeps nothing and leaves the scene's
    /// takes as they were. The scene's `capture` steps take their stills from the screen being
    /// recorded, which replace the scene's captures when every step ran, as `CaptureStore` says.
    /// Returns the log.
    @discardableResult
    public static func record(
        _ target: Target,
        scene: SceneFile,
        set: ResolvedSet,
        in project: Project,
        on device: Device,
        capture: CaptureDevice,
        player: Player,
        cleanUp: Bool = true,
    ) async throws(RetakeError) -> TakeLog {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let bundleID = try Installer.bundleID(for: project)
        let installed = Launcher.installedVersion(bundleID: bundleID, on: device)
        // Asked before recording starts, as devicectl talking to the device mid-take can upset it.
        guard let screen = Devicectl().screenPoints(of: device) else {
            throw RetakeError(.environment, "Couldn't read \(device.name)'s screen size from devicectl, which the step log needs for its touches and frames.")
        }
        var log = TakeLog(
            scene: target.scene, set: set.name, state: set.state, deviceType: type,
            device: TakeLog.DeviceInfo(
                model: device.model ?? "unknown", marketingName: device.marketingName,
                os: [device.osVersion, device.osBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "),
            ),
            app: TakeLog.AppInfo(bundleID: bundleID, version: installed?.version, build: installed?.build),
            retake: RetakeVersion.current.version, buttonHeist: RetakeVersion.current.buttonHeist,
            recordedAt: Date(), failure: nil, duration: 0, width: 0, height: 0, frames: 0, dropped: 0, screen: screen, launch: nil,
            clock: TakeLog.Clock(deviceAhead: nil), steps: [], shapes: [],
        )
        TakeStore.discardRecording(of: target.scene, in: target.folder)
        do {
            try FileManager.default.createDirectory(at: target.folder, withIntermediateDirectories: true)
        } catch {
            throw RetakeError(.failed, "Couldn't make \(project.displayPath(target.folder)): \(error.localizedDescription)")
        }
        // Until it's kept, an interrupted or unwritten recording is deleted, and the takes are untouched.
        var kept = false
        defer { if !kept { TakeStore.discardRecording(of: target.scene, in: target.folder) } }
        let movie = target.recording.movie

        let recorder = try DeviceRecorder(capture)
        recorder.turning(to: TakeWriter.Facing(scene.orientation))
        let header = log
        let collected = Collected()
        var player = player
        player.screen = screen
        let report = player.report
        player.report = { event in
            if case .finished(let played, let timing) = event, !played.isSetup { collected.add(played, timing) }
            report(event)
        }
        player.turning = { recorder.turning(to: TakeWriter.Facing($0)) }
        player.rotated = { await recorder.rotated() }
        let captures = project.captures(for: type)
        let hasCaptures = scene.steps.contains { $0.action?.capture != nil }
        CaptureStore.discardRecording(of: target.scene, in: captures)
        defer { CaptureStore.discardRecording(of: target.scene, in: captures) }
        let taker = CaptureTaker(
            scene: target.scene, folder: CaptureStore.recording(of: target.scene, in: captures), project: project, report: report,
            screenshot: { url throws(RetakeError) in try Devicectl().screenshot(of: device, to: url) },
        )
        player.capturing = { name throws(RetakeError) in try await taker.take(name) { () throws(RetakeError) in try await recorder.frame() } }
        player.readBeforeSteps = { elements, at in collected.beforeSteps = (elements, at) }

        var failure: RetakeError?
        do throws(RetakeError) {
            try await AppSession.run(target.scene, in: project, set: set, scene: scene, on: device, report: report, cleanUp: cleanUp) { () throws(RetakeError) in
                // Recording from before launch catches the launch screen, and everything up to the
                // first step, which the launch marks place.
                if scene.recordsLaunch, !collected.recording {
                    // Turned first, and given a moment to settle, so the take doesn't open on the
                    // device turning from however the last one left it.
                    try Launcher.turn(device, to: scene.orientation)
                    try? await Task.sleep(for: .seconds(Self.turnSettles))
                    try await recorder.start(writingTo: movie, describing: header)
                    collected.startRecording(at: recorder.startedAt)
                }
            } _: { driver, launched throws(RetakeError) in
                let deviceAhead = try await driver.clockOffset()
                do throws(RetakeError) {
                    try await player.play(scene, named: target.scene, on: driver) { () throws(RetakeError) in
                        if !collected.recording {
                            try await recorder.start(writingTo: movie, describing: header)
                            collected.startRecording(at: recorder.startedAt)
                        }
                        collected.clock = MovieClock(start: collected.startedAt!, deviceAhead: deviceAhead)
                        if scene.recordsLaunch {
                            let clock = collected.clock!
                            collected.launch = TakeLog.Launch(
                                launched: clock.seconds(launched.launched), reported: clock.seconds(launched.reported),
                                connected: clock.seconds(launched.connected),
                            )
                        }
                        // The lead-in is from the movie's start; for a take recorded from before
                        // launch, from now, when the app is reachable, so its first screen settles.
                        let leadIn = scene.recordsLaunch ? scene.leadIn : scene.leadIn - recorder.elapsed
                        if leadIn > 0 { await player.pause(leadIn) }
                    }
                    await player.pause(scene.tail)
                } catch {
                    failure = error
                }
                if collected.recording { collected.summary = try await recorder.stop() }
            }
        } catch {
            // A failure before the first step's played, or in recording itself.
            if collected.recording, collected.summary == nil { collected.summary = try? await recorder.stop() }
            guard collected.summary != nil else { throw error }
            failure = failure ?? error
        }
        if failure == nil, collected.summary == nil { throw RetakeError(.failed, "Nothing was recorded.") }
        let hitches = Launcher.readHitches(bundleID: bundleID, from: device)

        if let summary = collected.summary {
            log.duration = summary.duration
            log.width = summary.width
            log.height = summary.height
            log.frames = summary.frames
            log.dropped = summary.dropped
            log.shapes = summary.shapes
            log.previewAspect = set.aspect(for: type)
        }
        log.failure = failure?.message
        log.launch = collected.launch
        log.clock = TakeLog.Clock(deviceAhead: collected.clock?.deviceAhead)
        if let clock = collected.clock {
            log.beforeSteps = collected.beforeSteps.map { TakeLog.Reading(at: clock.seconds($0.at), elements: $0.elements) }
            log.steps = collected.steps.map { TakeLog.entry($0.played, $0.timing, on: clock) }
            log.hitches = hitches.map { hitches in
                hitches.map { TakeLog.Hitch(at: clock.seconds($0.at.addingTimeInterval(-(clock.deviceAhead ?? 0))), duration: $0.duration) }
                    .filter { $0.at + $0.duration > 0 && $0.at < log.duration }
            }
            if let warning = log.hitchWarning(over: project.settings.hitchThreshold) { report(.warning(warning)) }
        }
        do {
            try Data((JSONWriter.write(log.json) + "\n").utf8).write(to: target.recording.log)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(project.displayPath(target.recording.log)): \(error.localizedDescription)")
        }
        kept = true
        do {
            try TakeStore.keepRecording(of: target.scene, in: target.folder, failed: failure != nil)
        } catch {
            throw RetakeError(.failed, "Couldn't keep the take of \(target.scene) in \(project.displayPath(target.folder)): \(error.localizedDescription)")
        }
        if let failure { throw failure }
        if hasCaptures { try keepCaptures(of: target.scene, in: captures, project: project) }
        return log
    }

    /// The captures a recording took, kept in place of the scene's.
    static func keepCaptures(of scene: String, in captures: URL, project: Project) throws(RetakeError) {
        do {
            try CaptureStore.keepRecording(of: scene, in: captures)
        } catch {
            throw RetakeError(.failed, "Couldn't keep the captures of \(scene) in \(project.displayPath(captures)): \(error.localizedDescription)")
        }
    }

    /// Plays `scene` on its set with the device's screen open but not recorded, for its `capture`
    /// steps alone: its setup, then its steps with their holds, without a lead-in or a tail, and
    /// writes no movie and no step log. Its captures replace the scene's once every step has run;
    /// a failure keeps none, and leaves the scene's as they were. Returns each capture's size.
    @discardableResult
    public static func captureStills(
        of name: String,
        scene: SceneFile,
        set: ResolvedSet,
        in project: Project,
        on device: Device,
        capture: CaptureDevice,
        player: Player,
        cleanUp: Bool = true,
    ) async throws(RetakeError) -> [(width: Int, height: Int)] {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let captures = project.captures(for: type)
        CaptureStore.discardRecording(of: name, in: captures)
        defer { CaptureStore.discardRecording(of: name, in: captures) }
        let recorder = try DeviceRecorder(capture)
        let taker = CaptureTaker(
            scene: name, folder: CaptureStore.recording(of: name, in: captures), project: project, report: player.report,
            screenshot: { url throws(RetakeError) in try Devicectl().screenshot(of: device, to: url) },
        )
        var player = player
        player.capturing = { name throws(RetakeError) in try await taker.take(name) { () throws(RetakeError) in try await recorder.frame() } }
        player.turning = { recorder.turning(to: TakeWriter.Facing($0)) }
        player.rotated = { await recorder.rotated() }
        defer { recorder.close() }
        try await AppSession.run(name, in: project, set: set, scene: scene, on: device, report: player.report, cleanUp: cleanUp) { driver, _ throws(RetakeError) in
            try await player.play(scene, named: name, on: driver) { () throws(RetakeError) in try await recorder.open() }
        }
        try keepCaptures(of: name, in: captures, project: project)
        return taker.taken.map { ($0.width, $0.height) }
    }

    /// What the take gathered as it went, across the closures it runs in.
    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var played: [(played: Player.Played, timing: Player.Timing)] = []
        var recording = false
        var startedAt: Date?
        var clock: MovieClock?
        var launch: TakeLog.Launch?
        /// What was on screen just before the first step, and when, on the Mac's clock.
        var beforeSteps: (elements: [ScreenElement], at: Date)?
        var summary: TakeWriter.Summary?

        func add(_ played: Player.Played, _ timing: Player.Timing) {
            lock.withLock { self.played.append((played, timing)) }
        }

        var steps: [(played: Player.Played, timing: Player.Timing)] { lock.withLock { played } }

        func startRecording(at date: Date) {
            recording = true
            startedAt = date
        }
    }
}
