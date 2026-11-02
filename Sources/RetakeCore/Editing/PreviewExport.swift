import AVFoundation
import CoreImage

/// Renders a composition in two passes. What's drawn over the picture renders only through an
/// export session, which can't set a bit rate or draw a filter on each frame, so the first pass
/// writes a master, ProRes, with the overlays and the sound, and copies it again drawing the blurs
/// on each frame, when there are any, so the master hides what the video does. The second pass
/// re-encodes the master to App Store Connect's specification for app previews, H.264 High Profile
/// 4.0 at about 11 Mbps with 256 kbps stereo AAC at 48 kHz. A draft keeps no master, so its second
/// pass draws the blurs instead, and is faster and smaller.
public enum PreviewExport {
    /// A rectangle of the canvas, top-down, blurred from `start` to `end` in the video.
    public struct BlurRegion: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var rect: CGRect
        /// The Gaussian sigma, in canvas pixels.
        public var sigma: Double
        /// Whether the blur swells from none to `sigma` at the region's middle and back, as a turn's
        /// does, rather than holding at `sigma`.
        public var swells: Bool

        public init(start: Double, end: Double, rect: CGRect, sigma: Double, swells: Bool = false) {
            self.start = start
            self.end = end
            self.rect = rect
            self.sigma = sigma
            self.swells = swells
        }

        public func sigma(at time: Double) -> Double {
            guard swells, end > start else { return sigma }
            return sigma * sin(.pi * (time - start) / (end - start))
        }
    }

    /// How strongly a turn is blurred at its middle, in canvas pixels, as the editor Retake grew
    /// from did.
    public static let turnBlurSigma = 18.0

    /// The blurs of a cut: each turn's, over the whole canvas, swelling; and each the edit names,
    /// over its rectangle.
    public static func blurs(turns: [ClosedRange<Double>], overlays: Overlays, canvas: CGSize) -> [BlurRegion] {
        turns.map { BlurRegion(start: $0.lowerBound, end: $0.upperBound, rect: CGRect(origin: .zero, size: canvas), sigma: turnBlurSigma, swells: true) }
            + overlays.blurs.map { BlurRegion(start: $0.start, end: $0.end, rect: $0.rect, sigma: $0.radius) }
    }

    /// The first pass: `composition` with `layers` drawn over it, `blurs` over those, and
    /// `audioMix`'s sound, to `url`, as ProRes, or for a draft, H.264.
    public static func master(
        _ composition: EditComposition, audioMix: AVAudioMix?, layers: OverlayLayers?, blurs: [BlurRegion] = [], metadata: [AVMetadataItem], to url: URL,
        draft: Bool = false,
    ) async throws(RetakeError) {
        guard !blurs.isEmpty else {
            return try await export(composition, audioMix: audioMix, layers: layers, metadata: metadata, to: url, draft: draft)
        }
        // Beside the master rather than in the temporary directory, since it's as big.
        let unblurred = url.deletingLastPathComponent().appending(path: ".\(url.deletingPathExtension().lastPathComponent)-unblurred.mov")
        defer { try? FileManager.default.removeItem(at: unblurred) }
        try await export(composition, audioMix: audioMix, layers: layers, metadata: [], to: unblurred, draft: draft)
        do {
            try await encode(from: unblurred, to: url, as: .master(draft: draft), blurs: blurs, metadata: metadata)
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "Couldn't blur \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func export(
        _ composition: EditComposition, audioMix: AVAudioMix?, layers: OverlayLayers?, metadata: [AVMetadataItem], to url: URL, draft: Bool,
    ) async throws(RetakeError) {
        let videoComposition = composition.videoComposition.mutableCopy() as! AVMutableVideoComposition
        if let layers {
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: layers.video, in: layers.parent)
        }
        let preset = draft ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleProRes422LPCM
        guard let session = AVAssetExportSession(asset: composition.composition, presetName: preset) else {
            throw RetakeError(.failed, "There's no export for \(draft ? "H.264" : "ProRes") here.")
        }
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        // A take's sound sped up with its clip keeps its pitch.
        session.audioTimePitchAlgorithm = .spectral
        session.metadata = metadata
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await session.export(to: url, as: .mov)
        } catch {
            throw RetakeError(.failed, "Couldn't render \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// The second pass: the master re-encoded for App Store Connect, at `scale` of its size, with
    /// `blurs` drawn, to `url`: none, for a master that has them already.
    public static func preview(
        from master: URL, to url: URL, spec: PreviewSpec, blurs: [BlurRegion], metadata: [AVMetadataItem], scale: Double = 1, bitRate: Int = 11_000_000,
    ) async throws(RetakeError) {
        do {
            try await encode(from: master, to: url, as: .preview(spec, scale: scale, bitRate: bitRate), blurs: blurs, metadata: metadata)
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// What `encode` writes: App Store Connect's H.264, or a master as the first pass makes it, its
    /// sound copied as it is.
    enum Encoding {
        case preview(PreviewSpec, scale: Double, bitRate: Int)
        case master(draft: Bool)
    }

    static func encode(from source: URL, to url: URL, as encoding: Encoding, blurs: [BlurRegion], metadata: [AVMetadataItem]) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw RetakeError(.failed, "The master has no picture.") }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let size = try await video.load(.naturalSize)
        var scale = 1.0
        if case .preview(_, let previewScale, _) = encoding { scale = previewScale }
        let width = Int((size.width * scale / 2).rounded()) * 2, height = Int((size.height * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(videoOut)

        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer: AVAssetWriter
        let videoIn: AVAssetWriterInput
        let sound: Copier?
        switch encoding {
        case .preview(let spec, _, let bitRate):
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
                    AVVideoExpectedSourceFrameRateKey: spec.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: spec.framesPerSecond,
                ],
            ])
            let audioOut = audio.map {
                AVAssetReaderTrackOutput(track: $0, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2])
            }
            if let audioOut { reader.add(audioOut) }
            // A video with no sound of its own still gets a stereo track, silent, as App Store
            // Connect's audio requirements expect one.
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000,
            ])
            writer.add(audioIn)
            let duration = try await asset.load(.duration).seconds
            sound = try audioOut.map { Copier(output: $0, input: audioIn, label: "audio", painter: nil) }
                ?? Copier(silence: Self.silence(seconds: duration), input: audioIn)
        case .master(let draft):
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: draft ? AVVideoCodecType.h264 : AVVideoCodecType.proRes422, AVVideoWidthKey: width, AVVideoHeightKey: height,
            ])
            if let audio {
                let audioOut = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
                reader.add(audioOut)
                let hint = try await audio.load(.formatDescriptions).first
                let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
                writer.add(audioIn)
                sound = Copier(output: audioOut, input: audioIn, label: "audio", painter: nil)
            } else {
                sound = nil
            }
        }
        writer.metadata = metadata
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(videoIn)

        guard reader.startReading() else { throw RetakeError(.failed, "Couldn't read \(source.lastPathComponent): \(String(describing: reader.error))") }
        guard writer.startWriting() else { throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)

        let painter = FramePainter(blurs: blurs, canvasHeight: size.height, scale: scale, adaptor: adaptor)
        let copiers = [Copier(output: videoOut, input: videoIn, label: "video", painter: painter)] + (sound.map { [$0] } ?? [])
        await withTaskGroup(of: Void.self) { group in
            for copier in copiers { group.addTask { await copier.run() } }
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(String(describing: writer.error))")
        }
    }
}

extension PreviewExport {
    /// Stereo silence at 48 kHz, `seconds` long, in buffers of 1024 frames.
    static func silence(seconds: Double) throws -> [CMSampleBuffer] {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0,
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw RetakeError(.failed, "Couldn't make a silent sound track.") }
        let total = Int(seconds * 48000)
        return try stride(from: 0, to: total, by: 1024).map { start in
            let frames = min(1024, total - start)
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: frames * 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block,
            )
            guard let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: frames * 4) == noErr else {
                throw RetakeError(.failed, "Couldn't make a silent sound track.")
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
                presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sample,
            )
            guard let sample else { throw RetakeError(.failed, "Couldn't make a silent sound track.") }
            return sample
        }
    }
}

/// Copies one track's samples to the writer on its own queue, the only place either is touched
/// once copying starts: from the reader, the picture's through the painter, or from silence made
/// up front.
private final class Copier: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput?
    var silence: [CMSampleBuffer]
    let input: AVAssetWriterInput
    let queue: DispatchQueue
    let painter: FramePainter?

    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, label: String, painter: FramePainter?) {
        self.output = output
        silence = []
        self.input = input
        queue = DispatchQueue(label: "PreviewExport.\(label)")
        self.painter = painter
    }

    init(silence: [CMSampleBuffer], input: AVAssetWriterInput) {
        output = nil
        self.silence = silence.reversed()
        self.input = input
        queue = DispatchQueue(label: "PreviewExport.silence")
        painter = nil
    }

    func next() -> CMSampleBuffer? {
        output.map { $0.copyNextSampleBuffer() } ?? silence.popLast()
    }

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    guard let sample = next() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if let painter { painter.append(sample) } else { input.append(sample) }
                }
            }
        }
    }
}

/// Draws each frame at the preview's size, with the blurs in force at its time, and appends it.
private final class FramePainter: @unchecked Sendable {
    let blurs: [PreviewExport.BlurRegion]
    let canvasHeight: Double
    let scale: Double
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let context = CIContext()

    init(blurs: [PreviewExport.BlurRegion], canvasHeight: Double, scale: Double, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        self.blurs = blurs
        self.canvasHeight = canvasHeight
        self.scale = scale
        self.adaptor = adaptor
    }

    func append(_ sample: CMSampleBuffer) {
        guard let pixels = sample.imageBuffer, let pool = adaptor.pixelBufferPool else { return }
        let time = sample.presentationTimeStamp.seconds
        let frame = CIImage(cvPixelBuffer: pixels)
        var result = frame
        for region in blurs where time >= region.start && time < region.end {
            let sigma = region.sigma(at: time)
            guard sigma > 0.5 else { continue }
            // Core Image's origin is at the bottom.
            let rect = CGRect(x: region.rect.minX, y: canvasHeight - region.rect.maxY, width: region.rect.width, height: region.rect.height)
            result = frame.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: rect).composited(over: result)
        }
        if scale != 1 { result = result.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { return }
        context.render(result, to: output)
        adaptor.append(output, withPresentationTime: sample.presentationTimeStamp)
    }
}
