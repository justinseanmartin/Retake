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
    }

    public var version: String
    public var buttonHeist: ButtonHeist

    public static let current = RetakeVersion(
        version: "0.0.1-dev",
        buttonHeist: ButtonHeist(version: buttonHeistVersion.description, commit: nil),
    )
}
