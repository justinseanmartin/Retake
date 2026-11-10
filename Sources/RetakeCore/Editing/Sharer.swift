import AVFoundation
import CoreImage
import Foundation

/// What `retake share` is asked for: one video of clips side by side, each an edit's cut or a
/// scene's take, for a device type. See Documentation/cli.md, "retake share".
public struct ShareRequest: Equatable, Sendable {
    public struct Clip: Equatable, Sendable, CustomStringConvertible {
        /// An edit's name, for its cut, or a scene's, for its take.
        public var name: String
        public var type: DeviceType

        public init(name: String, type: DeviceType) {
            self.name = name
            self.type = type
        }

        /// How it's written on the command line: `showcase/iphone`.
        public var description: String { "\(name)/\(type.rawValue)" }
    }

    public var clips: [Clip]

    /// The most clips a share puts side by side, past which each is too small to make out on a
    /// phone.
    public static let most = 4

    /// What the video's file is called, without its extension: each clip's name and type, joined
    /// as they're joined on the command line, `showcase-iphone+showcase-ipad`.
    public var fileName: String {
        clips.map { "\($0.name)-\($0.type.rawValue)" }.joined(separator: String(ProjectFiles.shareJoin))
    }

    /// `text` as the command line gives it, `showcase/iphone+showcase/ipad`: clips joined by `+`,
    /// each typed by `type`, `--type`'s, or by its own `/iphone` or `/ipad`, one or the other for
    /// every clip. Misuse (2) for one that can't be read.
    public static func parse(_ text: String, type: DeviceType?) throws(RetakeError) -> ShareRequest {
        let parts = text.split(separator: ProjectFiles.shareJoin, omittingEmptySubsequences: false).map(String.init)
        if parts.contains(where: \.isEmpty) {
            throw RetakeError(.usage, "\"\(text)\" has an empty clip; join clips with \(ProjectFiles.shareJoin), as showcase/iphone\(ProjectFiles.shareJoin)showcase/ipad.")
        }
        if parts.count > most {
            throw RetakeError(.usage, "\"\(text)\" joins \(parts.count) clips; a share puts at most \(most) side by side.")
        }
        var clips: [Clip] = []
        for part in parts {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2, !pieces[0].isEmpty else {
                throw RetakeError(.usage, "\"\(part)\" isn't a clip; a clip is an edit or a scene, and its device type after a /, as showcase/iphone.")
            }
            switch (pieces.count == 2 ? pieces[1] : nil, type) {
            case (let named?, nil):
                guard let named = DeviceType(rawValue: named) else {
                    throw RetakeError(.usage, "\"\(part)\": \"\(named)\" isn't a device type; it's iphone or ipad.")
                }
                clips.append(Clip(name: pieces[0], type: named))
            case (nil, let type?):
                clips.append(Clip(name: pieces[0], type: type))
            case (_?, _?):
                throw RetakeError(.usage, "\"\(part)\" names its device type, and so does --type; give it one way: --type for every clip, or each clip's own.")
            case (nil, nil):
                throw RetakeError(.usage, "\"\(part)\" names no device type; give --type, or each clip's own, as \(part)/iphone.")
            }
        }
        return ShareRequest(clips: clips)
    }
}

/// Where each of a share's clips goes in its picture. One clip alone is 720 pixels wide; clips
/// joined are each 960 pixels tall, side by side in the order given, with 24-pixel gutters of the
/// background around and between them, all shrunk to fit 1920 pixels wide.
public struct ShareLayout: Equatable, Sendable {
    public var canvas: CGSize
    /// Each clip's place, top-down, in order.
    public var frames: [CGRect]

    public static let width = 720.0
    public static let height = 960.0
    public static let gutter = 24.0
    public static let widest = 1920.0

    /// Encoders take even sizes.
    static func even(_ value: Double) -> Double { (value / 2).rounded() * 2 }

    public static func of(_ sizes: [CGSize]) -> ShareLayout {
        if sizes.count == 1 {
            let canvas = CGSize(width: width, height: even(width * sizes[0].height / sizes[0].width))
            return ShareLayout(canvas: canvas, frames: [CGRect(origin: .zero, size: canvas)])
        }
        let widths = sizes.map { height * $0.width / $0.height }
        let total = widths.reduce(0, +) + gutter * Double(sizes.count + 1)
        let scale = min(1, widest / total)
        var frames: [CGRect] = []
        var x = gutter * scale
        for clipWidth in widths {
            frames.append(CGRect(x: x, y: gutter * scale, width: clipWidth * scale, height: height * scale))
            x += (clipWidth + gutter) * scale
        }
        return ShareLayout(canvas: CGSize(width: even(total * scale), height: even((height + 2 * gutter) * scale)), frames: frames)
    }
}

/// What `retake share` does: finds each clip's movie, an edit's master or a scene's take, and
/// writes them side by side as a small H.264 for sharing. See Documentation/cli.md, "retake share".
public enum Sharer {
    /// A clip's movie, and what's known of it before it's shared.
    public struct Source: Sendable {
        public var clip: ShareRequest.Clip
        public var movie: URL
        /// Whether it's a scene's take, rather than an edit's cut.
        public var isTake: Bool
        public var duration: Double
        public var hasSound: Bool
        /// What Retake wrote into its movie, for the share's own record; nil when it can't be read.
        public var record: MovieInfo?

        public init(clip: ShareRequest.Clip, movie: URL, isTake: Bool, duration: Double, hasSound: Bool, record: MovieInfo? = nil) {
            self.clip = clip
            self.movie = movie
            self.isTake = isTake
            self.duration = duration
            self.hasSound = hasSound
            self.record = record
        }
    }

    /// How much longer than the first clip another can run before the first's sound, which a
    /// video has unless told otherwise, is taken to end too soon.
    public static let soundOverrun = 1.0

    /// The clips after the first that run more than `soundOverrun` longer than it, so the first's
    /// sound would end well before the video does: which clip's sound it has is to be chosen.
    public static func outrunning(_ sources: [Source]) -> [Source] {
        guard let first = sources.first else { return [] }
        return sources.dropFirst().filter { $0.duration - first.duration > soundOverrun }
    }

    /// `clip`'s movie: its edit's master, or its scene's take. Fails (1) for a name that's both an
    /// edit's and a scene's, or for a cut or take that isn't there; misuse (2) for a name that's
    /// neither.
    public static func source(_ clip: ShareRequest.Clip, in project: Project) async throws(RetakeError) -> Source {
        let files = ProjectFiles(project: project)
        let isEdit = FileManager.default.fileExists(atPath: files.editURL(clip.name).path)
        let isScene = DeviceType.allCases.contains { FileManager.default.fileExists(atPath: files.sceneURL(clip.name, for: $0).path) }
            || TakeStore.take(of: clip.name, for: clip.type, in: project) != nil
        if isEdit, isScene {
            throw RetakeError(.failed, "\(clip): \(ProjectFiles.sharedName(clip.name)).")
        }
        let movie: URL
        if isEdit {
            movie = Cutter.folder(clip.name, for: clip.type, in: project).appending(path: "\(clip.name)-\(clip.type.rawValue)-master.mov")
            guard FileManager.default.fileExists(atPath: movie.path) else {
                throw RetakeError(.failed, "\(clip): there's no \(clip.type.rawValue) cut of \(clip.name) to share (\(project.displayPath(movie))); cut it with `retake cut \(clip.name) --type \(clip.type.rawValue)`.")
            }
        } else if isScene {
            try TakeStore.refuseOldLayout(for: [clip.type], in: project)
            guard let take = TakeStore.take(of: clip.name, for: clip.type, in: project), take.successful else {
                throw RetakeError(.failed, "\(clip): there's no successful \(clip.type.rawValue) take of \(clip.name) to share; record it.")
            }
            movie = take.movie
        } else {
            throw RetakeError(.usage, "\(clip): there's no edit or scene \"\(clip.name)\".")
        }
        let asset = AVURLAsset(url: movie)
        do {
            let duration = try await asset.load(.duration).seconds
            let hasSound = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            let record = try? await MovieInfo.read(movie)
            return Source(clip: clip, movie: movie, isTake: !isEdit, duration: duration, hasSound: hasSound, record: record)
        } catch {
            throw RetakeError(.failed, "\(clip): couldn't read \(project.displayPath(movie)): \(error.localizedDescription)")
        }
    }

    /// How densely the picture is encoded, in bits a pixel a frame: small, for a screen recording
    /// of an app, which is mostly flat color and still.
    static let bitsPerPixel = 0.04
    public static let framesPerSecond = 30

    /// `sources` side by side, as `ShareLayout` places them, on `background`, to `url`, as long as
    /// the longest, each shorter one holding its last frame, with the sound of `sources[audio]`
    /// alone, if it has any. Returns how long it plays, and its picture's size.
    public static func share(_ sources: [Source], audio: Int, background: Color, to url: URL) async throws(RetakeError) -> (duration: Double, size: CGSize) {
        do {
            return try await write(sources, audio: audio, background: background, to: url)
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func write(_ sources: [Source], audio: Int, background: Color, to url: URL) async throws -> (duration: Double, size: CGSize) {
        var outputs: [AVAssetReaderTrackOutput] = [], readers: [AVAssetReader] = [], sizes: [CGSize] = []
        for source in sources {
            let asset = AVURLAsset(url: source.movie)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw RetakeError(.failed, "\(source.clip): \(source.movie.lastPathComponent) has no picture.")
            }
            sizes.append(try await track.load(.naturalSize))
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            readers.append(reader)
            outputs.append(output)
        }
        let layout = ShareLayout.of(sizes)
        let duration = sources.map(\.duration).max() ?? 0
        let width = Int(layout.canvas.width), height = Int(layout.canvas.height)

        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(width * height * framesPerSecond) * bitsPerPixel),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
            ],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(videoIn)
        writer.metadata = MovieMetadata.share(sources.map { ($0.clip.description, $0.record) })

        var sound: Copier?
        if sources[audio].hasSound {
            let asset = AVURLAsset(url: sources[audio].movie)
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2])
                reader.add(output)
                readers.append(reader)
                let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
                ])
                writer.add(audioIn)
                sound = Copier(output: output, input: audioIn, label: "share.audio", painter: nil)
            }
        }

        for reader in readers where !reader.startReading() {
            let name = (reader.asset as? AVURLAsset)?.url.lastPathComponent ?? "a clip"
            throw RetakeError(.failed, "Couldn't read \(name): \(String(describing: reader.error))")
        }
        guard writer.startWriting() else { throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)

        let frames = max(1, Int((duration * Double(framesPerSecond)).rounded(.up)))
        let painter = SharePainter(outputs: outputs, layout: layout, background: background, input: videoIn, adaptor: adaptor, frames: frames)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await painter.run() }
            if let sound { group.addTask { await sound.run() } }
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(String(describing: writer.error))")
        }
        return (Double(frames) / Double(framesPerSecond), layout.canvas)
    }
}

/// Draws a share's frames, 30 a second, each clip's latest frame at or before the moment, so a
/// clip that's ended holds its last, and appends them, on its own queue, the only place its
/// readers and the writer's picture are touched once it starts.
private final class SharePainter: @unchecked Sendable {
    let outputs: [AVAssetReaderTrackOutput]
    let layout: ShareLayout
    let backdrop: CIImage
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let frames: Int
    let queue = DispatchQueue(label: "Sharer.video")
    let context = CIContext()
    var current: [CMSampleBuffer?]
    var pending: [CMSampleBuffer?]
    var ended: [Bool]
    var index = 0

    init(outputs: [AVAssetReaderTrackOutput], layout: ShareLayout, background: Color, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, frames: Int) {
        self.outputs = outputs
        self.layout = layout
        let color = CIColor(red: background.red, green: background.green, blue: background.blue, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? .black
        backdrop = CIImage(color: color).cropped(to: CGRect(origin: .zero, size: layout.canvas))
        self.input = input
        self.adaptor = adaptor
        self.frames = frames
        current = Array(repeating: nil, count: outputs.count)
        pending = Array(repeating: nil, count: outputs.count)
        ended = Array(repeating: false, count: outputs.count)
    }

    /// The next frame of clip `clip` that has a picture, or nil once it's ended.
    func read(_ clip: Int) -> CMSampleBuffer? {
        while !ended[clip] {
            guard let sample = outputs[clip].copyNextSampleBuffer() else {
                ended[clip] = true
                return nil
            }
            if sample.imageBuffer != nil { return sample }
        }
        return nil
    }

    /// Moves clip `clip` on to its latest frame at or before `time`, or its first, before it starts.
    func advance(_ clip: Int, to time: Double) {
        if current[clip] == nil { current[clip] = read(clip) }
        while true {
            if pending[clip] == nil { pending[clip] = read(clip) }
            guard let next = pending[clip], next.presentationTimeStamp.seconds <= time + 1e-6 else { return }
            current[clip] = next
            pending[clip] = nil
        }
    }

    func frame(at time: Double) -> CIImage {
        var image = backdrop
        let canvasHeight = layout.canvas.height
        for (clip, place) in layout.frames.enumerated() {
            advance(clip, to: time)
            guard let pixels = current[clip]?.imageBuffer else { continue }
            let picture = CIImage(cvPixelBuffer: pixels)
            let scale = place.height / picture.extent.height
            let scaled = picture.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: place.width / (picture.extent.width * scale),
            ])
            // Core Image's origin is at the bottom.
            let target = CGRect(x: place.minX, y: canvasHeight - place.maxY, width: place.width, height: place.height)
            let placed = scaled.transformed(by: CGAffineTransform(translationX: target.minX - scaled.extent.minX, y: target.minY - scaled.extent.minY))
            image = placed.cropped(to: target).composited(over: image)
        }
        return image
    }

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    guard index < frames, let pool = adaptor.pixelBufferPool else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    if let buffer {
                        context.render(frame(at: Double(index) / Double(Sharer.framesPerSecond)), to: buffer)
                        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Sharer.framesPerSecond)))
                    }
                    index += 1
                }
            }
        }
    }
}
