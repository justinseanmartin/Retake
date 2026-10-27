import ButtonHeist
import Foundation

/// The app launched on a set and driven for one command, `rehearse` or `inspect`, then cleaned up
/// after: the take's copy of the app's data is deleted from the device at the end, however the
/// command ended.
public enum AppSession {
    /// A set by name, with what it extends under it: a misuse (2) when it doesn't exist, naming
    /// `namedBy`, the file or option that named it, and a failure (1) when a file is wrong.
    public static func set(_ name: String, in project: Project, namedBy: String) throws(RetakeError) -> ResolvedSet {
        let files = ProjectFiles(project: project)
        guard FileManager.default.fileExists(atPath: files.setURL(name).path) else {
            let others = files.names(in: project.sets)
            throw RetakeError(
                .usage,
                "\(namedBy): there's no set \"\(name)\" (\(project.displayPath(files.setURL(name))))"
                    + (others.isEmpty ? "." : "; there's \(others.joined(separator: ", ")).")
            )
        }
        let report = ProjectFiles.Report()
        guard let set = files.resolveSet(name, into: report) else { throw report.error }
        return set
    }

    /// Launches the app on `set` for `scene`'s take, connects to it, and runs `body` with a driver
    /// for it. A launch whose app is never reached is tried once more; once `body` has started, a
    /// failure is final. Then, unless the set is `live`, launches the app once more to delete the
    /// take's copy of its data; if that fails after `body` failed, it's only a warning.
    /// The app's console goes to a temporary folder, since neither command writes in the project.
    public static func run(
        _ purpose: String,
        in project: Project,
        set: ResolvedSet,
        scene: SceneFile,
        on device: Device,
        report: @escaping @Sendable (Player.Event) -> Void,
        _ body: @ButtonHeistActor (ButtonHeistDriver) async throws(RetakeError) -> Void,
    ) async throws(RetakeError) {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let bundleID = try Installer.bundleID(for: project)
        report(.launching(set: set.name, state: set.state))
        let logs = FileManager.default.temporaryDirectory.appending(path: "retake-\(purpose)-\(UUID().uuidString.prefix(8))")

        var outcome: RetakeError?
        for attempt in 1...2 {
            let take = "\(purpose)-\(UUID().uuidString.prefix(6).lowercased())"
            let plan = LaunchPlan.make(project: project, set: set, scene: scene, type: type, bundleID: bundleID, take: take)
            let started = Started()
            do throws(RetakeError) {
                let app = try Launcher.launch(plan, on: device, logs: logs)
                defer { app.stop() }
                try await ButtonHeistDriver.withApp(app) { driver throws(RetakeError) in
                    started.value = true
                    try await body(driver)
                }
                outcome = nil
            } catch {
                outcome = error
            }
            // Only a launch that never reached the app is tried again.
            guard let failure = outcome, failure.status == .environment, !started.value, attempt == 1 else { break }
            report(.note("\(failure.message) Launching the app again."))
        }

        if set.state != .live {
            do {
                try Launcher.cleanUp(bundleID: bundleID, on: device)
            } catch where outcome == nil {
                outcome = error
            } catch {
                report(.warning("\(error.message) Run `retake clean --on-device` to delete what's left."))
            }
        }
        if let outcome { throw outcome }
    }

    /// Whether `body` began, which a connection failure can't have come after. Set on The Button
    /// Heist's actor and read once its session has ended.
    final class Started: @unchecked Sendable {
        var value = false
    }
}
