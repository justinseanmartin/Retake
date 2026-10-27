import ArgumentParser
import Foundation
import RetakeCore

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints what's on screen.",
        discussion: """
            Launches the app on a set and prints each element's label, traits, frame and activation \
            point, in screen points. With --watch, prints again each time the screen changes, until \
            stopped with Control-C.
            """,
    )

    @Option(help: ArgumentHelp("The set to launch on (default: retake.json's defaultSet).", valueName: "set"))
    var set: String?

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Print again whenever the screen changes, until stopped.")
    var watch = false

    @OptionGroup var project: ProjectOptions

    func run() async throws {
        let located = try project.locate()
        let set = try Inspection.set(self.set, in: located)
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        // Control-C ends watching rather than the process, so the device is still cleaned up.
        let interruption = Interruption()
        if watch { interruption.start() }
        defer { interruption.stop() }
        let started = Date()
        let shown = Counter()
        let inspection = Inspection(stopped: { interruption.happened }) { elements in
            let count = shown.next()
            if count > 1 { Swift.print("") }
            let when = count == 1 ? "On screen" : String(format: "Changed, %.1f s in", Date().timeIntervalSince(started))
            Swift.print("\(when), \(elements.count) element\(elements.count == 1 ? "" : "s"):")
            for element in elements { Swift.print("  \(element.line)") }
            if count == 1, watch { Swift.print("Watching for changes; press Control-C to stop.") }
            // Each screen as it comes, through a pipe too, since watching runs until stopped.
            fflush(stdout)
        }
        let name = target.name
        try await Inspection.run(set, in: located, on: target, watch: watch, inspection: inspection) { event in
            if case .launching(let set, let state) = event {
                Swift.print("Launching the app on \(name), from \(set) (\(state.rawValue)).")
            } else {
                Rehearse.show(event, scene: "", device: name)
            }
        }
        if interruption.happened { Swift.print("Stopped.") }
    }
}

/// Control-C, caught while it's started rather than ending the process.
final class Interruption: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var source: DispatchSourceSignal?

    func start() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { [self] in lock.withLock { fired = true } }
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

/// Counts up from 1, from any thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int { lock.withLock { count += 1; return count } }
}

struct Rehearse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Plays a scene without recording it.",
        discussion: "Writes nothing. Fails (1) at the first step that doesn't run, naming it.",
    )

    @Argument(help: ArgumentHelp("The scene to play.", valueName: "scene"))
    var scene: String

    @OptionGroup var device: DeviceOptions

    @Option(
        name: .customLong("from"),
        help: ArgumentHelp(
            "Skip to this step, numbered from 1, playing the steps before it without their holds.",
            valueName: "step",
        ),
    )
    var fromStep: Int?

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if let fromStep, fromStep < 1 {
            throw ValidationError("--from numbers steps from 1.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        let player = Player(report: { event in Self.show(event, scene: scene, device: target.name) })
        try await Rehearsal.run(scene, in: located, on: target, from: fromStep ?? 1, player: player)
        print("Played every step of \(scene).")
    }

    /// Each step once it's played, with how long it took, and what an `inspect` step saw.
    @Sendable static func show(_ event: Player.Event, scene: String, device: String) {
        switch event {
        case .launching(let set, let state):
            Swift.print("Rehearsing \(scene) on \(device), from \(set) (\(state.rawValue)).")
        case .started:
            break
        case .finished(let played, let seconds):
            Swift.print("  \(played.name): \(played.step.summary)  \(String(format: "%.2f", seconds)) s")
        case .inspected(_, let elements):
            for element in elements { Swift.print("      \(element.line)") }
        case .note(let message):
            Console.note(message)
        case .warning(let message):
            Console.warn(message)
        }
    }
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Records takes.",
        discussion: """
            With no scenes named, records every scene in scenes/<type>/ with no take yet, or every one \
            with --force. With --for, the scenes an edit uses. Scenes named are recorded whether or not \
            they have takes. A new take never replaces one.
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

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if !scenes.isEmpty, edit != nil {
            throw ValidationError("Name scenes or give --for, not both.")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("record")
    }
}

struct Takes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lists takes.",
        discussion: "Without --device or --type, lists takes of both device types.",
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
        _ = try project.locate()
        throw RetakeError.notImplemented("takes")
    }
}

struct Discard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes a take.",
        discussion: "Fails (1), deleting nothing, if an edit pins one of them.",
    )

    @Argument(help: ArgumentHelp("The scene the takes are of.", valueName: "scene"))
    var scene: String

    @Argument(help: ArgumentHelp("The takes' numbers.", valueName: "take"))
    var takes: [Int]

    @Option(help: ArgumentHelp("The device type the takes are of.", valueName: "type"))
    var type: DeviceType?

    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if takes.isEmpty {
            throw ValidationError("Name at least one take.")
        }
        if let take = takes.first(where: { $0 < 1 }) {
            throw ValidationError("Takes are numbered from 1, not \(take).")
        }
    }

    func run() async throws {
        _ = try project.locate()
        throw RetakeError.notImplemented("discard")
    }
}

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deletes takes and videos, or take data left on the device.",
        discussion: """
            Deletes every take and every rendered video, of both device types unless --type names one. \
            Edits' pins are left as they are. With --on-device, deletes instead what Retake leaves in the \
            app's container on the device (takes' copies of its data, and staged set files), which \
            record and rehearse do at the end of a run.
            """,
    )

    @Flag(help: "Delete only takes.")
    var takes = false

    @Flag(help: "Delete only videos.")
    var videos = false

    @Option(help: ArgumentHelp("Only this device type's.", valueName: "type"))
    var type: DeviceType?

    @Flag(help: "Don't ask first.")
    var yes = false

    @Flag(help: "Delete takes' copies of the app's data, and staged set files, from the device instead.")
    var onDevice = false

    @OptionGroup var device: DeviceOptions
    @OptionGroup var project: ProjectOptions

    func validate() throws {
        if takes, videos {
            throw ValidationError("Give --takes or --videos, not both; with neither, both are deleted.")
        }
        if onDevice, takes || videos || type != nil || yes {
            throw ValidationError(
                "--on-device deletes only what's on the device; it takes no --takes, --videos, --type or --yes.",
            )
        }
        if !onDevice, device.device != nil {
            throw ValidationError("--device applies only with --on-device.")
        }
    }

    func run() async throws {
        let located = try project.locate()
        guard onDevice else { throw RetakeError.notImplemented("clean") }
        let directory = try DeviceDirectory.current()
        let target = try directory.resolve(device.choice(
            configuration: located.settings.device.map { ($0, located.configuration) },
            connected: directory.recordable.map(\.udid),
        ))
        let bundleID = try Installer.bundleID(for: located)
        try Launcher.cleanUp(bundleID: bundleID, on: target)
        print("Deleted takes' copies of \(bundleID)'s data, and staged set files, from \(target.name).")
    }
}
