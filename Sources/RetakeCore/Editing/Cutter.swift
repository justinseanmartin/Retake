import AVFoundation
import Foundation

/// What `retake cut` does for one edit and one device type: reads the takes it pins, checks them,
/// plans the cut, composes it with its overlays and sound, and exports it. See docs/cli.md,
/// "retake cut".
public enum Cutter {
    public struct Result: Sendable {
        /// What was written: the master and the preview, or a draft's preview.
        public var files: [URL]
        /// How long the video plays.
        public var duration: Double
        public var warnings: [String]
    }

    /// App Store Connect's limits on a preview's length, in seconds.
    public static let length = 15.0...30.0

    /// Where `edit`'s videos for `type` go: `output/cuts/<type>/<edit>/`.
    public static func folder(_ edit: String, for type: DeviceType, in project: Project) -> URL {
        project.cuts(for: type).appending(path: edit, directoryHint: .isDirectory)
    }

    /// Cuts `name`'s video for `type`. Fails (1) for an edit that can't be read, a pinned take
    /// missing or failed, takes from devices with different screens, an anchor or element that
    /// doesn't resolve, or, unless a draft, a video outside App Store Connect's limits; misuse (2)
    /// for an edit that doesn't name `type`.
    public static func cut(
        _ name: String, for type: DeviceType, in project: Project, draft: Bool = false, report: (String) -> Void = { _ in },
    ) async throws(RetakeError) -> Result {
        let files = ProjectFiles(project: project)
        let read = ProjectFiles.Report()
        guard let edit = files.readEdit(name, into: read) else { throw read.error }
        guard let video = edit.videos[type] else {
            throw RetakeError(.usage, "\(name) isn't cut for \(type.rawValue): its devices are \(edit.devices.map(\.rawValue).joined(separator: ", ")).")
        }

        // The pinned take of every scene the video plays or takes a still from, in the order it
        // first does.
        let scenes = video.clips.flatMap { [$0.take] + $0.stills.map(\.take) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let pins = Dictionary((edit.takes[type] ?? []).map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        var logs: [String: TakeLog] = [:], movies: [String: URL] = [:]
        for scene in scenes {
            guard let number = pins[scene] else {
                throw RetakeError(.failed, "\(name) pins no \(type.rawValue) take of \(scene); run `retake conform \(name)`.")
            }
            guard let take = TakeStore.takes(of: scene, for: [type], in: project).first(where: { $0.number == number }) else {
                throw RetakeError(.failed, "Take \(number) of \(scene), which \(name) pins for \(type.rawValue), isn't recorded; record it, or conform the edit.")
            }
            guard let log = take.recorded, take.problem == nil else {
                throw RetakeError(.failed, "Take \(number) of \(scene) for \(type.rawValue) can't be read: \(take.problem ?? "").")
            }
            if let failure = log.failure {
                throw RetakeError(.failed, "Take \(number) of \(scene) for \(type.rawValue) failed (\(failure)), so it can't be cut from.")
            }
            logs[scene] = log
            movies[scene] = take.movie
        }

        // Points are the screen's, so every take of a type must come from the same screen.
        let screens = Dictionary(grouping: scenes) { scene in
            logs[scene].map { log in log.screen.map { "\(Int($0.width))×\(Int($0.height)) points" } ?? "\(log.width)×\(log.height) pixels" } ?? ""
        }
        if screens.count > 1 {
            let list = screens.sorted { $0.key < $1.key }.map { screen, names in
                "\(screen): \(names.map { "\($0) take \(logs[$0]!.take)" }.joined(separator: ", "))"
            }
            throw RetakeError(.failed, "\(name)'s \(type.rawValue) takes come from devices with different screens: \(list.joined(separator: "; ")).")
        }

        let timelines = logs.mapValues(TakeTimeline.init)
        let plan = try CutPlan.make(video, timelines: timelines)
        let spec = PreviewSpec.of(type)
        let record = MovieMetadata.Video(edit: name, type: type, bundleID: logs[scenes[0]]?.app.bundleID ?? "", takes: scenes.compactMap { logs[$0] })
        var warnings: [String] = []
        if !record.mixed.isEmpty {
            let takes = scenes.compactMap { scene in logs[scene].map { "\(scene) take \($0.take) (\($0.app.version ?? "?") (\($0.app.build ?? "?")), \($0.device.marketingName ?? $0.device.model), iOS \($0.device.os))" } }
            warnings.append("\(name)'s \(type.rawValue) takes span more than one of: \(record.mixed.joined(separator: ", ")): \(takes.joined(separator: "; ")).")
        }
        if !length.contains(plan.duration) {
            let message = "\(name)'s \(type.rawValue) video is \(TakeTimeline.seconds(plan.duration)) long; App Store Connect takes 15 to 30 s."
            guard draft else { throw RetakeError(.failed, message) }
            warnings.append(message)
        }

        report("Composing \(name) for \(type.rawValue), \(TakeTimeline.seconds(plan.duration))...")
        let composition = try await EditComposition.make(plan, movies: movies, logs: logs, spec: spec, background: video.background)
        let overlays = try Overlays.make(video, plan: plan, framings: composition.framings, timelines: timelines)
        let stills = try await stillImages(overlays.stills, movies: movies)
        let sound = try SoundPlan.make(video, plan: plan, overlays: overlays, timelines: timelines, root: project.root)
        let audioMix = try await composition.add(sound, movies: movies)
        let layers = OverlayLayers(overlays, spec: spec, stills: stills)
        let blurs = PreviewExport.blurs(turns: composition.turnBlurs, overlays: overlays, canvas: spec.size)

        let folder = folder(name, for: type, in: project)
        let base = "\(name)-\(type.rawValue)"
        if draft {
            let first = FileManager.default.temporaryDirectory.appending(path: "retake-draft-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: first) }
            let preview = folder.appending(path: "\(base)-draft.mp4")
            report("Rendering a draft...")
            try await PreviewExport.master(composition, audioMix: audioMix, layers: layers, metadata: [], to: first, draft: true)
            try await PreviewExport.preview(from: first, to: preview, spec: spec, blurs: blurs, metadata: MovieMetadata.preview(record), scale: 0.5, bitRate: 3_000_000)
            return Result(files: [preview], duration: plan.duration, warnings: warnings)
        }
        let master = folder.appending(path: "\(base)-master.mov")
        let preview = folder.appending(path: "\(base).mp4")
        report("Rendering the master...")
        try await PreviewExport.master(composition, audioMix: audioMix, layers: layers, metadata: MovieMetadata.video(record), to: master)
        report("Encoding for App Store Connect...")
        try await PreviewExport.preview(from: master, to: preview, spec: spec, blurs: blurs, metadata: MovieMetadata.preview(record))
        let size = (try? FileManager.default.attributesOfItem(atPath: preview.path)[.size] as? Int) ?? 0
        if size > 500_000_000 {
            throw RetakeError(.failed, "\(preview.lastPathComponent) is \(size / 1_000_000) MB; App Store Connect takes at most 500 MB.")
        }
        return Result(files: [master, preview], duration: plan.duration, warnings: warnings)
    }

    /// Each still's frame, from its take's movie.
    static func stillImages(_ stills: [Overlays.Still], movies: [String: URL]) async throws(RetakeError) -> [CGImage] {
        var images: [CGImage] = []
        for still in stills {
            guard let movie = movies[still.take] else { throw RetakeError(.failed, "There's no take of \(still.take) for a still.") }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                images.append(try await generator.image(at: CMTime(seconds: still.at, preferredTimescale: 600)).image)
            } catch {
                throw RetakeError(.failed, "Couldn't take a still from \(movie.lastPathComponent) at \(TakeTimeline.seconds(still.at)): \(error.localizedDescription)")
            }
        }
        return images
    }
}
