import ButtonHeist
import Foundation

/// Recording one take of a scene: its movie and its step log. See Documentation/cli.md, "retake record",
/// steps 1 to 4.
public enum TakeRecording {
    /// Where a take is written, and what it's of.
    public struct Target: Sendable {
        public var scene: String
        public var take: Int
        /// The take's movie; its step log is beside it, as `.json`.
        public var movie: URL

        public init(scene: String, take: Int, movie: URL) {
            self.scene = scene
            self.take = take
            self.movie = movie
        }

        public var log: URL { movie.deletingPathExtension().appendingPathExtension("json") }
    }

    /// Records `target`'s take of `scene` on its set, through `capture`: launches the app, plays the
    /// setup, records the lead-in, the steps with their holds, and the tail, and writes the movie
    /// and its step log. A take whose step doesn't run is still written, marked failed, for its
    /// footage to show what went wrong, and the failure is thrown after; one that couldn't record at
    /// all writes nothing. Returns the log.
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
        let screen = Devicectl().screenPoints(of: device)
        var log = TakeLog(
            scene: target.scene, take: target.take, set: set.name, state: set.state, deviceType: type,
            device: TakeLog.DeviceInfo(
                model: device.model ?? "unknown", marketingName: device.marketingName,
                os: [device.osVersion, device.osBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "),
            ),
            app: TakeLog.AppInfo(bundleID: bundleID, version: installed?.version, build: installed?.build),
            retake: RetakeVersion.current.version, buttonHeist: RetakeVersion.current.buttonHeist,
            recordedAt: Date(), failure: nil, duration: 0, width: 0, height: 0, launch: nil,
            clock: TakeLog.Clock(deviceAhead: nil), steps: [], shapes: [],
        )
        do {
            try FileManager.default.createDirectory(at: target.movie.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw RetakeError(.failed, "Couldn't make \(project.displayPath(target.movie.deletingLastPathComponent())): \(error.localizedDescription)")
        }

        let recorder = try DeviceRecorder(capture)
        recorder.turning(to: TakeWriter.Facing(scene.orientation))
        let header = log
        let collected = Collected()
        var player = player
        let report = player.report
        player.report = { event in
            if case .finished(let played, let timing) = event, !played.isSetup { collected.add(played, timing) }
            report(event)
        }
        player.turning = { recorder.turning(to: TakeWriter.Facing($0)) }

        var failure: RetakeError?
        do throws(RetakeError) {
            try await AppSession.run("\(target.scene)-\(target.take)", in: project, set: set, scene: scene, on: device, report: report, cleanUp: cleanUp) { () throws(RetakeError) in
                // Recording from before launch catches the launch screen, and everything up to the
                // first step, which the launch marks place.
                if scene.recordsLaunch, !collected.recording {
                    try await recorder.start(writingTo: target.movie, describing: header)
                    collected.startRecording(at: recorder.startedAt)
                }
            } _: { driver, launched throws(RetakeError) in
                let deviceAhead = try await driver.clockOffset()
                do throws(RetakeError) {
                    try await player.play(scene, named: target.scene, on: driver) { () throws(RetakeError) in
                        if !collected.recording {
                            try await recorder.start(writingTo: target.movie, describing: header)
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
                        // The lead-in is from the movie's start, so a take recorded from before
                        // launch, already longer, waits for nothing more.
                        let leadIn = scene.leadIn - recorder.elapsed
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

        if let summary = collected.summary {
            log.duration = summary.duration
            log.width = summary.width
            log.height = summary.height
            log.frames = summary.frames
            log.dropped = summary.dropped
            log.shapes = summary.shapes
            log.screen = screen
            log.aspect = set.aspect[type].map { SetFile.AspectChoice(portrait: $0.portrait, landscape: $0.landscapeShape) }
        }
        log.failure = failure?.message
        log.launch = collected.launch
        log.clock = TakeLog.Clock(deviceAhead: collected.clock?.deviceAhead)
        if let clock = collected.clock {
            log.steps = collected.steps.map { TakeLog.entry($0.played, $0.timing, on: clock) }
        }
        do {
            try Data((JSONWriter.write(log.json) + "\n").utf8).write(to: target.log)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(project.displayPath(target.log)): \(error.localizedDescription)")
        }
        if let failure { throw failure }
        return log
    }

    /// What the take gathered as it went, across the closures it runs in.
    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var played: [(played: Player.Played, timing: Player.Timing)] = []
        var recording = false
        var startedAt: Date?
        var clock: MovieClock?
        var launch: TakeLog.Launch?
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
