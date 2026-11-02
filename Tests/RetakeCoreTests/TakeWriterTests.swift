import AVFoundation
import CoreImage
import Foundation
@testable import RetakeCore
import Testing

/// Small generated frames, at 30 a second, through the writer and back out of the movie.
struct TakeWriterTests {
    let movie = FileManager.default.temporaryDirectory.appending(path: "retake-writer-\(UUID().uuidString).mov")

    /// A frame whose top half is red and bottom half blue, so which way it was turned shows.
    func frame(width: Int, height: Int, at index: Int) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pixels)
        let buffer = try #require(pixels)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * row + x * 4
                let top = y < height / 2
                (pixel[0], pixel[1], pixel[2], pixel[3]) = top ? (0, 0, 255, 255) : (255, 0, 0, 255)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: CMTimeValue(100 + index), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample)
        return try #require(sample)
    }

    /// Whether a frame of the movie, at `seconds`, is red on its right half and blue on its left.
    func redOnTheRight(at seconds: Double) async throws -> Bool {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func red(x: Int) -> Bool { let pixel = data + (image.height / 2) * context.bytesPerRow + x * 4; return pixel[0] > 128 && pixel[2] < 128 }
        return red(x: image.width * 3 / 4) && !red(x: image.width / 4)
    }

    @Test func framesOfTheOtherShapeAreTurnedTheWayTheDeviceFacesUntilItHasTurnedBack() async throws {
        defer { try? FileManager.default.removeItem(at: movie) }
        let writer = TakeWriter(writingTo: movie, live: false)
        var index = 0
        func append(_ count: Int, width: Int, height: Int) throws {
            for _ in 0..<count {
                writer.appendVideo(try frame(width: width, height: height, at: index))
                index += 1
            }
        }
        try append(6, width: 64, height: 96)
        writer.facing = .landscapeRight
        try append(6, width: 96, height: 64)
        // Told before the turn back, so the frames still landscape mustn't change which way they turn.
        writer.facing = .portrait
        try append(3, width: 96, height: 64)
        try append(6, width: 64, height: 96)
        writer.facing = .landscapeLeft
        try append(6, width: 96, height: 64)
        let summary = try await writer.finish()

        #expect(summary.width == 64 && summary.height == 96)
        #expect(summary.frames == 27 && summary.dropped == 0)
        #expect(summary.shapes.map(\.turn) == [0, -90, 0, 90])
        #expect(summary.shapes.map(\.at) == [0, 0.2, 0.5, 0.7])
        #expect(try await !redOnTheRight(at: 0.1), "upright as it came")
        #expect(try await !redOnTheRight(at: 0.4), "turned right, the app's top to the file's left")
        #expect(try await redOnTheRight(at: 0.8), "turned left, the app's top to the file's right")
    }

    @Test func aSampleNoLaterThanTheLastIsSkippedNotWritten() async throws {
        defer { try? FileManager.default.removeItem(at: movie) }
        let writer = TakeWriter(writingTo: movie, live: false)
        writer.appendVideo(try frame(width: 64, height: 96, at: 0))
        writer.appendVideo(try frame(width: 64, height: 96, at: 2))
        writer.appendVideo(try frame(width: 64, height: 96, at: 1))
        let summary = try await writer.finish()
        #expect(summary.frames == 2 && summary.outOfOrder == 1)
    }

    @Test func aStillScreensFrameIsWrittenAgainUntilTheNextComes() async throws {
        defer { try? FileManager.default.removeItem(at: movie) }
        let writer = TakeWriter(writingTo: movie, live: false)
        writer.appendVideo(try frame(width: 64, height: 96, at: 0))
        writer.appendVideo(try frame(width: 64, height: 96, at: 15))
        let summary = try await writer.finish()
        #expect(summary.frames == 2, "the device's own frames")
        let asset = AVURLAsset(url: movie)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var times: Set<Double> = []
        // Read in decode order, with markers that have no time of their own among them.
        while let sample = output.copyNextSampleBuffer() {
            if sample.presentationTimeStamp.isNumeric { times.insert(sample.presentationTimeStamp.seconds) }
        }
        let shown = times.sorted()
        let gaps = zip(shown, shown.dropFirst()).map { $1 - $0 }
        #expect((shown.last ?? 0) >= 0.5 && (gaps.max() ?? 1) < 0.02, "the half second between them, a frame each sixtieth")
    }

    @Test func theMovieSaysHowItWasMade() async throws {
        defer { try? FileManager.default.removeItem(at: movie) }
        let log = TakeLog(
            scene: "create-note", take: 3, set: "returning-user", state: .cloned, deviceType: .ipad,
            device: .init(model: "iPad13,4", marketingName: "iPad Pro (11-inch) (3rd generation)", os: "26.6.2 (23G90)"),
            app: .init(bundleID: "com.example.notes", version: "1.9.0", build: "412"),
            retake: "0.0.1", buttonHeist: .init(version: "0.7.1-d53fb59edbf3", commit: "5d05a318-dirty"),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000), failure: nil, duration: 0, width: 0, height: 0, launch: nil,
            clock: .init(deviceAhead: nil), steps: [], shapes: [],
        )
        let writer = TakeWriter(writingTo: movie, metadata: MovieMetadata.take(log), live: false)
        for index in 0..<3 { writer.appendVideo(try frame(width: 64, height: 96, at: index)) }
        _ = try await writer.finish()
        let fields = try await MovieMetadata.read(movie)
        #expect(fields == [
            "com.apple.quicktime.software": "Retake 0.0.1",
            "com.apple.quicktime.make": "Apple",
            "com.apple.quicktime.model": "iPad Pro (11-inch) (3rd generation)",
            "com.apple.quicktime.creationdate": "2027-01-15T08:00:00Z",
            "retake.version": "0.0.1",
            "retake.scene": "create-note",
            "retake.take": "3",
            "retake.set": "returning-user",
            "retake.state": "cloned",
            "retake.app.bundle-id": "com.example.notes",
            "retake.app.version": "1.9.0",
            "retake.app.build": "412",
            "retake.buttonheist.version": "0.7.1-d53fb59edbf3",
            "retake.buttonheist.commit": "5d05a318-dirty",
            "retake.device.model": "iPad13,4",
            "retake.device.type": "ipad",
            "retake.device.os": "26.6.2 (23G90)",
        ])
    }

    @Test func aTakeThatStartedTurnedTurnsItsUprightFramesBack() {
        #expect(TakeWriter.turn(for: .portrait, startedFacing: .landscapeLeft) == -90)
        #expect(TakeWriter.turn(for: .portrait, startedFacing: .landscapeRight) == 90)
    }
}
