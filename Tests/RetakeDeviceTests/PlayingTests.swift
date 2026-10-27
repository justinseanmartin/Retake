import Foundation
import RetakeCore
import Testing

extension OnDevice {
    @Suite struct PlayingTests {
        /// Every kind of step the example's scenes take, through one session each: taps by label,
        /// typing, waits, a timed drag, and turns.
        @Test(arguments: ["create-note", "reorder"])
        func aSceneRehearsesToItsLastStep(_ scene: String) async throws {
            let example = try ExampleOnDevice()
            // `reorder` is only for the iPad so far; its points are the iPad's.
            guard FileManager.default.fileExists(atPath: ProjectFiles(project: example.project).sceneURL(scene, for: example.device.type!).path) else { return }
            let played = Played()
            let player = Player(report: { if case .finished(let step, _) = $0 { played.add(step.number) } })
            try await Rehearsal.run(scene, in: example.project, on: example.device, from: 1, player: player)
            let steps = try #require(ProjectFiles(project: example.project).readScene(scene, for: example.device.type!, into: ProjectFiles.Report())).steps
            #expect(played.numbers == Array(1...steps.count))
        }

        @Test func aStepThatDoesntRunFailsNamingIt() async throws {
            let example = try ExampleOnDevice()
            let scenes = example.project.scenes(for: example.device.type!)
            let url = scenes.appending(path: "rehearse-failure-\(UUID().uuidString.prefix(6)).json")
            try #"{ "set": "returning-user", "steps": [{ "tap": { "label": "No such button" } }] }"#.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let name = url.deletingPathExtension().lastPathComponent
            await #expect {
                try await Rehearsal.run(name, in: example.project, on: example.device, from: 1, player: Player())
            } throws: { error in
                let error = error as? RetakeError
                return error?.status == .failed && error?.message.hasPrefix("\(name): step 1 of 1, tap \"No such button\", didn't run:") == true
            }
        }
    }
}

extension OnDevice {
    @Suite struct InspectingTests {
        @Test func inspectShowsTheSetsScreen() async throws {
            let example = try ExampleOnDevice()
            let screens = Screens()
            let inspection = Inspection(show: { screens.add($0) })
            let set = try Inspection.set("returning-user", in: example.project)
            try await Inspection.run(set, in: example.project, on: example.device, watch: false, inspection: inspection, report: { _ in })
            let labels = try #require(screens.all.first).compactMap(\.label)
            #expect(screens.all.count == 1)
            #expect(labels.contains("Weekend plans") && labels.contains("Book club") && labels.contains("New Note"), "the set's notes, not the real ones")
        }
    }
}

/// The screens an inspection showed.
final class Screens: @unchecked Sendable {
    private let lock = NSLock()
    private var screens: [[ScreenElement]] = []

    func add(_ screen: [ScreenElement]) { lock.withLock { screens.append(screen) } }
    var all: [[ScreenElement]] { lock.withLock { screens } }
}

/// The steps a rehearsal reported finished, in order.
final class Played: @unchecked Sendable {
    private let lock = NSLock()
    private var played: [Int] = []

    func add(_ number: Int) { lock.withLock { played.append(number) } }
    var numbers: [Int] { lock.withLock { played } }
}
