import Foundation

/// Retake's support library, loaded into the app when Retake launches it, to set up a take before
/// the app's own code runs: its home for the set's state, and its defaults. Its source is in
/// Support/, and what Retake and it expect of each other is in Support/RetakeSupport.h.
public struct SupportLibrary: Equatable, Sendable {
    /// The contract version, as Support/RetakeSupport.h defines it; a test keeps the two equal.
    public static let contractVersion = 1

    /// The file name it's embedded under, in the app's `Frameworks/`.
    public static let fileName = "RetakeSupport.dylib"

    /// The library built for iOS devices.
    public var file: URL

    /// Where it's looked for, in order: beside the `retake` binary, as a release carries it
    /// (`share/retake/`), then where `scripts/build-support.sh` builds it.
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
            throw RetakeError(.environment, "Retake's support library isn't built yet; run scripts/build-support.sh.")
        }
        return SupportLibrary(file: file)
    }

    /// `~/Library/Caches/retake/support`.
    public static var defaultCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "retake/support", directoryHint: .isDirectory)
    }

    /// The environment that has the library set a take up from `set`, as Support/RetakeSupport.h
    /// describes it.
    public static func environment(for set: ResolvedSet, take: String) -> [String: String] {
        let defaults = JSONValue.object(JSONObject(set.defaults.map { JSONObject.Entry(key: $0.name, value: $0.value) }))
        return [
            "RETAKE_STATE": set.state.rawValue,
            "RETAKE_TAKE": take,
            "RETAKE_DEFAULTS": JSONWriter.write(defaults).trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }
}
