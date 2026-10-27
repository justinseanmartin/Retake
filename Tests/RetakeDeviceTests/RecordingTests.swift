import AVFoundation
import Foundation
import RetakeCore
import Testing

extension OnDevice {
    @Suite struct RecordingTests {
        /// A take of `create-note`: its movie with the take's metadata, and a step log with every
        /// step, in order, on the movie's clock from the device's own times, with what was on
        /// screen after each. Kept in the example's `RetakeOutput/tests/` to look at.
        @Test(arguments: ["create-note", "first-launch"])
        func aTakeHasItsStepLogAndMetadata(_ name: String) async throws {
            let example = try ExampleOnDevice()
            let capture = try #require(ScreenCaptureDevices().captureDevices(waitingFor: example.device.name, timeout: 10).first { $0.name == example.device.name })
            let (scene, set) = try AppSession.scene(name, in: example.project, for: example.device.type!)
            let target = TakeRecording.Target(scene: name, take: 1, movie: example.project.output.appending(path: "tests/\(name).mov"))
            let log = try await TakeRecording.record(target, scene: scene, set: set, in: example.project, on: example.device, capture: capture, player: Player())

            #expect(log.failure == nil)
            #expect(log.steps.map(\.number) == Array(1...scene.steps.count))
            #expect(log.steps.allSatisfy { $0.timedByDevice && $0.start <= $0.end })
            #expect(zip(log.steps, log.steps.dropFirst()).allSatisfy { $0.end <= $1.start }, "in order, none overlapping")
            #expect(log.steps.first.map { $0.start >= scene.leadIn } ?? false)
            #expect(log.steps.last.map { log.duration >= $0.end + scene.tail - 0.1 } ?? false)
            #expect(log.steps.allSatisfy { $0.elements?.isEmpty == false })
            #expect((log.launch != nil) == scene.recordsLaunch)
            if let launch = log.launch {
                #expect(0 < launch.launched && launch.launched < launch.reported && launch.reported <= launch.connected)
                #expect(launch.connected < log.steps[0].start)
            }
            let written = try JSONParser.parse(String(contentsOf: target.log, encoding: .utf8))
            #expect(written == log.json)
            let metadata = try await MovieMetadata.read(target.movie)
            #expect(metadata["retake.scene"] == name && metadata["retake.take"] == "1" && metadata["retake.state"] == "clean")
            #expect(metadata["retake.app.version"] != nil && metadata["retake.device.model"] == example.device.model)
            #expect(!metadata.values.contains { $0.contains(example.device.name) || $0.contains(example.device.udid) }, "nothing personal")
        }

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
            try await AppSession.run("record-test", in: example.project, set: set, scene: SceneFile(steps: []), on: example.device, report: { _ in }) { _, _ throws(RetakeError) in
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
