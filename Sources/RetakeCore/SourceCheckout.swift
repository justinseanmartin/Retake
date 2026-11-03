import Foundation

/// The checkout a Retake was built from, for saying how to build what it installs. A released
/// Retake carries all of that beside it, in `share/retake/`, and its checkout was the release
/// machine's, so it isn't here.
enum SourceCheckout {
    /// The checkout's root, as this file's path said when Retake was built.
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// What to do: run the checkout's `Scripts/build.sh`, by its full path, so it's clear from any
    /// directory; or, where the checkout isn't here, reinstall Retake.
    static func remedy(root: URL = root) -> String {
        let script = root.appending(path: "Scripts/build.sh")
        return FileManager.default.isExecutableFile(atPath: script.path) ? "run \(script.path)" : "reinstall Retake"
    }
}
