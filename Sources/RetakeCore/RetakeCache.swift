import CryptoKit
import Foundation

/// `~/Library/Caches/retake/`: what each person's Retake keeps for itself, outside any project.
/// See Documentation/cli.md, "Files Retake writes".
public enum RetakeCache {
    public static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "retake", directoryHint: .isDirectory)
    }

    /// A folder for `project` in `builds/`, named for the project's folder, the one holding it, and
    /// a hash of its path, so two projects, or two clones of one, never share one.
    public static func builds(for project: Project, in root: URL = root) -> URL {
        let folders = project.root.standardizedFileURL.pathComponents.filter { $0 != "/" }.suffix(2)
        let hash = SHA256.hash(data: Data(project.root.standardizedFileURL.path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return root.appending(path: "builds/\((folders + [hash]).joined(separator: "-"))", directoryHint: .isDirectory)
    }
}
