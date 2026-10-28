import AVFoundation
import Foundation
@testable import RetakeCore
import Testing

/// What `info` reads back out of a movie: the fields `record` and `cut` wrote.
struct MovieInfoTests {
    func fields(_ items: [AVMetadataItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.key as! String, $0.value as! String) })
    }

    func video(builds: [String]) -> MovieMetadata.Video {
        let takes = builds.enumerated().map { index, build in
            var log = TakeLogReadingTests.log(scene: "scene\(index + 1)", take: index + 1)
            log.app.build = build
            return log
        }
        return MovieMetadata.Video(edit: "video1", type: .ipad, bundleID: "com.example.notes", takes: takes)
    }

    @Test func aTakesFieldsReadBackAsItsStepLogNamesThem() throws {
        let info = try #require(MovieInfo.info(fields: fields(MovieMetadata.take(TakeLogReadingTests.log())), description: nil))
        #expect(info.isTake)
        #expect(info.json[path: "scene"] == .string("create-note") && info.json[path: "take"] == .number(3))
        #expect(info.json[path: "device", "marketingName"] == .string("iPad Pro (11-inch) (3rd generation)"))
        #expect(info.json[path: "bundleID"] == .string("com.example.notes"))
        #expect(info.lines == [
            "Take 3 of create-note, for ipad",
            "  Recorded     2027-01-15T08:00:00Z",
            "  Set          returning-user (cloned)",
            "  App          com.example.notes 1.0 (7)",
            "  Device       iPad Pro (11-inch) (3rd generation) (iPad13,4), iOS 26.6.2 (23G90)",
            "  Button Heist 0.7.1",
            "  Retake       0.0.1",
        ])
    }

    @Test func aMastersFieldsReadBackAsTheMP4sDescriptionHoldsThem() throws {
        let video = video(builds: ["7"])
        let master = try #require(MovieInfo.info(fields: fields(MovieMetadata.video(video)), description: nil))
        let preview = try #require(MovieInfo.info(fields: [:], description: JSONWriter.compact(video.json)))
        #expect(master == .video(video.json) && preview == master)
        #expect(master.mixed.isEmpty && master.lines.contains("  Takes        scene1@1"))
    }

    @Test func aVideoWhoseTakesSpanBuildsSaysWhichTakeIsOnWhich() throws {
        let info = MovieInfo.video(video(builds: ["7", "8"]).json)
        #expect(info.mixed == ["builds of the app"])
        #expect(info.lines.contains("  Takes        scene1@1: 1.0 (7), iPad13,4, iOS 26.6.2 (23G90), The Button Heist 0.7.1"))
        #expect(info.lines.last == "  Its takes span more than one of: builds of the app.")
    }

    @Test func aMovieRetakeDidntWriteIsntRead() async throws {
        #expect(MovieInfo.info(fields: ["com.apple.quicktime.software": "Final Cut"], description: "{\"edit\": 1}") == nil)
        let folder = FileManager.default.temporaryDirectory.appending(path: "RetakeMovieInfoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let notAMovie = folder.appending(path: "a.mov")
        try Data("not a movie".utf8).write(to: notAMovie)
        await #expect(throws: RetakeError.self) { try await MovieInfo.read(notAMovie) }
        await #expect(throws: RetakeError.self) { try await MovieInfo.read(folder.appending(path: "missing.mp4")) }
    }
}
