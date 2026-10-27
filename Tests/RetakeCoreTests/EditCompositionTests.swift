import AVFoundation
import Foundation
@testable import RetakeCore
import Testing

/// The editor's timing and framing, and the composition AVFoundation plays from them.
struct CutPlanTests {
    /// The `TakeTimelineTests` take, 6 s long: `a` at 1–1.5 s, `b` at 2–3 s, a hold at 4–4.5 s.
    let timelines = ["walk": TakeTimelineTests.timeline()]

    func video(_ clips: String) throws -> Edit {
        let reader = JSONReader(file: "edits/video.json")
        let edit = EditFile.read(#"{"devices": ["ipad"], "clips": [\#(clips)]}"#, with: reader)
        #expect(reader.problems.isEmpty, "\(reader.problems)")
        return try #require(edit?.videos[.ipad])
    }

    @Test func clipsPlayInTurnAtTheirSpeedsOverlappingByTheirCrossfades() throws {
        let plan = try CutPlan.make(video(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}, "speed": 2},
            {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.5},
            {"take": "walk", "from": 0.5, "to": 1.5, "speed": 0.5, "crossfade": 0.25}
            """#), timelines: timelines)
        #expect(plan.placements.map(\.from) == [1, 2, 0.5])
        #expect(plan.placements.map(\.to) == [2, 6, 1.5])
        #expect(plan.placements.map(\.start) == [0, 0, 3.75], "the second starts its cross-fade before the first ends")
        #expect(plan.placements.map(\.duration) == [0.5, 4, 2])
        #expect(plan.duration == 5.75)
        #expect(plan.placements[0].videoTime(1.5) == 0.25, "half way through the first clip, played at twice its speed")
    }

    @Test(arguments: [
        (#"{"take": "walk", "from": {"step": "b"}, "to": {"step": "a"}}"#, "clips[0] plays 2 s to 1 s of a take 6 s long; it must run forward, inside it."),
        (#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end", "offset": 1}}"#, "clips[0] plays 1 s to 7 s of a take 6 s long; it must run forward, inside it."),
        (#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}, {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 2}"#, "clips[1]'s cross-fade, 2 s, is longer than it or the clip before plays."),
        (#"{"take": "other", "from": {"step": "a"}, "to": {"step": "b"}}"#, "clips[0]: there's no take of other to cut it from."),
    ])
    func aPlanThatCantBeCutSaysWhichClip(_ clips: String, _ message: String) throws {
        let edit = try video(clips)
        do {
            _ = try CutPlan.make(edit, timelines: timelines)
            Issue.record("cut a plan that can't be cut")
        } catch {
            #expect(error.status == .failed && error.message == message)
        }
    }

    @Test func aWindowShapedByAspectIsCroppedFromTheTopAndScaledToTheCanvas() {
        // An iPad's capture, its app laid out at 3:4 at the top: exactly the iPad preview's shape.
        let ipad = ClipFraming.filling(PreviewSpec.of(.ipad).size, capture: CGSize(width: 1200, height: 1718), aspect: .init(width: 3, height: 4))
        #expect(ipad.cropRect == CGRect(x: 0, y: 0, width: 1200, height: 1600))
        #expect(ipad.canvasFrame == CGRect(x: 0, y: 0, width: 1200, height: 1600))
        // An iPhone's full screen, a hair narrower than the preview: scaled to its height, and
        // a sliver cropped from each side.
        let iphone = ClipFraming.filling(PreviewSpec.of(.iphone).size, capture: CGSize(width: 1170, height: 2532), aspect: nil)
        #expect(abs(iphone.cropRect.height - 2532) < 0.001 && iphone.cropRect.width < 1170)
        #expect(abs(iphone.cropRect.midX - 585) < 0.001)
        #expect(abs(iphone.canvasFrame.width - 886) < 0.001 && abs(iphone.canvasFrame.height - 1920) < 0.001)
    }
}

/// The composition, from small generated movies: two takes, one red on top and one green, so which
/// clip shows is a matter of colour.
struct EditCompositionTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "retake-composition-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// A one-colour movie, 2 s at 30 frames a second, 60×80.
    func movie(_ name: String, red: UInt8, green: UInt8, blue: UInt8) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).mov")
        let writer = TakeWriter(writingTo: url, live: false)
        for index in 0..<60 { writer.appendVideo(try Self.frame(red: red, green: green, blue: blue, at: index)) }
        _ = try await writer.finish()
        return url
    }

    static func frame(red: UInt8, green: UInt8, blue: UInt8, at index: Int) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(nil, 60, 80, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pixels)
        let buffer = try #require(pixels)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: CVPixelBufferGetBytesPerRow(buffer) * 80, by: 4) {
            (base[offset], base[offset + 1], base[offset + 2], base[offset + 3]) = (blue, green, red, 255)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample)
        return try #require(sample)
    }

    /// The middle pixel of the composition's frame at `seconds`, as red, green and blue.
    func colour(of composition: EditComposition, at seconds: Double) async throws -> (Int, Int, Int) {
        let generator = AVAssetImageGenerator(asset: composition.composition)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test func clipsPlayInTurnCrossfadingOnTheCanvas() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let movies = ["red": try await movie("red", red: 255, green: 0, blue: 0), "green": try await movie("green", red: 0, green: 255, blue: 0)]
        let plan = CutPlan(placements: [
            .init(take: "red", from: 0, to: 1, speed: 1, start: 0, duration: 1, crossfade: 0),
            .init(take: "green", from: 0.5, to: 1.5, speed: 2, start: 0.75, duration: 0.5, crossfade: 0.25),
        ])
        let composition = try await EditComposition.make(plan, movies: movies, spec: PreviewSpec(width: 60, height: 80, framesPerSecond: 30), background: .black)
        #expect(abs(composition.composition.duration.seconds - 1.25) < 0.01)
        let ranges = composition.videoComposition.instructions.map { ($0.timeRange.start.seconds, $0.timeRange.end.seconds) }
        #expect(ranges.map(\.0) == [0, 0.75, 1] && ranges.map(\.1) == [0.75, 1, 1.25])

        // Through the encoder and back, pure red and green come out a little mixed, so each is told
        // by which channel leads.
        let red = try await colour(of: composition, at: 0.3)
        #expect(red.0 > red.1 + 150, "the first clip, alone")
        let green = try await colour(of: composition, at: 1.15)
        #expect(green.1 > green.0 + 150, "the second, alone")
        let between = try await colour(of: composition, at: 0.875)
        #expect(between.0 > green.0 + 40 && between.1 > red.1 + 40, "half way through the cross-fade, some of each")
    }
}
