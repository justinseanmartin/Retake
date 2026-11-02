import AVFoundation
import CoreImage
import Foundation

/// A take's movie, written from a device's capture stream: video at the device's own size, and its
/// sound. See README.md, "Takes" and "Turns".
///
/// The stream changes shape when the device turns, but a movie has one size, so the file keeps the
/// shape of the first frame and a frame of the other shape is turned a quarter to fit, the way the
/// device's own screen faces: the take then shows what a camera fixed to the device would. Each
/// change of shape is kept, with when it happened, for the step log and the edit to turn back.
///
/// Not thread-safe: one queue appends to it, the capture's, and `finish` is called after the last
/// append. Through `AVAssetWriter` rather than `AVCaptureMovieFileOutput`, which ends the file at the
/// first break in the stream, and `devicectl` talking to the device mid-take causes one.
public final class TakeWriter: @unchecked Sendable {
    /// Which way the device faces, for which way to turn frames of the other shape.
    public enum Facing: Sendable, Equatable {
        case portrait
        case portraitUpsideDown
        /// Turned with its top to the left, as `devicectl` names `landscapeLeft`.
        case landscapeLeft
        case landscapeRight

        var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    }

    /// A change in the stream's shape: when, in seconds from the movie's start, the size of the
    /// frames from then on, and the quarter turn they were stored with.
    public struct ShapeChange: Equatable, Sendable {
        public var at: Double
        public var width: Int
        public var height: Int
        /// Degrees clockwise the frame was turned to fit the file: 0, 90 or -90.
        public var turn: Int
    }

    public struct Summary: Equatable, Sendable {
        /// Seconds of video written.
        public var duration: Double
        public var frames: Int
        /// The file's size, the first frame's.
        public var width: Int
        public var height: Int
        /// Frames the writer wasn't ready for, as opposed to frames the device never sent.
        public var dropped: Int
        /// Samples skipped for arriving stamped no later than the one before, as a resync of the
        /// stream's clock can, which the writer would otherwise fail on.
        public var outOfOrder: Int
        /// The first frame's shape, and each change after it.
        public var shapes: [ShapeChange]
    }

    private let url: URL
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let context = CIContext()

    /// The first frame's time, which the movie starts at.
    public private(set) var start: CMTime?
    private var lastVideo = CMTime.invalid
    /// The last frame written, to write again while the screen is still.
    private var held: CVPixelBuffer?
    private var lastAudio = CMTime.invalid
    /// Where the sound written so far ends. The device sends nothing while it's silent, and the
    /// encoder would close the gap, pulling every later sound earlier than its frame.
    private var audioEnd = CMTime.invalid
    private var size = (width: 0, height: 0)
    private var frames = 0
    private var dropped = 0
    private var outOfOrder = 0
    private var shapes: [ShapeChange] = []

    /// Which way the device faces now; set before turning it, so frames of the new shape are
    /// turned the right way.
    public var facing: Facing = .portrait {
        didSet { if start != nil { chooseTurn() } }
    }
    /// Which way the device faced at the first frame, whose shape the file has.
    private var startFacing: Facing = .portrait
    /// How frames of the other shape are turned: chosen when the device is turned into that shape,
    /// and kept while it's turned back, since the frames are still of that shape until the device
    /// has turned.
    private var otherShapeTurn: Int?

    /// Whether frames come live, so one the encoder isn't ready for is dropped rather than waited
    /// for, as a capture's must be; false waits, for frames made up in tests.
    private let live: Bool

    /// What the movie says about how it was made, written with it.
    private let metadata: [AVMetadataItem]

    public init(writingTo url: URL, metadata: [AVMetadataItem] = [], live: Bool = true) {
        self.url = url
        self.metadata = metadata
        self.live = live
    }

    /// Whether the writer failed, as it now and then does a moment in, and should be started over.
    public var failed: Bool { writer?.status == .failed }

    /// Seconds of video written so far.
    public var written: Double {
        guard let start, lastVideo.isValid else { return 0 }
        return (lastVideo - start).seconds
    }

    public func appendVideo(_ sample: CMSampleBuffer) {
        let time = sample.presentationTimeStamp
        guard let pixels = sample.imageBuffer else { return }
        if writer == nil { begin(with: pixels, at: time) }
        guard let start, let adaptor, let video else { return }
        guard !lastVideo.isValid || time > lastVideo else {
            outOfOrder += 1
            return
        }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let turn = width == size.width && height == size.height ? 0 : otherShapeTurn ?? Self.turn(for: facing, startedFacing: startFacing)
        if shapes.last.map({ $0.width != width || $0.height != height }) ?? true {
            shapes.append(ShapeChange(at: (time - start).seconds, width: width, height: height, turn: turn))
        }
        guard let fitted = fitted(pixels, turning: turn) else {
            dropped += 1
            return
        }
        // The device sends nothing while its screen is still, and a clip cut from inside such a
        // stretch would have no picture until the next frame came: black, under its overlays. So
        // the last frame is written again every sixtieth of a second until this one.
        if let held, lastVideo.isValid {
            var at = lastVideo + Self.repeatEvery
            while at + Self.repeatEvery <= time {
                guard ready(video), adaptor.append(held, withPresentationTime: at) else { break }
                at = at + Self.repeatEvery
            }
        }
        guard ready(video), adaptor.append(fitted, withPresentationTime: time) else {
            dropped += 1
            return
        }
        lastVideo = time
        held = fitted
        frames += 1
    }

    /// How often a still screen's frame is written again.
    static let repeatEvery = CMTime(value: 1, timescale: 60)

    /// Whether `input` takes more now. Not live, as in tests, the writer is waited for, but not
    /// forever: with nothing written to its sound input, it can stop taking video until sound comes.
    private func ready(_ input: AVAssetWriterInput) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !live, !input.isReadyForMoreMediaData, writer?.status == .writing, Date() < deadline { usleep(1000) }
        return input.isReadyForMoreMediaData
    }

    public func appendAudio(_ sample: CMSampleBuffer) {
        let time = sample.presentationTimeStamp
        guard let start, time >= start, let audio, audio.isReadyForMoreMediaData else { return }
        guard !lastAudio.isValid || time > lastAudio else {
            outOfOrder += 1
            return
        }
        let gapStart = audioEnd.isValid ? audioEnd : start
        if (time - gapStart).seconds > 0.001, let silence = Self.silence(like: sample, from: gapStart, to: time) {
            audio.append(silence)
        }
        if audio.append(sample) {
            lastAudio = time
            audioEnd = time + sample.duration
        }
    }

    /// Ends the file, which is then complete.
    public func finish() async throws(RetakeError) -> Summary {
        guard let writer, let start else { throw RetakeError(.failed, "Nothing was recorded: no frames arrived.") }
        video?.markAsFinished()
        audio?.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw RetakeError(.failed, "The recording couldn't be finished: \(writer.error.map { "\($0)" } ?? "unknown error").")
        }
        let duration = lastVideo.isValid ? (lastVideo - start).seconds : 0
        return Summary(duration: duration, frames: frames, width: size.width, height: size.height, dropped: dropped, outOfOrder: outOfOrder, shapes: shapes)
    }

    /// Abandons the file, for a start that failed.
    public func cancel() {
        writer?.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    /// Facing the other shape from the file's, picks the turn for that shape's frames; facing the
    /// file's own shape keeps it, for the frames still coming before the device has turned back.
    private func chooseTurn() {
        if facing.isLandscape != startFacing.isLandscape {
            otherShapeTurn = Self.turn(for: facing, startedFacing: startFacing)
        }
    }

    /// Degrees clockwise to turn a frame of the other shape so it faces as the device does: a
    /// device turned with its top to the left shows the app upright to someone holding it, so in
    /// the device's own frame the app's top is at its right, a quarter turn clockwise. A take that
    /// started turned has a landscape file, and its upright frames are turned back the other way.
    public static func turn(for facing: Facing, startedFacing: Facing) -> Int {
        switch facing {
        case .landscapeLeft: 90
        case .landscapeRight: -90
        case .portrait, .portraitUpsideDown:
            switch startedFacing {
            case .landscapeLeft: -90
            case .landscapeRight: 90
            // Turned by hand, so which way isn't known: as if to the left, the more usual.
            case .portrait, .portraitUpsideDown: 90
            }
        }
    }

    /// Sized from the first frame, since the device reports no format until frames arrive.
    private func begin(with pixels: CVPixelBuffer, at time: CMTime) {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000],
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ])
        for input in [video, audio] {
            input.expectsMediaDataInRealTime = live
            writer.add(input)
        }
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        warmUpTurning(width: width, height: height)
        writer.metadata = metadata
        writer.startWriting()
        writer.startSession(atSourceTime: time)
        self.writer = writer
        self.video = video
        self.audio = audio
        size = (width, height)
        start = time
        startFacing = facing
        otherShapeTurn = nil
    }

    /// The first quarter turn compiles Core Image's kernels, which held the capture queue for a
    /// quarter second and lost the frames behind it, so one blank frame is turned up front.
    private func warmUpTurning(width: Int, height: Int) {
        var blank: CVPixelBuffer?, out: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        CVPixelBufferCreate(nil, height, width, kCVPixelFormatType_32BGRA, attributes, &blank)
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &out)
        guard let blank, let out else { return }
        render(blank, turning: 90, into: out)
    }

    /// The frame in the file's shape: as it is, or turned a quarter.
    private func fitted(_ pixels: CVPixelBuffer, turning degrees: Int) -> CVPixelBuffer? {
        guard degrees != 0 else { return pixels }
        guard let pool = adaptor?.pixelBufferPool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }
        render(pixels, turning: degrees, into: out)
        return out
    }

    private func render(_ pixels: CVPixelBuffer, turning degrees: Int, into out: CVPixelBuffer) {
        // Core Image's y runs up, so a turn clockwise on screen is `.right`'s.
        let image = CIImage(cvPixelBuffer: pixels).oriented(degrees > 0 ? .right : .left)
        context.render(image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)), to: out)
    }

    /// Silent PCM in the format of `sample`, filling `start` to `end`.
    static func silence(like sample: CMSampleBuffer, from start: CMTime, to end: CMTime) -> CMSampleBuffer? {
        guard let format = sample.formatDescription,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM
        else { return nil }
        let count = CMItemCount(((end - start).seconds * description.mSampleRate).rounded())
        let planes = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(description.mChannelsPerFrame) : 1
        let length = count * Int(description.mBytesPerFrame) * planes
        guard count > 0, length > 0 else { return nil }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block,
        ) == noErr, let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr
        else { return nil }
        var silence: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: start, packetDescriptions: nil, sampleBufferOut: &silence,
        )
        return silence
    }
}
