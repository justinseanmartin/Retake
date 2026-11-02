import AVFoundation
import Foundation
@testable import RetakeCore
import Testing

struct PreviewExportTests {
    @Test func aTurnsBlurSwellsAndAnEditsHoldsSteady() {
        var overlays = Overlays()
        overlays.blurs = [.init(rect: CGRect(x: 0, y: 0, width: 10, height: 10), radius: 20, start: 1, end: 2)]
        let blurs = PreviewExport.blurs(turns: [3...3.5], overlays: overlays, canvas: CGSize(width: 64, height: 96))
        #expect(blurs.map(\.rect) == [CGRect(x: 0, y: 0, width: 64, height: 96), CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(blurs[0].sigma(at: 3) == 0 && abs(blurs[0].sigma(at: 3.25) - PreviewExport.turnBlurSigma) < 1e-9, "none at its edges, all at its middle")
        #expect(blurs[1].sigma(at: 1.1) == 20 && blurs[1].sigma(at: 1.9) == 20)
    }

    @Test func aVideosRecordListsEachDistinctBuildAndDeviceInTheOrderItsClipsPlay() {
        var first = TakeLogReadingTests.log(scene: "a", take: 1)
        first.app.build = "412"
        var second = TakeLogReadingTests.log(scene: "b", take: 2)
        second.app.build = "415"
        var third = TakeLogReadingTests.log(scene: "c", take: 3)
        third.app.build = "412"
        let video = MovieMetadata.Video(edit: "video1", type: .ipad, bundleID: "com.example.notes", takes: [first, second, third])
        #expect(video.appVersions == [
            .object(JSONObject([.init(key: "version", value: .string("1.0")), .init(key: "build", value: .string("412"))])),
            .object(JSONObject([.init(key: "version", value: .string("1.0")), .init(key: "build", value: .string("415"))])),
        ])
        #expect(video.devices.count == 1 && video.takeRecords.count == 3)
        #expect(video.mixed == ["builds of the app"])
        #expect(video.json[path: "edit"] == .string("video1") && video.json[path: "deviceType"] == .string("ipad"))
    }

    @Test func aCompositionRendersToAMasterAndAPreviewCarryingItsRecord() async throws {
        let tests = EditCompositionTests()
        defer { try? FileManager.default.removeItem(at: tests.folder) }
        let red = try await tests.movie("red", red: 255, green: 0, blue: 0)
        let spec = PreviewSpec(width: 64, height: 96, framesPerSecond: 30)
        let plan = CutPlan(placements: [.init(take: "red", from: 0, to: 1, speed: 1, start: 0, duration: 1, crossfade: 0)])
        let composition = try await EditComposition.make(plan, movies: ["red": red], spec: spec, background: .black)
        var overlays = Overlays()
        overlays.captions = [.init(text: "Hi", color: .black, y: 0.5, symbol: nil, start: 0, end: 1)]
        let record = MovieMetadata.Video(edit: "video1", type: .ipad, bundleID: "com.example.notes", takes: [TakeLogReadingTests.log()])

        let master = tests.folder.appending(path: "video1-ipad-master.mov")
        let preview = tests.folder.appending(path: "video1-ipad.mp4")
        try await PreviewExport.master(composition, audioMix: nil, layers: OverlayLayers(overlays, spec: spec), metadata: MovieMetadata.video(record), to: master)
        try await PreviewExport.preview(from: master, to: preview, spec: spec, blurs: [], metadata: MovieMetadata.preview(record))

        #expect(try await MovieMetadata.read(master)["retake.edit"] == "video1")
        let asset = AVURLAsset(url: preview)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 64, height: 96))
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.05)
        let items: [AVMetadataItem] = try await asset.load(.metadata)
        let description = items.first { item in item.commonKey == .commonKeyDescription }
        let text = try #require(try await description?.load(.stringValue))
        #expect(try JSONParser.parse(text)[path: "edit"] == .string("video1"))
        #expect(try await MovieInfo.read(preview) == MovieInfo.read(master), "info reads the same record from either")
    }

    /// How much brightness changes from each pixel of a frame of `movie` to the next across: high
    /// where a caption's edges are sharp.
    func contrast(of movie: URL, at seconds: Double) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixels = [UInt8](repeating: 0, count: 64 * 96 * 4)
        let context = try #require(CGContext(
            data: &pixels, width: 64, height: 96, bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 96))
        let brightness = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) }
        return brightness.indices.filter { $0 % 64 != 63 }.reduce(0) { $0 + abs(brightness[$1] - brightness[$1 + 1]) }
    }

    @Test func theMasterHidesWhatItsBlursCoverAsThePreviewDoes() async throws {
        let tests = EditCompositionTests()
        defer { try? FileManager.default.removeItem(at: tests.folder) }
        let red = try await tests.movie("red", red: 255, green: 0, blue: 0)
        let spec = PreviewSpec(width: 64, height: 96, framesPerSecond: 30)
        let plan = CutPlan(placements: [.init(take: "red", from: 0, to: 1, speed: 1, start: 0, duration: 1, crossfade: 0)])
        let composition = try await EditComposition.make(plan, movies: ["red": red], spec: spec, background: .black)
        var overlays = Overlays()
        overlays.captions = [.init(text: "Hi", color: .black, y: 0.5, symbol: nil, start: 0, end: 1)]
        let blurs = [PreviewExport.BlurRegion(start: 0, end: 0.5, rect: CGRect(x: 0, y: 0, width: 64, height: 96), sigma: 12)]
        let record = MovieMetadata.Video(edit: "video1", type: .ipad, bundleID: "com.example.notes", takes: [TakeLogReadingTests.log()])

        let master = tests.folder.appending(path: "video1-ipad-master.mov")
        try await PreviewExport.master(composition, audioMix: nil, layers: OverlayLayers(overlays, spec: spec), blurs: blurs, metadata: MovieMetadata.video(record), to: master)

        let blurred = try await contrast(of: master, at: 0.25), sharp = try await contrast(of: master, at: 0.75)
        #expect(blurred * 2 < sharp, "the caption blurred while the blur lasts (\(blurred)), and sharp after it (\(sharp))")
        let track = try #require(try await AVURLAsset(url: master).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AppleProRes422)
        #expect(try await MovieMetadata.read(master)["retake.edit"] == "video1")
        #expect(try FileManager.default.contentsOfDirectory(atPath: tests.folder.path).sorted() == ["red.mov", "video1-ipad-master.mov"], "no unblurred copy left")
    }
}
