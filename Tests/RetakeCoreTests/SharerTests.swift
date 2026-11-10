import AVFoundation
import Foundation
@testable import RetakeCore
import Testing

struct ShareRequestTests {
    @Test func clipsAreTypedByTypeOrEachTheirOwnNeverBoth() throws {
        let joined = try ShareRequest.parse("showcase/iphone+showcase/ipad", type: nil)
        #expect(joined.clips == [.init(name: "showcase", type: .iphone), .init(name: "showcase", type: .ipad)])
        #expect(joined.fileName == "showcase-iphone+showcase-ipad")
        #expect(try ShareRequest.parse("showcase+create-note", type: .ipad).clips == [.init(name: "showcase", type: .ipad), .init(name: "create-note", type: .ipad)])

        func misuse(_ text: String, _ type: DeviceType? = nil) -> String? {
            do {
                _ = try ShareRequest.parse(text, type: type)
                return nil
            } catch {
                return error.status == .usage ? error.message : "not misuse: \(error.message)"
            }
        }
        #expect(misuse("showcase/iphone+tour", .ipad)?.hasPrefix(#""showcase/iphone" names its device type, and so does --type"#) == true)
        #expect(misuse("showcase/iphone+tour") == #""tour" names no device type; give --type, or each clip's own, as tour/iphone."#)
        #expect(misuse("showcase/ipod") == #""showcase/ipod": "ipod" isn't a device type; it's iphone or ipad."#)
        #expect(misuse("showcase/ipad++tour/ipad")?.hasPrefix(#""showcase/ipad++tour/ipad" has an empty clip"#) == true)
        #expect(misuse("/ipad")?.hasPrefix(#""/ipad" isn't a clip"#) == true)
        #expect(misuse("a+b+c+d+e", .ipad) == #""a+b+c+d+e" joins 5 clips; a share puts at most 4 side by side."#)
    }
}

struct ShareLayoutTests {
    let iphone = CGSize(width: 886, height: 1920), ipad = CGSize(width: 1200, height: 1600)

    @Test func oneClipAloneIs720Wide() {
        let layout = ShareLayout.of([iphone])
        #expect(layout.canvas == CGSize(width: 720, height: 1560))
        #expect(layout.frames == [CGRect(x: 0, y: 0, width: 720, height: 1560)])
    }

    @Test func clipsJoinedAre960TallInGuttersInTheirOrder() {
        let layout = ShareLayout.of([iphone, ipad])
        #expect(layout.canvas == CGSize(width: 1236, height: 1008), "443 + 720 and three 24 px gutters, made even")
        #expect(layout.frames == [CGRect(x: 24, y: 24, width: 443, height: 960), CGRect(x: 491, y: 24, width: 720, height: 960)])
    }

    @Test func clipsTooWideTogetherShrinkToFit1920() {
        let layout = ShareLayout.of(Array(repeating: ipad, count: 4))
        #expect(layout.canvas.width == 1920)
        let last = layout.frames[3]
        #expect(abs(last.maxX + last.minY - 1920) < 0.001, "the last gutter as wide as the top one")
        #expect(abs(last.width / last.height - 0.75) < 0.001)
    }
}

struct SharerTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeSharerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = Project(configuration: root.appending(path: "retake.json"))
        try write("retake.json", "{}")
        try write("scenes/ipad/walk.json", #"{"steps": [{"hold": 1}]}"#)
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": []}"#)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func failure(_ name: String) async -> String? {
        do {
            _ = try await Sharer.source(.init(name: name, type: .ipad), in: project)
            return nil
        } catch {
            return "\(error.status.rawValue): \(error.message)"
        }
    }

    @Test func aNameIsAnEditsCutOrAScenesTakeAndMustBeThere() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await failure("video") == "1: video/ipad: there's no ipad cut of video to share (output/cuts/ipad/video/video-ipad-master.mov); cut it with `retake cut video --type ipad`.")
        #expect(await failure("walk") == "1: walk/ipad: there's no successful ipad take of walk to share; record it.")
        #expect(await failure("nothing") == #"2: nothing/ipad: there's no edit or scene "nothing"."#)
        try write("scenes/iphone/video.json", #"{"steps": [{"hold": 1}]}"#)
        #expect(await failure("video") == #"1: video/ipad: a scene is named "video" too, so `retake share video` can't tell a cut from a take; rename one of them."#)
    }

    @Test func clipsSideBySidePlayForTheLongestOnTheBackground() async throws {
        let movies = EditCompositionTests()
        defer { try? FileManager.default.removeItem(at: movies.folder) }
        let red = try await movies.movie("red", red: 255, green: 0, blue: 0, frames: 12)
        let blue = try await movies.movie("blue", red: 0, green: 0, blue: 255, frames: 6)
        func source(_ name: String, _ movie: URL, _ duration: Double) -> Sharer.Source {
            Sharer.Source(clip: .init(name: name, type: .ipad), movie: movie, isTake: true, duration: duration, hasSound: false)
        }
        let sources = [source("red", red, 0.4), source("blue", blue, 0.2)]

        let url = movies.folder.appending(path: "share.mp4")
        let shared = try await Sharer.share(sources, audio: 1, background: Color(hex: "#3A3A3C")!, to: url)
        #expect(shared.size == CGSize(width: 1352, height: 1008), "two 640×960 clips and their gutters")
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 0.4) < 0.05, "as long as the longest")
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty, "the clip it takes its sound from has none")

        // After the blue clip has ended, it holds its last frame beside the red one still playing.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: 0.35, preferredTimescale: 600)).image
        func pixel(_ x: Int, _ y: Int) throws -> (Int, Int, Int) {
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            // The image's top-left pixel (x, y) lands on the context's one pixel.
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        }
        // H.264's color conversion moves pure red to about (232, 36, 2).
        func near(_ found: (Int, Int, Int), _ wanted: (Int, Int, Int)) -> Bool {
            abs(found.0 - wanted.0) < 48 && abs(found.1 - wanted.1) < 48 && abs(found.2 - wanted.2) < 48
        }
        #expect(near(try pixel(344, 504), (255, 0, 0)), "red, on the left")
        #expect(near(try pixel(1008, 504), (0, 0, 255)), "blue, held, on the right")
        #expect(near(try pixel(10, 10), (0x3A, 0x3A, 0x3C)), "the background in the gutter")
        #expect(try await MovieInfo.read(url).lines.first == "Share of red/ipad + blue/ipad", "info reads its record")
    }

    @Test func aSharesRecordNamesEachClipAndWhatItsFrom() throws {
        let take = MovieInfo.take(.object(JSONObject([.init(key: "scene", value: .string("walk")), .init(key: "recordedAt", value: .string("2026-11-09T21:01:40Z"))])))
        let items = MovieMetadata.share([("walk/ipad", take), ("other/ipad", nil)], retake: "0.0.1")
        let description = items.first { $0.commonKey == .commonKeyDescription }?.value as? String
        let info = try #require(MovieInfo.info(fields: [:], description: description))
        #expect(info.json(movie: "a.mp4")[path: "share"] != nil, "info --json names it a share")
        #expect(info.lines == [
            "Share of walk/ipad + other/ipad",
            "  Clips        walk/ipad: take of walk, recorded 2026-11-09T21:01:40Z on ?, iOS ?",
            "               other/ipad: from a movie with no record",
            "  Retake       0.0.1",
        ])
    }
}
