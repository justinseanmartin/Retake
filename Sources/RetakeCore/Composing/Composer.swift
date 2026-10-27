import ButtonHeist
import Foundation

/// Where `compose` reads its actions from: a terminal, where it can ask for what's missing, or a
/// pipe, where it can't.
public protocol ComposeInput: Sendable {
    /// The next line, or nil when there are no more.
    func next() async -> String?
    /// Asks a question and waits for the answer; only at a terminal.
    func ask(_ question: String) async -> String?
    var isInteractive: Bool { get }
}

/// Writing a scene a step at a time on the device. See docs/cli.md, "retake compose".
public enum Composer {
    /// What `compose` says back, after launching and after each action.
    public enum Reply: Sendable {
        /// What's on screen: after launching, or for `inspect`.
        case screen([ScreenElement])
        /// The elements `inspect` was asked for, in the order VoiceOver reads them, so the first is
        /// `--occurrence 1`.
        case matches([ScreenElement])
        /// A step that ran and was added, its number, and the screen after it.
        case added(Step, number: Int, [ScreenElement])
        /// The last step, changed by `set`.
        case changed(Step, number: Int)
        /// The scene's steps, for `steps`, or replayed after `undo` or `replay`.
        case steps([Step])
        case help(String)
        /// A step that didn't run, or an action that was wrong; nothing was added.
        case failed(String)
    }

    /// Composes `name` for the device's type: launches on its set (or `set` for a new scene), replays
    /// its steps, then takes actions from `input` until `quit` or the input ends, replying through
    /// `reply`, and writing the scene after each change. Cleans up the device at the end.
    public static func run(
        _ name: String,
        set setName: String?,
        in project: Project,
        on device: Device,
        input: some ComposeInput,
        reply: @escaping @Sendable (Reply) -> Void,
        report: @escaping @Sendable (Player.Event) -> Void = { _ in },
    ) async throws(RetakeError) {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let files = ProjectFiles(project: project)
        let url = files.sceneURL(name, for: type)
        var scene: SceneFile?
        var text: String?
        if FileManager.default.fileExists(atPath: url.path) {
            let report = ProjectFiles.Report()
            guard let read = files.readScene(name, for: type, into: report) else { throw report.error }
            if let named = read.set, setName != nil {
                throw RetakeError(.usage, "\(project.displayPath(url)) already names its set, \(named); leave --set out.")
            }
            scene = read
            text = try? String(contentsOf: url, encoding: .utf8)
        }
        guard let setFor = scene?.set ?? setName ?? project.settings.defaultSet else {
            throw RetakeError(.usage, "Give --set, or a defaultSet in \(project.configuration.lastPathComponent), for the new scene \(name) to start on.")
        }
        let set = try AppSession.set(setFor, in: project, namedBy: scene == nil && setName != nil ? "--set" : project.displayPath(url))
        let state = State(document: SceneDocument(url: url, scene: scene, text: text, newOn: setFor), scene: scene ?? SceneFile(set: setFor, steps: []))

        while true {
            var launch = state.scene
            launch.steps = state.document.steps
            try await AppSession.run("compose-\(name)", in: project, set: set, scene: launch, on: device, report: report, cleanUp: false) { driver, _ throws(RetakeError) in
                state.ending = try await session(name, state: state, on: driver, input: input, reply: reply)
            }
            if state.ending != .relaunch { break }
        }
        if set.state != .live {
            do {
                try Launcher.cleanUp(bundleID: try Installer.bundleID(for: project), on: device)
            } catch {
                report(.warning("\(error.message) Run `retake clean --on-device` to delete what's left."))
            }
        }
    }

    enum Ending { case quit, relaunch }

    /// The scene as it's composed, across relaunches.
    final class State: @unchecked Sendable {
        var document: SceneDocument
        let scene: SceneFile
        var ending: Ending = .quit

        init(document: SceneDocument, scene: SceneFile) {
            self.document = document
            self.scene = scene
        }
    }

    /// One launch's worth: replays the scene's steps, shows the screen, then runs actions until
    /// one ends it.
    @ButtonHeistActor
    static func session(
        _ name: String,
        state: State,
        on driver: some AppDriver,
        input: some ComposeInput,
        player: Player = Player(),
        reply: @escaping @Sendable (Reply) -> Void,
    ) async throws(RetakeError) -> Ending {
        // A replay waits out each step's hold, as a take does, since a step can need the app to have
        // settled after the one before. A step given now runs as soon as it's given.
        var orientation = state.scene.orientation
        if !state.document.steps.isEmpty {
            var replay = state.scene
            replay.steps = state.document.steps
            do throws(RetakeError) {
                try await player.play(replay, named: name, on: driver)
                if let turned = state.document.steps.compactMap({ step -> SceneFile.Orientation? in
                    if case .orientation(let to)? = step.action { return to } else { return nil }
                }).last { orientation = turned }
            } catch {
                reply(.failed("Replaying the scene: \(error.message)"))
            }
            reply(.steps(state.document.steps))
        }
        reply(.screen(try await settled(driver)))

        while let line = await input.next() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let action: ComposeAction
            do {
                action = try await parse(line, input: input)
            } catch {
                reply(.failed(error.message))
                continue
            }
            switch action {
            case .step(let step):
                if let problem = problem(withID: step.id, in: state.document.steps) {
                    reply(.failed(problem))
                    continue
                }
                let number = state.document.steps.count + 1
                let played = Player.Played(isSetup: false, number: number, count: number, step: step)
                do throws(RetakeError) {
                    try await player.play(played, in: name, orientation: &orientation, holding: false, on: driver)
                } catch {
                    // The scene is the one being composed, so its name says nothing here.
                    reply(.failed(error.message.hasPrefix("\(name): ") ? String(error.message.dropFirst(name.count + 2)) : error.message))
                    continue
                }
                state.document.steps.append(step)
                try state.document.write()
                reply(.added(step, number: number, try await driver.elements()))
            case .inspect(let target):
                let elements = try await driver.elements()
                reply(target.map { target in .matches(elements.filter(target.matches)) } ?? .screen(elements))
            case .set(let hold, let id):
                guard var last = state.document.steps.last else { reply(.failed("There's no step yet to change.")); continue }
                if let problem = problem(withID: id, in: state.document.steps.dropLast()) {
                    reply(.failed(problem))
                    continue
                }
                if let hold { last.hold = hold }
                if let id { last.id = id }
                try replaceLast(with: last, in: state, reply: reply)
            case .undo(let count):
                let steps = state.document.steps.count
                guard steps > 0 else { reply(.failed("There's no step to undo.")); continue }
                guard count <= steps else { reply(.failed("There \(steps == 1 ? "is 1 step" : "are \(steps) steps") to undo, not \(count).")); continue }
                state.document.steps.removeLast(count)
                try state.document.write()
                return .relaunch
            case .replay:
                return .relaunch
            case .steps:
                reply(.steps(state.document.steps))
            case .help(let action):
                if let action {
                    guard let spec = ComposeActionSpec.all.first(where: { $0.name == action }) else {
                        reply(.failed("There's no action \"\(action)\"; `help` lists them."))
                        continue
                    }
                    reply(.help(spec.usage))
                } else {
                    reply(.help(ComposeActionSpec.overview))
                }
            case .quit:
                return .quit
            }
        }
        return .quit
    }

    /// A line as an action; at a terminal, asking for what it's missing, one option at a time.
    static func parse(_ line: String, input: some ComposeInput) async throws(ComposeAction.Problem) -> ComposeAction {
        var line = line
        while true {
            do {
                return try ComposeAction.parse(line)
            } catch .missing(let action, let options) where input.isInteractive {
                for option in options {
                    guard let answer = await ask(for: option, action: action, input: input) else {
                        throw .wrong("Left out; nothing was done.")
                    }
                    line += answer
                }
            }
        }
    }

    /// Asks for one missing option, returning it as words to add to the line, or nil when left
    /// empty. An element is asked for as its label, then its value, then its identifier, until one
    /// is given.
    static func ask(for option: ComposeOption, action: String, input: some ComposeInput) async -> String? {
        let names = option.name == "element" ? ElementOptions.asked : [option.name]
        for name in names {
            let question = option.name == "element"
                ? "\(action) needs an element. --\(name) (empty to \(name == names.last ? "give up" : "skip"))? "
                : "\(action) needs --\(name) \(option.value), \(option.help) (empty to give up)? "
            guard let answer = await input.ask(question), !answer.isEmpty else { continue }
            return " --\(name) \"\(answer.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return nil
    }

    /// Why a step can't have `id`, as a scene's file reading would say, or nil when it can.
    static func problem(withID id: String?, in steps: some Collection<Step>) -> String? {
        guard let id else { return nil }
        if steps.contains(where: { $0.id == id }) { return "\"\(id)\" is already a step's id; ids are unique in a scene." }
        if SceneFile.isNumberLike(id) { return "\"\(id)\" looks like a number, which anchors count steps by; give it a name." }
        if id == "start" || id == "end" { return "\"\(id)\" names the take's own \(id), so a step can't have it." }
        return nil
    }

    static func replaceLast(with step: Step, in state: State, reply: @Sendable (Reply) -> Void) throws(RetakeError) {
        state.document.steps[state.document.steps.count - 1] = step
        try state.document.write()
        reply(.changed(step, number: state.document.steps.count))
    }

    /// What's on screen once it has looked the same twice running, a quarter second apart, so an app
    /// still laying itself out after launch isn't shown half drawn; or after three seconds, as it is.
    @ButtonHeistActor
    static func settled(_ driver: some AppDriver, pause: @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) async throws(RetakeError) -> [ScreenElement] {
        var shown = try await driver.elements()
        for _ in 0..<12 {
            await pause(0.25)
            let now = try await driver.elements()
            if now == shown { break }
            shown = now
        }
        return shown
    }
}
