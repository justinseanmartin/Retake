import Foundation

/// Retake's support library, loaded into the app when Retake launches it, to set up a take before
/// the app's own code runs: its home for the set's state, and its defaults. Its source is in
/// Support/, and what Retake and it expect of each other is in Support/RetakeSupport.h.
public struct SupportLibrary: Equatable, Sendable {
    /// The contract version, as Support/RetakeSupport.h defines it; a test keeps the two equal.
    public static let contractVersion = 2

    /// The file name it's embedded under, in the app's `Frameworks/`.
    public static let fileName = "RetakeSupport.dylib"

    /// The library built for iOS devices.
    public var file: URL

    /// Where it's looked for, in order: beside the `retake` binary, as a release carries it
    /// (`share/retake/`), then where `Scripts/build-support.sh` builds it.
    public static func candidates(executable: URL, cache: URL = defaultCache) -> [URL] {
        let share = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "share/retake/\(fileName)")
        return [share, cache.appending(path: "\(contractVersion)/\(fileName)")]
    }

    /// The library, or an environment problem (3) saying how to build it.
    public static func locate(
        executable: URL = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
        cache: URL = defaultCache,
    ) throws(RetakeError) -> SupportLibrary {
        guard let file = candidates(executable: executable, cache: cache).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw RetakeError(.environment, "Retake's support library isn't built yet; \(SourceCheckout.remedy()).")
        }
        return SupportLibrary(file: file)
    }

    /// `~/Library/Caches/retake/support`.
    public static var defaultCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "retake/support", directoryHint: .isDirectory)
    }

    /// The environment that has the library set a take up from `set`, on a device of `type`, as
    /// Support/RetakeSupport.h describes it.
    public static func environment(for set: ResolvedSet, type: DeviceType, take: String) -> [String: String] {
        let defaults = JSONValue.object(JSONObject(set.defaults.map { JSONObject.Entry(key: $0.name, value: $0.value) }))
        var environment = [
            "RETAKE_STATE": set.state.rawValue,
            "RETAKE_TAKE": take,
            "RETAKE_DEFAULTS": JSONWriter.write(defaults).trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let appearance = set.appearance { environment["RETAKE_APPEARANCE"] = appearance.rawValue }
        if let aspect = set.aspect[type] {
            if let portrait = aspect.portrait { environment["RETAKE_ASPECT_PORTRAIT"] = portrait.description }
            if let landscape = aspect.landscapeShape { environment["RETAKE_ASPECT_LANDSCAPE"] = landscape.description }
        }
        return environment
    }

    /// The environment for a launch that only deletes takes' homes and staged files, then exits.
    public static let cleanupEnvironment = ["RETAKE_CLEANUP": "1"]

    /// Where the library writes its report, in the app's container.
    public static let reportPath = "tmp/RetakeLaunch/report.json"
    /// Where it writes the times the app's main thread missed frames.
    public static let hitchesPath = "tmp/RetakeLaunch/hitches.json"
}

/// What the support library reports at launch, from `tmp/RetakeLaunch/report.json`.
public struct LaunchReport: Equatable, Sendable {
    public var contract: Int
    public var take: String
    public var state: String
    public var cleanedUp: Bool
    /// How long the library took to set the take up.
    public var milliseconds: Double

    public init(contract: Int, take: String, state: String, cleanedUp: Bool = false, milliseconds: Double = 0) {
        self.contract = contract
        self.take = take
        self.state = state
        self.cleanedUp = cleanedUp
        self.milliseconds = milliseconds
    }

    public static func parse(_ data: Data) -> LaunchReport? {
        guard let value = try? JSONParser.parse(String(decoding: data, as: UTF8.self)),
              case .number(let contract)? = value[path: "contract"] else { return nil }
        var milliseconds = 0.0
        if case .number(let value)? = value[path: "milliseconds"] { milliseconds = value }
        return LaunchReport(
            contract: Int(contract),
            take: value[path: "take"]?.stringValue ?? "",
            state: value[path: "state"]?.stringValue ?? "",
            cleanedUp: value[path: "cleanedUp"] == .bool(true),
            milliseconds: milliseconds,
        )
    }

    /// That the report is the take's own, from a library speaking this Retake's contract; otherwise
    /// an environment problem (3), since the app needs embedding again, as Documentation/cli.md,
    /// "Compatibility with an embedded app", says.
    public func check(take expected: String) throws(RetakeError) {
        guard contract == SupportLibrary.contractVersion else {
            throw RetakeError(
                .environment,
                "The app was embedded by a Retake whose support library speaks contract \(contract), and this Retake's speaks "
                    + "\(SupportLibrary.contractVersion); embed it again with `retake embed` or `retake install`.",
            )
        }
        guard take == expected else {
            throw RetakeError(.environment, "The support library didn't report on this launch; embed the app again with `retake embed` or `retake install`.")
        }
    }
}
