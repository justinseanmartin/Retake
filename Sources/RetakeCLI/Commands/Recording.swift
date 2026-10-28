import ArgumentParser
import Foundation
import RetakeCore

struct Compose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Writes a scene a step at a time, on the device.",
        discussion: """
            Launches the app on the scene's set, replays its steps, prints what's on screen, then \
            takes actions, one a line: a step's action with its options, such as tap --label "New \
            Note", which runs at once and is added to the scene when it runs, or one that acts on \
            the scene, such as inspect, undo, replay or quit. `help` lists them. Reads standard input, so a \
            script or an agent can drive it; --json answers each line with a line of JSON.
            """,
    )

    @Argument(help: ArgumentHelp("The scene to write, new or not.", valueName: "scene"))
    var scene: String

    @Option(help: ArgumentHelp("For a new scene, the set it starts on (default: retake.json's defaultSet).", valueName: "set"))
    var set: String?

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Answer each line with a line of JSON, for a program to read.")
    var json = false

    @OptionGroup var project: ProjectOptions

    func run() async throws {
        let located = try project.locate()
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        let input = LineInput(prompt: json ? nil : "> ")
        // Control-C ends composing as `quit` does, so the device is still cleaned up.
        let interruption = Interruption()
        interruption.start { input.finish() }
        defer { interruption.stop() }
        let json = json, name = target.name
        try await Composer.run(scene, set: set, in: located, on: target, input: input, reply: { reply in
            if json { ComposeOutput.json(reply) } else { ComposeOutput.text(reply) }
            fflush(stdout)
        }, report: { event in
            switch event {
            case .launching(let set, let state):
                if !json { Swift.print("Launching on \(name), from \(set) (\(state.rawValue)).") }
            case .note(let message): Console.note(message)
            case .warning(let message): Console.warn(message)
            default: break
            }
        })
    }
}

/// What `compose` prints for each reply: for people, or as a line of JSON each.
enum ComposeOutput {
    static func text(_ reply: Composer.Reply) {
        switch reply {
        case .screen(let elements):
            print("On screen, \(elements.count) element\(elements.count == 1 ? "" : "s"):")
            for element in elements { print("  \(element.line)") }
        case .matches(let elements):
            if elements.isEmpty { print("Nothing on screen matches.") }
            for (index, element) in elements.enumerated() { print("  --occurrence \(index + 1)  \(element.line)") }
        case .added(let step, let number, let elements):
            print("✓ step \(number)\(step.id.map { " (\($0))" } ?? ""): \(step.line)")
            print("On screen, \(elements.count) element\(elements.count == 1 ? "" : "s"):")
            for element in elements { print("  \(element.line)") }
        case .changed(let step, let number):
            print("✓ step \(number)\(step.id.map { " (\($0))" } ?? ""): \(step.line)")
        case .steps(let steps):
            if steps.isEmpty { print("No steps yet.") }
            for (index, step) in steps.enumerated() {
                print("  \(index + 1)\(step.id.map { " (\($0))" } ?? ""): \(step.line)")
            }
        case .help(let text):
            print(text)
        case .failed(let message):
            print("✖ \(message)")
        }
    }

    static func json(_ reply: Composer.Reply) {
        var fields: [JSONObject.Entry]
        switch reply {
        case .screen(let elements):
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "screen", value: .array(elements.map(\.json)))]
        case .matches(let elements):
            let numbered = elements.enumerated().map { index, element -> JSONValue in
                guard case .object(var object) = element.json else { return element.json }
                object.entries.append(.init(key: "occurrence", value: .number(Double(index + 1))))
                return .object(object)
            }
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "screen", value: .array(numbered))]
        case .added(let step, let number, let elements):
            fields = [
                .init(key: "ok", value: .bool(true)), .init(key: "number", value: .number(Double(number))),
                .init(key: "step", value: step.json), .init(key: "screen", value: .array(elements.map(\.json))),
            ]
        case .changed(let step, let number):
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "number", value: .number(Double(number))), .init(key: "step", value: step.json)]
        case .steps(let steps):
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "steps", value: .array(steps.map(\.json)))]
        case .help(let text):
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "help", value: .string(text))]
        case .failed(let message):
            fields = [.init(key: "ok", value: .bool(false)), .init(key: "error", value: .string(message))]
        }
        print(JSONWriter.compact(.object(JSONObject(fields))))
    }
}

/// Lines from standard input, read on a thread of their own so waiting for the next doesn't hold
/// up anything else. At a terminal, each is prompted for, and a missing option can be asked for.
final class LineInput: ComposeInput, @unchecked Sendable {
    private let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let prompt: String?
    let isInteractive = isatty(STDIN_FILENO) == 1

    init(prompt: String?) {
        (lines, continuation) = AsyncStream.makeStream(of: String.self)
        self.prompt = prompt
        let continuation = continuation
        Thread.detachNewThread {
            while let line = readLine() { continuation.yield(line) }
            continuation.finish()
        }
    }

    func next() async -> String? {
        if isInteractive, let prompt { show(prompt) }
        var iterator = lines.makeAsyncIterator()
        return await iterator.next()
    }

    func ask(_ question: String) async -> String? {
        guard isInteractive else { return nil }
        show(question)
        var iterator = lines.makeAsyncIterator()
        return await iterator.next()
    }

    func finish() { continuation.finish() }

    private func show(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

/// Control-C, caught while it's started rather than ending the process.
final class Interruption: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var source: DispatchSourceSignal?

    func start(then handler: @escaping @Sendable () -> Void = {}) {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { [self] in
            lock.withLock { fired = true }
            handler()
        }
        source.resume()
        self.source = source
    }

    var happened: Bool { lock.withLock { fired } }

    func stop() {
        guard let source else { return }
        source.cancel()
        signal(SIGINT, SIG_DFL)
    }
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Records takes, or with --dry-run, plays scenes without recording them.",
        discussion: """
            With no scenes named, records every scene in scenes/<type>/ with no take yet, or every one \
            with --force. With --for, the scenes an edit uses. Scenes named are recorded whether or not \
            they have takes. A new take never replaces one. With --dry-run, plays the scenes chosen \
            the same way, and writes nothing.
            """,
    )

    @Argument(help: ArgumentHelp("The scenes to record.", valueName: "scene"))
    var scenes: [String] = []

    @Option(name: .customLong("for"), help: ArgumentHelp("Record the scenes this edit uses.", valueName: "edit"))
    var edit: String?

    @Flag(help: "Add a new take to scenes that already have one.")
    var force = false

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Stop at the first scene that fails, rather than carrying on with the next.")
    var stopOnFailure = false

    @Flag(help: "Play the scenes without recording them, writing nothing.")
    var dryRun = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if !scenes.isEmpty, edit != nil {
            throw ValidationError("Name scenes or give --for, not both.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        guard let type = target.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(target.name) is an iPhone or an iPad.")
        }
        let (chosen, taken) = try RecordRun.scenes(named: scenes, edit: edit, force: force, for: type, in: located)
        guard !chosen.isEmpty else {
            print(taken.isEmpty
                ? "There are no \(type.rawValue) scenes in \(located.displayPath(located.scenes(for: type)))."
                : "Every scene chosen already has a take: \(taken.joined(separator: ", ")). Give --force to record another.")
            return
        }
        let capture = dryRun ? nil : try directory.captureDevice(for: target)
        let name = target.name, dryRun = dryRun
        let player = Player(report: { event in Self.show(event, scene: "", device: name, dryRun: dryRun) })
        let outcomes = await RecordRun.run(
            chosen, in: located, on: target, capture: capture, dryRun: dryRun,
            stopOnFailure: stopOnFailure, player: player,
        )
        // What became of each scene, and the worst status among them.
        print("")
        for outcome in outcomes {
            if let failure = outcome.failure {
                let take = outcome.take.map { ", take \($0) kept, marked failed" } ?? ""
                // A step's failure names its scene already; a launch's doesn't.
                let message = failure.message.hasPrefix("\(outcome.scene): ") ? String(failure.message.dropFirst(outcome.scene.count + 2)) : failure.message
                print("✖ \(outcome.scene)\(take): \(message)")
            } else if let take = outcome.take {
                print("✓ \(outcome.scene): take \(take), \(String(format: "%.1f", outcome.duration ?? 0)) s, in \(located.displayPath(located.takes(for: type).appending(path: "\(outcome.scene)/\(take).mov")))")
            } else {
                print("✓ \(outcome.scene): played every step")
            }
        }
        let skipped = chosen.dropFirst(outcomes.count)
        if !skipped.isEmpty { print("Not \(dryRun ? "played" : "recorded"): \(skipped.joined(separator: ", ")).") }
        if let worst = outcomes.compactMap(\.failure?.status).max() {
            throw ExitCode(worst.rawValue)
        }
    }

    /// Each scene as it starts, and each step once it's played, with how long it took.
    @Sendable static func show(_ event: Player.Event, scene: String, device: String, dryRun: Bool) {
        switch event {
        case .scene(let name, let take):
            Swift.print(take.map { "Recording \(name), take \($0), on \(device)." } ?? "Playing \(name) on \(device).")
        case .launching(let set, let state):
            Swift.print("  From \(set) (\(state.rawValue)).")
        case .started:
            break
        case .finished(let played, let timing):
            Swift.print("  \(played.name): \(played.step.summary)  \(String(format: "%.2f", timing.seconds)) s")
        case .note(let message):
            Console.note(message)
        case .warning(let message):
            Console.warn(message)
        }
    }
}

struct Takes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lists takes.",
        discussion: """
            Lists each take's number, when it was recorded, the app's version and build, the device, its \
            duration, frames dropped, whether it failed, and the edits that pin it. Without --device or \
            --type, lists takes of both device types.
            """,
    )

    @Argument(help: ArgumentHelp("Only this scene's takes.", valueName: "scene"))
    var scene: String?

    @OptionGroup var device: DeviceOptions

    @Option(help: ArgumentHelp("Only this device type's takes.", valueName: "type"))
    var type: DeviceType?

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if device.device != nil, type != nil {
            throw ValidationError("Give --device or --type, not both.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        var types = type.map { [$0] } ?? DeviceType.allCases
        if device.named() != nil {
            let directory = try DeviceDirectory.current()
            let target = try directory.resolve(device.choice(configuration: nil, connected: directory.recordable.map(\.udid)))
            guard let deviceType = target.type else {
                throw RetakeError(.environment, "Retake can't tell whether \(target.name) is an iPhone or an iPad.")
            }
            types = [deviceType]
        }
        let takes = TakeStore.takes(of: scene, for: types, in: located)
        if let scene, takes.isEmpty {
            let files = ProjectFiles(project: located)
            guard types.contains(where: { FileManager.default.fileExists(atPath: files.sceneURL(scene, for: $0).path) }) else {
                throw RetakeError(.usage, "There's no scene \"\(scene)\" for \(types.map(\.rawValue).joined(separator: " or ")).")
            }
        }
        if output.json {
            print(JSONWriter.write(.array(takes.map(TakesOutput.json))), terminator: "")
        } else {
            TakesOutput.text(takes)
        }
    }
}

/// What `takes` prints: for people, or as JSON.
enum TakesOutput {
    static func text(_ takes: [TakeStore.Take]) {
        guard !takes.isEmpty else { return print("No takes.") }
        var heading: (DeviceType, String)?
        for take in takes {
            if heading?.0 != take.type || heading?.1 != take.scene {
                print("\(take.scene) (\(take.type.rawValue)):")
                heading = (take.type, take.scene)
            }
            guard let log = take.recorded else {
                print("  \(take.number)  can't be read: \(take.problem ?? "")")
                continue
            }
            let recorded = log.recordedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
            let app = [log.app.version, log.app.build.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
            var parts = [
                recorded, app.isEmpty ? nil : app, "\(log.device.marketingName ?? log.device.model), iOS \(log.device.os)",
                String(format: "%.1f s", log.duration), log.dropped.map { "\($0) dropped" },
            ].compactMap(\.self)
            if let failure = log.failure { parts.append("failed: \(failure)") }
            if let problem = take.problem { parts.append(problem) }
            if !take.pinnedBy.isEmpty { parts.append("pinned by \(take.pinnedBy.joined(separator: ", "))") }
            print("  \(take.number)  \(parts.joined(separator: "  "))")
        }
    }

    static func json(_ take: TakeStore.Take) -> JSONValue {
        var fields: [JSONObject.Entry] = [
            .init(key: "type", value: .string(take.type.rawValue)),
            .init(key: "scene", value: .string(take.scene)),
            .init(key: "take", value: .number(Double(take.number))),
        ]
        if let log = take.recorded {
            fields += [
                .init(key: "recordedAt", value: .string(ISO8601DateFormatter().string(from: log.recordedAt))),
                .init(key: "app", value: TakeLog.object([("version", log.app.version.map(JSONValue.string)), ("build", log.app.build.map(JSONValue.string))])),
                .init(key: "device", value: TakeLog.object([
                    ("model", .string(log.device.model)), ("marketingName", log.device.marketingName.map(JSONValue.string)), ("os", .string(log.device.os)),
                ])),
                .init(key: "duration", value: .number(log.duration)),
            ]
            if let frames = log.frames { fields.append(.init(key: "frames", value: .number(Double(frames)))) }
            if let dropped = log.dropped { fields.append(.init(key: "dropped", value: .number(Double(dropped)))) }
        }
        fields.append(.init(key: "failed", value: .bool(take.failed)))
        if let failure = take.recorded?.failure { fields.append(.init(key: "failure", value: .string(failure))) }
        if let problem = take.problem { fields.append(.init(key: "problem", value: .string(problem))) }
        fields.append(.init(key: "pinnedBy", value: .array(take.pinnedBy.map(JSONValue.string))))
        return .object(JSONObject(fields))
    }
}

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes takes and cuts, or take data left on the device.",
        discussion: """
            With neither --takes nor --cuts, deletes every take and every cut, of both device types \
            unless --type names one. --takes alone deletes every take, and given scenes, or a scene's \
            take as <scene>@<take>, only those; --cuts alone every cut, and given edits, only theirs. \
            Lists what it will delete, naming takes an edit pins, and asks first unless --yes. With \
            --on-device, deletes instead what Retake leaves in the app's container on the device \
            (takes' copies of its data, and staged set files), which record does at the end of a run.
            """,
    )

    // Each may be given bare, `--takes`, meaning all; `Retake.run` passes that on as `*`.
    @Option(help: ArgumentHelp("Delete takes: every one, or the scenes and takes given, as create-note,share-note@2.", valueName: "takes"))
    var takes: String?

    @Option(help: ArgumentHelp("Delete cuts: every one, or the edits' given, as video1,video2.", valueName: "edits"))
    var cuts: String?

    @Option(help: ArgumentHelp("Only this device type's.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Don't ask first.")
    var yes = false

    @Flag(help: "Delete takes' copies of the app's data, and staged set files, from the device instead.")
    var onDevice = false

    @OptionGroup var device: DeviceOptions
    @OptionGroup var project: ProjectOptions

    /// The options whose value may be left out.
    static let optionalValues = ["--takes", "--cuts"]

    func validate() throws {
        if onDevice, takes != nil || cuts != nil || type != nil || yes {
            throw ValidationError(
                "--on-device deletes only what's on the device; it takes no --takes, --cuts, --type or --yes.",
            )
        }
        if !onDevice, device.device != nil {
            throw ValidationError("--device applies only with --on-device.")
        }
    }

    /// A comma-separated list, where `*` stands for every one, as an empty list.
    static func list(_ value: String?) -> [String]? {
        value.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "*" } }
    }

    func run() async throws {
        let located = try project.locate()
        guard onDevice else {
            let choices = try Self.list(takes).map { names throws(RetakeError) in try names.map { name throws(RetakeError) in try TakeStore.TakeChoice.parse(name) } }
            let cleaning = try TakeStore.cleaning(takes: choices, cuts: Self.list(cuts), for: type.map { [$0] } ?? DeviceType.allCases, in: located)
            guard !cleaning.takes.isEmpty || !cleaning.cuts.isEmpty else { return print("Nothing to delete.") }
            Self.describe(cleaning, in: located)
            if !yes {
                guard Prompt.isInteractive else {
                    throw RetakeError(.usage, "Give --yes to delete without being asked; there's no terminal to ask at.")
                }
                FileHandle.standardError.write(Data("Delete \(cleaning.takes.count + cleaning.cuts.count == 1 ? "it" : "them")? [y/N] ".utf8))
                guard ["y", "yes"].contains(readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "") else {
                    return print("Nothing deleted.")
                }
            }
            try TakeStore.delete(cleaning, in: located)
            print("Deleted.")
            return
        }
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        let bundleID = try Installer.bundleID(for: located)
        try Launcher.cleanUp(bundleID: bundleID, on: target)
        print("Deleted takes' copies of \(bundleID)'s data, and staged set files, from \(target.name).")
    }

    /// What will be deleted: takes by scene, each edit's cuts, and the pins left pointing nowhere.
    static func describe(_ cleaning: TakeStore.Cleaning, in project: Project) {
        if !cleaning.takes.isEmpty {
            print("Takes:")
            for type in DeviceType.allCases {
                let ofType = cleaning.takes.filter { $0.type == type }
                for scene in ofType.map(\.scene).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                    let numbers = ofType.filter { $0.scene == scene }.map { String($0.number) }
                    print("  \(scene) (\(type.rawValue)): \(numbers.joined(separator: ", "))")
                }
            }
        }
        if !cleaning.cuts.isEmpty {
            print("Cuts:")
            for folder in cleaning.cuts { print("  \(project.displayPath(folder))") }
        }
        for take in cleaning.pinned {
            Console.warn("\(take.name) (\(take.type.rawValue)) is pinned by \(take.pinnedBy.joined(separator: ", ")), which can't be cut until conformed onto another take.")
        }
    }
}
