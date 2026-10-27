import Foundation
import RetakeCore
import Testing

extension OnDevice {
    @Suite struct PlayingTests {
        /// Every kind of step the example's scenes take, played by `record --dry-run`, one session
        /// each: taps by label, typing, waits, a timed drag, and turns.
        @Test(arguments: ["create-note", "reorder"])
        func aDryRunPlaysEveryStep(_ scene: String) async throws {
            let example = try ExampleOnDevice()
            // `reorder` is only for the iPad so far; its points are the iPad's.
            guard FileManager.default.fileExists(atPath: ProjectFiles(project: example.project).sceneURL(scene, for: example.device.type!).path) else { return }
            let played = Played()
            let player = Player(report: { if case .finished(let step, _) = $0 { played.add(step.number) } })
            let outcomes = await RecordRun.run([scene], in: example.project, on: example.device, capture: nil, dryRun: true, stopOnFailure: false, player: player)
            #expect(outcomes.count == 1 && outcomes[0].failure == nil && outcomes[0].take == nil)
            let steps = try #require(ProjectFiles(project: example.project).readScene(scene, for: example.device.type!, into: ProjectFiles.Report())).steps
            #expect(played.numbers == Array(1...steps.count))
        }

        @Test func aStepThatDoesntRunFailsNamingIt() async throws {
            let example = try ExampleOnDevice()
            let scenes = example.project.scenes(for: example.device.type!)
            let url = scenes.appending(path: "dry-run-failure-\(UUID().uuidString.prefix(6)).json")
            try #"{ "set": "returning-user", "steps": [{ "tap": { "label": "No such button" } }] }"#.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let name = url.deletingPathExtension().lastPathComponent
            let outcomes = await RecordRun.run([name], in: example.project, on: example.device, capture: nil, dryRun: true, stopOnFailure: false, player: Player())
            let failure = try #require(outcomes.first?.failure)
            #expect(failure.status == .failed && failure.message.hasPrefix("\(name): step 1 of 1, tap \"No such button\", didn't run:"))
        }
    }
}

extension OnDevice {
    @Suite struct ComposingTests {
        /// A new scene written on the device from a pipe, as an agent would: two steps that run,
        /// one that doesn't, and an undo that relaunches and replays the rest.
        @Test func aSceneIsComposedStepByStep() async throws {
            let example = try ExampleOnDevice()
            let name = "composed-\(UUID().uuidString.prefix(6))"
            let url = ProjectFiles(project: example.project).sceneURL(name, for: example.device.type!)
            defer { try? FileManager.default.removeItem(at: url) }
            let input = Lines([
                #"tap --label "New Note" --id new-note --hold 0.8"#,
                #"type --text "Shopping\n" --value "Title""#,
                #"tap --label "Nowhere""#,
                #"waitFor --label "Synced""#,
                "undo",
                "quit",
            ])
            let screens = Screens()
            try await Composer.run(name, set: "returning-user", in: example.project, on: example.device, input: input) { reply in
                if case .screen(let elements) = reply { screens.add(elements) }
                if case .failed(let message) = reply { screens.fail(message) }
            }
            let scene = try #require(ProjectFiles(project: example.project).readScene(name, for: example.device.type!, into: ProjectFiles.Report()))
            #expect(scene.steps.map(\.id) == ["new-note", nil], "the wait undone, the failed tap never added")
            #expect(screens.failures.count == 1 && screens.failures[0].contains("Nowhere"))
            #expect(screens.all.count == 2, "after launching, and after replaying")
            #expect(screens.all.last?.contains { $0.value == "Shopping" } == true, "the replay typed the title again")
        }
    }
}

/// Lines given one after another, as from a pipe.
final class Lines: ComposeInput, @unchecked Sendable {
    private var lines: [String]
    let isInteractive = false

    init(_ lines: [String]) { self.lines = lines }

    func next() async -> String? { lines.isEmpty ? nil : lines.removeFirst() }
    func ask(_ question: String) async -> String? { nil }
}

/// The screens a session showed, and what failed.
final class Screens: @unchecked Sendable {
    private let lock = NSLock()
    private var screens: [[ScreenElement]] = []
    private var failed: [String] = []

    func add(_ screen: [ScreenElement]) { lock.withLock { screens.append(screen) } }
    func fail(_ message: String) { lock.withLock { failed.append(message) } }
    var all: [[ScreenElement]] { lock.withLock { screens } }
    var failures: [String] { lock.withLock { failed } }
}

/// The steps a rehearsal reported finished, in order.
final class Played: @unchecked Sendable {
    private let lock = NSLock()
    private var played: [Int] = []

    func add(_ number: Int) { lock.withLock { played.append(number) } }
    var numbers: [Int] { lock.withLock { played } }
}
