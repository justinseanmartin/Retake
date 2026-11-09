import Foundation
import TheScore

/// This Retake's version, and The Button Heist it's built against; see README.md, "The Button Heist,
/// and Retake's version pin".
public struct RetakeVersion: Codable, Equatable, Sendable {
    public struct ButtonHeist: Codable, Equatable, Sendable {
        /// The version The Button Heist reports, and its handshake compares: `0.7.1` for a release,
        /// with a contract hash appended (`0.7.1-d53fb59edbf3`) for a build between releases.
        public var version: String
        /// The commit of a local clone Retake was built from, ending in `-dirty` when it had
        /// uncommitted changes; nil for a release, which the version names exactly.
        public var commit: String?
        /// The local clone Retake was built from, when it was.
        public var clonePath: String?
    }

    public var version: String
    public var buttonHeist: ButtonHeist

    /// The version this Retake's schemas are published under: its release, without a pre-release
    /// suffix, so `0.0.1-dev` reads files written for `0.0.1`.
    public var schemaVersion: String {
        String(version.prefix { $0 != "-" })
    }

    public static let current = RetakeVersion(
        version: "0.0.1",
        buttonHeist: ButtonHeist(version: buttonHeistVersion.description, commit: nil, clonePath: nil),
    )

    /// This Retake's version, with the clone it was built from when it was: its path and commit, as
    /// `Scripts/fetch-insidejob.sh` recorded them when it built the clone's framework.
    public static func withClone(cache: URL = InsideJobFramework.defaultCache) -> RetakeVersion {
        var version = current
        if InsideJobFramework.isBuiltFromClone {
            let clone = InsideJobFramework.clone(in: cache)
            version.buttonHeist.clonePath = clone?.path ?? "a local clone"
            version.buttonHeist.commit = clone?.commit ?? "unknown; \(SourceCheckout.remedy()) with RETAKE_BUTTONHEIST_PATH set"
        }
        return version
    }
}
