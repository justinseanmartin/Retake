import Foundation

/// Everything one launch of the app for a take needs, worked out before anything touches the
/// device: what to copy to it, which way to turn it, and the launch environment and arguments.
public struct LaunchPlan: Equatable, Sendable {
    public var bundleID: String
    /// Names the take's home on the device, and the report the support library writes for it.
    public var take: String
    public var orientation: SceneFile.Orientation
    /// Files and folders to stage in the app's container: (from, to) pairs.
    public var staging: [Staged]
    public var environment: [String: String]
    public var arguments: [String]
    /// The port and token The Button Heist's server in the app listens with.
    public var port: Int
    public var token: String

    public struct Staged: Equatable, Sendable {
        /// The file or folder in the project.
        public var source: URL
        /// Where it goes in the app's container: `tmp/RetakeSet/Documents/notes.json`.
        public var destination: String
    }

    /// Where the Mac stages a set's files, in the app's container, for the support library.
    public static let stagingFolder = "tmp/RetakeSet"

    /// The libraries every launch inserts: the support library first, so a take is set up before
    /// The Button Heist's server starts in it.
    public static let insertedLibraries = "@executable_path/Frameworks/\(SupportLibrary.fileName):@executable_path/Frameworks/TheInsideJob.framework/TheInsideJob"

    /// The launch for `scene`'s take on `type`, from its resolved `set`: the set's environment,
    /// then the scene's on top, then Retake's own, which a set or scene can't name.
    public static func make(
        project: Project,
        set: ResolvedSet,
        scene: SceneFile,
        type: DeviceType,
        bundleID: String,
        take: String,
        port: Int = Int.random(in: 20000...60000),
        token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    ) -> LaunchPlan {
        var environment: [String: String] = [:]
        for variable in set.environment { environment[variable.name] = variable.value }
        environment.merge(SupportLibrary.environment(for: set, type: type, take: take)) { $1 }
        environment["DYLD_INSERT_LIBRARIES"] = insertedLibraries
        environment["INSIDEJOB_PORT"] = String(port)
        environment["INSIDEJOB_TOKEN"] = token
        // The Button Heist draws a fingerprint where it touches, which a recording would show.
        environment["INSIDEJOB_FINGERPRINTS"] = "false"
        let staging = set.files.map { copy in
            Staged(source: project.root.appending(path: copy.source), destination: "\(stagingFolder)/\(copy.destination)")
        }
        return LaunchPlan(
            bundleID: bundleID, take: take, orientation: scene.orientation, staging: staging,
            environment: environment, arguments: set.arguments, port: port, token: token,
        )
    }

    /// The launch environment as `devicectl` takes it: one JSON object.
    public var environmentJSON: String {
        let object = JSONObject(environment.keys.sorted().map { JSONObject.Entry(key: $0, value: .string(environment[$0]!)) })
        return JSONWriter.write(.object(object)).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// `devicectl device process launch`'s arguments, attached to the app's console so the
    /// connection to the device holds for the take. The app's own arguments come after `--`, or
    /// `devicectl` takes one such as `-AppleLocale` for its own `-l`.
    public func launchArguments(udid: String) -> [String] {
        ["devicectl", "device", "process", "launch", "--device", udid, "--terminate-existing", "--activate", "--console",
         "--environment-variables", environmentJSON, bundleID] + (arguments.isEmpty ? [] : ["--"] + arguments)
    }

    /// `devicectl`'s name for a scene's orientation.
    public static func devicectlName(_ orientation: SceneFile.Orientation) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        }
    }
}
