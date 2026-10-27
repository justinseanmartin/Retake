import ButtonHeist
import Foundation

/// Playing a scene on a device without recording it. See docs/cli.md, "retake rehearse".
public enum Rehearsal {
    /// The scene `name` for the device's type, and the set it starts on: a misuse (2) when either
    /// doesn't exist, and a failure (1) when either file is wrong.
    public static func scene(_ name: String, in project: Project, for type: DeviceType) throws(RetakeError) -> (scene: SceneFile, set: ResolvedSet) {
        let files = ProjectFiles(project: project)
        let url = files.sceneURL(name, for: type)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let others = files.names(in: project.scenes(for: type))
            throw RetakeError(
                .usage,
                "There's no \(type.rawValue) scene \"\(name)\" (\(project.displayPath(url)))"
                    + (others.isEmpty ? "." : "; there's \(others.joined(separator: ", ")).")
            )
        }
        let report = ProjectFiles.Report()
        guard let scene = files.readScene(name, for: type, into: report) else { throw report.error }
        guard let setName = scene.set ?? project.settings.defaultSet else {
            throw RetakeError(
                .usage,
                "\(project.displayPath(url)) names no set, and \(project.configuration.lastPathComponent) has no defaultSet.",
            )
        }
        guard FileManager.default.fileExists(atPath: files.setURL(setName).path) else {
            throw RetakeError(.usage, "\(project.displayPath(url)): there's no set \"\(setName)\" (\(project.displayPath(files.setURL(setName)))).")
        }
        guard let set = files.resolveSet(setName, into: report) else { throw report.error }
        return (scene, set)
    }

    /// Launches the app on the scene's set, plays it, and deletes the take's copy of the app's data
    /// from the device at the end, whether or not every step ran. A launch whose app can't be
    /// reached is tried once more. The app's console goes to a temporary folder, since rehearsing
    /// writes nothing in the project.
    public static func run(_ name: String, in project: Project, on device: Device, from: Int, player: Player) async throws(RetakeError) {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let (scene, set) = try scene(name, in: project, for: type)
        guard from <= scene.steps.count else {
            throw RetakeError(.usage, "--from \(from) is past \(name)'s last step, \(scene.steps.count).")
        }
        let bundleID = try Installer.bundleID(for: project)
        player.report(.launching(set: set.name, state: set.state))
        let logs = FileManager.default.temporaryDirectory.appending(path: "retake-rehearse-\(UUID().uuidString.prefix(8))")

        var outcome: RetakeError?
        for attempt in 1...2 {
            let take = "rehearse-\(name)-\(UUID().uuidString.prefix(6).lowercased())"
            let plan = LaunchPlan.make(project: project, set: set, scene: scene, type: type, bundleID: bundleID, take: take)
            let started = Started()
            do throws(RetakeError) {
                let app = try Launcher.launch(plan, on: device, logs: logs)
                defer { app.stop() }
                try await ButtonHeistDriver.withApp(app) { driver throws(RetakeError) in
                    started.value = true
                    try await player.play(scene, named: name, from: from, on: driver)
                }
                outcome = nil
            } catch {
                outcome = error
            }
            // Only a launch that never reached the app is tried again.
            guard let failure = outcome, failure.status == .environment, !started.value, attempt == 1 else { break }
            player.report(.note("\(failure.message) Launching the app again."))
        }

        if set.state != .live {
            do {
                try Launcher.cleanUp(bundleID: bundleID, on: device)
            } catch where outcome == nil {
                outcome = error
            } catch {
                player.report(.warning("\(error.message) Run `retake clean --on-device` to delete what's left."))
            }
        }
        if let outcome { throw outcome }
    }

    /// Whether playing began, which a connection failure can't have come after. Set on The
    /// Button Heist's actor and read once its session has ended.
    final class Started: @unchecked Sendable {
        var value = false
    }
}
