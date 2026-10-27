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

    @Test func aTakeThatStartedTurnedTurnsItsUprightFramesBack() {
        #expect(TakeWriter.turn(for: .portrait, startedFacing: .landscapeLeft) == -90)
        #expect(TakeWriter.turn(for: .portrait, startedFacing: .landscapeRight) == 90)
    }
}
