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
        let target = try device.target(configuration: located.settings.device.map { ($0, located.configuration) }).device
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
            for match in elements { print("  \(match.name?.options ?? "(nothing to name it by)")  ·  \(match.element.line)") }
        case .added(let step, let number, let elements, let suggestion):
            print("✓ step \(number)\(step.id.map { " (\($0))" } ?? ""): \(step.line)")
            if case .tapElement(let target)? = suggestion?.action {
                if target.occurrence == nil {
                    print("  That point is on \(target), which a step can name and follow wherever the layout puts it: undo, then tap \(target.options)")
                } else {
                    print("  That point is on \(target), which a step can name only by where it comes among those alike, which breaks when the layout changes: undo, then tap \(target.options)")
                }
            }
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
            let numbered = elements.map { match -> JSONValue in
                guard case .object(var object) = match.element.json, let name = match.name else { return match.element.json }
                object.entries.append(.init(key: "name", value: name.json))
                return .object(object)
            }
            fields = [.init(key: "ok", value: .bool(true)), .init(key: "screen", value: .array(numbered))]
        case .added(let step, let number, let elements, let suggestion):
            fields = [
                .init(key: "ok", value: .bool(true)), .init(key: "number", value: .number(Double(number))),
                .init(key: "step", value: step.json), .init(key: "screen", value: .array(elements.map(\.json))),
            ]
            if let suggestion { fields.append(.init(key: "suggestion", value: suggestion.json)) }
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
        abstract: "Records takes, or with --stills-only, only their captures, or with --dry-run, plays scenes without recording them.",
        discussion: """
            With no scenes named, records every scene in scenes/<type>/ with no take yet, or every one \
            with --force. With --for, the scenes an edit uses. Scenes named are recorded whether or not \
            they have takes. A take that succeeds replaces the scene's take, which is kept as its \
            previous one, replacing that; one that fails is kept as the scene's latest failure, and \
            leaves its take alone, as does one interrupted. A scene's capture steps save the screen as \
            stills, in output/captures/<type>/<scene>/, replacing its captures when every step ran. With \
            --stills-only, plays the scenes with capture steps, those with no captures yet unless --force, \
            taking their captures without recording a take. With --dry-run, plays the scenes chosen \
            the same way, and writes nothing to the project: its console log goes to a temporary \
            folder, as every launch's does.
            """,
    )

    @Argument(help: ArgumentHelp("The scenes to record.", valueName: "scene"))
    var scenes: [String] = []

    @Option(name: .customLong("for"), help: ArgumentHelp("Record the scenes this edit uses.", valueName: "edit"))
    var edit: String?

    @Flag(help: "Record again scenes that already have a take, keeping the take each replaces as its previous one.")
    var force = false

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Stop at the first scene that fails, rather than carrying on with the next.")
    var stopOnFailure = false

    @Flag(help: "Play the scenes without recording them, writing nothing.")
    var dryRun = false

    @Flag(help: "Take only the scenes' captures, recording no take: the scenes with capture steps, those with no captures yet unless --force.")
    var stillsOnly = false

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if !scenes.isEmpty, edit != nil {
            throw ValidationError("Name scenes or give --for, not both.")
        }
        if stillsOnly, dryRun {
            throw ValidationError("--stills-only takes captures, and --dry-run takes nothing; give one.")
        }
        if stillsOnly, edit != nil {
            throw ValidationError("--for chooses the scenes an edit cuts, and an edit uses no captures; name the scenes, or give neither.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        let (directory, target) = try device.target(configuration: located.settings.device.map { ($0, located.configuration) })
        guard let type = target.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(target.name) is an iPhone or an iPad.")
        }
        let (chosen, taken) = try RecordRun.scenes(named: scenes, edit: edit, force: force, stillsOnly: stillsOnly, for: type, in: located)
        guard !chosen.isEmpty else {
            if stillsOnly {
                print(taken.isEmpty
                    ? "No \(type.rawValue) scene in \(located.displayPath(located.scenes(for: type))) has a capture step."
                    : "Every scene chosen already has its captures: \(taken.joined(separator: ", ")). Give --force to take them again.")
            } else {
                print(taken.isEmpty
                    ? "There are no \(type.rawValue) scenes in \(located.displayPath(located.scenes(for: type)))."
                    : "Every scene chosen already has a take: \(taken.joined(separator: ", ")). Give --force to record them again.")
            }
            return
        }
        let capture = dryRun ? nil : try directory.captureDevice(for: target)
        let name = target.name, dryRun = dryRun, stillsOnly = stillsOnly
        let player = Player(report: { event in Self.show(event, scene: "", device: name, dryRun: dryRun, stillsOnly: stillsOnly) })
        let outcomes = await RecordRun.run(
            chosen, in: located, on: target, capture: capture, dryRun: dryRun, stillsOnly: stillsOnly,
            stopOnFailure: stopOnFailure, player: player,
        )
        // What became of each scene, and the worst status among them.
        print("")
        for outcome in outcomes {
            if let failure = outcome.failure {
                let take = outcome.movie.map { ", kept as its latest failure, \(located.displayPath($0))" } ?? ""
                // A step's failure names its scene already; a launch's doesn't.
                let message = failure.message.hasPrefix("\(outcome.scene): ") ? String(failure.message.dropFirst(outcome.scene.count + 2)) : failure.message
                print("✖ \(outcome.scene)\(take): \(message)")
            } else if let movie = outcome.movie {
                let stills = outcome.captures.map { ", and \(Self.captures(outcome.captured.count)) in \(located.displayPath($0))" } ?? ""
                print("✓ \(outcome.scene): \(String(format: "%.1f", outcome.duration ?? 0)) s, in \(located.displayPath(movie))\(stills)")
            } else if let folder = outcome.captures {
                print("✓ \(outcome.scene): \(Self.captures(outcome.captured.count)), in \(located.displayPath(folder))")
            } else {
                print("✓ \(outcome.scene): played every step")
            }
        }
        // Whether App Store Connect takes the captures as screenshots, once for each size.
        var sizes: [CaptureSize] = []
        for size in outcomes.flatMap(\.captured) where !sizes.contains(where: { $0.width == size.width && $0.height == size.height }) {
            sizes.append(size)
            print(AppStoreScreenshots.note(width: size.width, height: size.height, for: type))
        }
        let skipped = chosen.dropFirst(outcomes.count)
        if !skipped.isEmpty { print("Not \(dryRun ? "played" : "recorded"): \(skipped.joined(separator: ", ")).") }
        if let worst = outcomes.compactMap(\.failure?.status).max() {
            throw ExitCode(worst.rawValue)
        }
    }

    static func captures(_ count: Int) -> String { count == 1 ? "1 capture" : "\(count) captures" }

    /// Each scene as it starts, and each step once it's played, with how long it took.
    @Sendable static func show(_ event: Player.Event, scene: String, device: String, dryRun: Bool, stillsOnly: Bool = false) {
        switch event {
        case .scene(let name, let recording):
            Swift.print(!recording ? "Playing \(name) on \(device)." : stillsOnly ? "Capturing \(name) on \(device)." : "Recording \(name) on \(device).")
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
        abstract: "Lists takes, or puts back a scene's previous take.",
        discussion: """
            Lists each scene's take, the previous take it replaced, and its latest failure: when each \
            was recorded, the app's version and build, the device, its duration, frames dropped, why \
            a failure failed, and the edits cut from the take. Without --device or --type, lists \
            takes of both device types. With --restore, puts back a scene's previous take, the take \
            it replaced becoming the previous one, so restoring again undoes it.
            """,
    )

    @Argument(help: ArgumentHelp("Only this scene's takes.", valueName: "scene"))
    var scene: String?

    @Option(help: ArgumentHelp("Put back this scene's previous take, swapping it with its take.", valueName: "scene"))
    var restore: String?

    @OptionGroup var device: DeviceOptions

    @Option(help: ArgumentHelp("Only this device type's takes.", valueName: "type"))
    var type: DeviceType?

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if device.device != nil, type != nil {
            throw ValidationError("Give --device or --type, not both.")
        }
        if restore != nil, scene != nil || output.json {
            throw ValidationError("--restore names its scene itself, and lists nothing; give it no scene and no --json.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        var types = type.map { [$0] } ?? DeviceType.allCases
        if device.named() != nil {
            let target = try device.target(configuration: nil).device
            guard let deviceType = target.type else {
                throw RetakeError(.environment, "Retake can't tell whether \(target.name) is an iPhone or an iPad.")
            }
            types = [deviceType]
        }
        try TakeStore.refuseOldLayout(for: types, in: located)
        if let restore {
            let withPrevious = types.filter { type in TakeStore.takes(of: restore, for: [type], in: located).contains { $0.kind == .previous } }
            guard let restoring = withPrevious.first else {
                throw RetakeError(.usage, "There's no previous take of \(restore)\(types.count == 1 ? " for \(types[0].rawValue)" : "") to put back.")
            }
            guard withPrevious.count == 1 else {
                throw RetakeError(.usage, "\(restore) has a previous take for both \(withPrevious.map(\.rawValue).joined(separator: " and ")); give --type to say which to put back.")
            }
            try TakeStore.restore(restore, for: restoring, in: located)
            let take = TakeStore.take(of: restore, for: restoring, in: located)
            let when = take?.recorded.map { ", recorded \(StatusOutput.date($0.recordedAt))," } ?? ""
            print("Put back \(restore)'s previous \(restoring.rawValue) take\(when) in place of the one that replaced it, which is its previous take now.")
            return
        }
        let takes = TakeStore.takes(of: scene, for: types, in: located)
        if let scene, takes.isEmpty {
            let files = ProjectFiles(project: located)
            guard types.contains(where: { FileManager.default.fileExists(atPath: files.sceneURL(scene, for: $0).path) }) else {
                throw RetakeError(
                    .usage,
                    "There's no scene \"\(scene)\" for \(types.map(\.rawValue).joined(separator: " or "))"
                        + "\(types.lazy.compactMap { files.misnamedFolder(located.scenes(for: $0)) }.first.map { ": \($0)" } ?? "").",
                )
            }
        }
        if output.json {
            print(JSONWriter.write(.array(takes.map(\.json))), terminator: "")
        } else {
            TakesOutput.text(takes)
        }
    }
}

/// What `takes` prints for people; `TakeStore.Take.json` is what it prints as JSON.
enum TakesOutput {
    static func text(_ takes: [TakeStore.Take]) {
        guard !takes.isEmpty else { return print("No takes.") }
        var heading: (DeviceType, String)?
        for take in takes {
            if heading?.0 != take.type || heading?.1 != take.scene {
                print("\(take.scene) (\(take.type.rawValue)):")
                heading = (take.type, take.scene)
            }
            let kind = take.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            guard let log = take.recorded else {
                print("  \(kind)  can't be read: \(take.problem ?? "")")
                continue
            }
            let app = [log.app.version, log.app.build.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
            var parts = [
                StatusOutput.date(log.recordedAt), app.isEmpty ? nil : app, "\(log.device.marketingName ?? log.device.model), iOS \(log.device.os)",
                String(format: "%.1f s", log.duration), "\(log.dropped) dropped",
            ].compactMap(\.self)
            if let failure = log.failure { parts.append("failed: \(failure)") }
            if let problem = take.problem { parts.append(problem) }
            if !take.usedBy.isEmpty { parts.append("used by \(take.usedBy.joined(separator: ", "))") }
            print("  \(kind)  \(parts.joined(separator: "  "))")
        }
    }
}

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes takes, cuts and captures, or take data left on the device.",
        discussion: """
            With none of --takes, --cuts and --captures, deletes every take, cut and capture, of both \
            device types unless --type names one. --takes alone deletes every take, and given scenes, \
            only theirs: each one's take, previous take and latest failure, and any numbered takes an \
            earlier Retake left; --cuts alone every cut, and given edits, only theirs; --captures alone \
            every scene's captures, and given scenes, only theirs. --unused deletes every previous take \
            and failure, the takes and scene definitions no edit needs, keeping each needed scene's \
            take and every scene that captures, and the captures of scenes that no longer do. \
            Lists what it will delete, naming takes an edit is cut from, and asks first unless --yes. With \
            --on-device, deletes instead what Retake leaves in the app's container on the device \
            (takes' copies of its data, and staged set files), which record does at the end of a run.
            """,
    )

    // Each may be given bare, `--takes`, meaning all; `Retake.run` passes that on as `*`.
    @Option(help: ArgumentHelp("Delete takes: every one, or the given scenes', as create-note,share-note.", valueName: "scenes"))
    var takes: String?

    @Option(help: ArgumentHelp("Delete cuts: every one, or the edits' given, as video1,video2.", valueName: "edits"))
    var cuts: String?

    @Option(help: ArgumentHelp("Delete captures: every scene's, or the given scenes', as home,settings.", valueName: "scenes"))
    var captures: String?

    @Option(help: ArgumentHelp("Only this device type's.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Delete previous takes, failures, and the takes and scene definitions no edit needs, keeping each needed scene's take.")
    var unused = false

    @Flag(help: "Don't ask first.")
    var yes = false

    @Flag(help: "Delete takes' copies of the app's data, and staged set files, from the device instead.")
    var onDevice = false

    @OptionGroup var device: DeviceOptions
    @OptionGroup var project: ProjectOptions

    /// The options whose value may be left out.
    static let optionalValues = ["--takes", "--cuts", "--captures"]

    func validate() throws {
        if onDevice, takes != nil || cuts != nil || captures != nil || type != nil || yes || unused {
            throw ValidationError(
                "--on-device deletes only what's on the device; it takes no --takes, --cuts, --captures, --type, --unused or --yes.",
            )
        }
        if unused, takes != nil || cuts != nil || captures != nil {
            throw ValidationError("--unused chooses takes, scenes and captures itself; it can't be combined with --takes, --cuts or --captures.")
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
            let types = type.map { [$0] } ?? DeviceType.allCases
            let cleaning: TakeStore.Cleaning
            if unused {
                cleaning = try TakeStore.unused(for: types, in: located)
            } else {
                cleaning = try TakeStore.cleaning(takes: Self.list(takes), cuts: Self.list(cuts), captures: Self.list(captures), for: types, in: located)
            }
            guard !cleaning.isEmpty else { return print("Nothing to delete.") }
            Self.describe(cleaning, in: located)
            if !yes {
                guard Prompt.isInteractive else {
                    throw RetakeError(.usage, "Give --yes to delete without being asked; there's no terminal to ask at.")
                }
                let count = cleaning.count
                FileHandle.standardError.write(Data("Delete \(count == 1 ? "it" : "them")? [y/N] ".utf8))
                guard ["y", "yes"].contains(readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "") else {
                    return print("Nothing deleted.")
                }
            }
            try TakeStore.delete(cleaning, in: located)
            print("Deleted.")
            return
        }
        let target = try device.target(configuration: located.settings.device.map { ($0, located.configuration) }).device
        let bundleID = try Installer.bundleID(for: located)
        try Launcher.cleanUp(bundleID: bundleID, on: target)
        print("Deleted takes' copies of \(bundleID)'s data, and staged set files, from \(target.name).")
    }

    /// What will be deleted: takes by scene, each edit's cuts, and the takes edits were cut from.
    static func describe(_ cleaning: TakeStore.Cleaning, in project: Project) {
        if !cleaning.takes.isEmpty {
            print("Takes:")
            for type in DeviceType.allCases {
                let ofType = cleaning.takes.filter { $0.type == type }
                for scene in ofType.map(\.scene).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                    let kinds = ofType.filter { $0.scene == scene }.map(\.kind.rawValue)
                    print("  \(scene) (\(type.rawValue)): \(kinds.joined(separator: ", "))")
                }
            }
        }
        if !cleaning.oldTakes.isEmpty {
            print("Numbered takes from an earlier Retake:")
            for folder in cleaning.oldTakes { print("  \(project.displayPath(folder))/") }
        }
        if !cleaning.cuts.isEmpty {
            print("Cuts:")
            for folder in cleaning.cuts { print("  \(project.displayPath(folder))") }
        }
        if !cleaning.scenes.isEmpty {
            print("Scenes:")
            for scene in cleaning.scenes { print("  \(project.displayPath(scene))") }
        }
        if !cleaning.captures.isEmpty {
            print("Captures:")
            for folder in cleaning.captures { print("  \(project.displayPath(folder))/") }
        }
        for take in cleaning.used {
            Console.warn("\(take.scene)'s \(take.type.rawValue) take is used by \(take.usedBy.joined(separator: ", ")); record it again before the next cut.")
        }
    }
}
