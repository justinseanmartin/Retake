import Foundation

/// The TheInsideJob framework Retake embeds in apps: The Button Heist's own release build, of the
/// version Retake's client is built against, or one built from the local clone a Retake built
/// from a clone uses. See README.md, "The Button Heist, and Retake's version pin".
public struct InsideJobFramework: Equatable, Sendable {
    /// The `.xcframework`.
    public var bundle: URL
    /// The version its `VERSION` file names.
    public var version: String

    /// Its slice for iOS devices, `ios-arm64/TheInsideJob.framework`.
    public var deviceFramework: URL {
        bundle.appending(path: "ios-arm64/TheInsideJob.framework", directoryHint: .isDirectory)
    }

    /// Where a framework is looked for, in order: beside the `retake` binary, as a release
    /// carries it (`share/retake/`); the clone's build, for a Retake built from a clone; and the
    /// cache `Scripts/fetch-insidejob.sh` fills.
    public static func candidates(executable: URL, cache: URL = defaultCache, builtFromClone: Bool = isBuiltFromClone) -> [URL] {
        let share = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "share/retake/TheInsideJob.xcframework", directoryHint: .isDirectory)
        let cached = builtFromClone
            ? cache.appending(path: "clone/TheInsideJob.xcframework", directoryHint: .isDirectory)
            : cache.appending(path: "\(RetakeVersion.current.buttonHeist.version)/TheInsideJob.xcframework", directoryHint: .isDirectory)
        return [share, cached]
    }

    /// The framework for this Retake, or an environment problem (3) saying how to get it.
    public static func locate(
        executable: URL = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
        cache: URL = defaultCache,
        builtFromClone: Bool = isBuiltFromClone,
        expectedVersion: String = RetakeVersion.current.buttonHeist.version,
    ) throws(RetakeError) -> InsideJobFramework {
        for bundle in candidates(executable: executable, cache: cache, builtFromClone: builtFromClone) {
            guard let data = FileManager.default.contents(atPath: bundle.appending(path: "VERSION").path) else { continue }
            let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let framework = InsideJobFramework(bundle: bundle, version: version)
            guard version == expectedVersion else {
                throw RetakeError(
                    .environment,
                    "\(bundle.path) is TheInsideJob \(version), but this Retake is built against \(expectedVersion); "
                        + "run Scripts/fetch-insidejob.sh to replace it.",
                )
            }
            guard FileManager.default.fileExists(atPath: framework.deviceFramework.path) else {
                throw RetakeError(.environment, "\(bundle.path) has no framework for iOS devices (ios-arm64).")
            }
            return framework
        }
        throw RetakeError(
            .environment,
            builtFromClone
                ? "There's no TheInsideJob built from the clone yet; run Scripts/fetch-insidejob.sh with RETAKE_BUTTONHEIST_PATH set."
                : "TheInsideJob \(expectedVersion) isn't here yet; run Scripts/fetch-insidejob.sh to download it.",
        )
    }

    /// `~/Library/Caches/retake/insidejob`.
    public static var defaultCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "retake/insidejob", directoryHint: .isDirectory)
    }

    public static var isBuiltFromClone: Bool {
        #if RETAKE_BUTTONHEIST_CLONE
        true
        #else
        false
        #endif
    }

    /// The clone the framework was built from, as `Scripts/fetch-insidejob.sh` recorded it.
    public struct Clone: Equatable, Sendable {
        public var path: String
        /// Its commit, ending in `-dirty` when it had uncommitted changes.
        public var commit: String

        public init(path: String, commit: String) {
            self.path = path
            self.commit = commit
        }
    }

    public static func clone(in cache: URL = defaultCache) -> Clone? {
        guard let data = FileManager.default.contents(atPath: cache.appending(path: "clone/clone.json").path),
              let value = try? JSONParser.parse(String(decoding: data, as: UTF8.self)),
              let path = value[path: "path"]?.stringValue, let commit = value[path: "commit"]?.stringValue else { return nil }
        return Clone(path: path, commit: commit)
    }
}
