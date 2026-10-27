import AVFoundation
import Foundation
import RetakeCore
import Testing

extension OnDevice {
    @Suite struct RecordingTests {
        /// Records the example while the device turns left, back, right and back: one movie of the
        /// first frame's shape, every change of shape noted with its turn, and next to nothing lost.
        /// The movie is kept in the example's `RetakeOutput/tests/` to look at.
        @Test func aRecordingKeepsGoingThroughTurns() async throws {
            let example = try ExampleOnDevice()
            let capture = try #require(ScreenCaptureDevices().captureDevices(waitingFor: example.device.name, timeout: 10).first { $0.name == example.device.name })
            let recorder = try DeviceRecorder(capture)
            let movie = example.project.output.appending(path: "tests/turns.mov")
            try FileManager.default.createDirectory(at: movie.deletingLastPathComponent(), withIntermediateDirectories: true)

            let set = try Inspection.set("returning-user", in: example.project)
            nonisolated(unsafe) var summary: TakeWriter.Summary?
            try await AppSession.run("record-test", in: example.project, set: set, scene: SceneFile(steps: []), on: example.device, report: { _ in }) { _ throws(RetakeError) in
                try await recorder.start(writingTo: movie)
                try? await Task.sleep(for: .seconds(1.5))
                for orientation in [SceneFile.Orientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
                    recorder.turning(to: TakeWriter.Facing(orientation))
                    try Launcher.turn(example.device, to: orientation)
                    try? await Task.sleep(for: .seconds(2.5))
                }
                summary = try await recorder.stop()
            }
            let result = try #require(summary)
            #expect(result.height > result.width, "the file keeps the first frame's portrait shape")
            #expect(result.shapes.map(\.turn) == [0, 90, 0, -90, 0])
            #expect(result.shapes.dropFirst().allSatisfy { $0.at > 1 })
            #expect(Double(result.frames) / result.duration > 50, "about the device's 60 frames a second")
            #expect(result.dropped < 5)

            let asset = AVURLAsset(url: movie)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(Int(size.width) == result.width && Int(size.height) == result.height)
            #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        }
    }
}
