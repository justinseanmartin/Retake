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
        let set = try AppSession.set(setName, in: project, namedBy: project.displayPath(url))
        return (scene, set)
    }

    /// Launches the app on the scene's set, plays it, and deletes the take's copy of the app's data
    /// from the device at the end, whether or not every step ran.
    public static func run(_ name: String, in project: Project, on device: Device, from: Int, player: Player) async throws(RetakeError) {
        guard let type = device.type else {
            throw RetakeError(.environment, "Retake can't tell whether \(device.name) is an iPhone or an iPad.")
        }
        let (scene, set) = try scene(name, in: project, for: type)
        guard from <= scene.steps.count else {
            throw RetakeError(.usage, "--from \(from) is past \(name)'s last step, \(scene.steps.count).")
        }
        try await AppSession.run("rehearse-\(name)", in: project, set: set, scene: scene, on: device, report: player.report) { driver, _ throws(RetakeError) in
            try await player.play(scene, named: name, from: from, on: driver)
        }
    }
}
