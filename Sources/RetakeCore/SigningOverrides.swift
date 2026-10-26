import Foundation

/// What to sign an embedded app with in place of what it was signed with. Each field left nil keeps
/// the app's own: its identity is the certificate it was signed with, and its profile the
/// `embedded.mobileprovision` inside it.
public struct SigningOverrides: Equatable, Sendable {
    /// A signing identity, as `codesign -s` takes it: a certificate's SHA-1 or its name.
    public var identity: String?
    /// A provisioning profile, to embed as the app's `embedded.mobileprovision`.
    public var profile: URL?

    public init(identity: String? = nil, profile: URL? = nil) {
        self.identity = identity
        self.profile = profile
    }
}
