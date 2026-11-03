import Foundation
@testable import RetakeCore
import Testing

/// Saying how to build what Retake installs, from wherever it's run.
struct SourceCheckoutTests {
    @Test func aSourceBuildSaysToRunItsBuildScriptByItsFullPathAndAReleaseToReinstall() {
        #expect(SourceCheckout.remedy() == "run \(SourceCheckout.root.path)/Scripts/build.sh")
        #expect(SourceCheckout.remedy(root: URL(filePath: "/nowhere")) == "reinstall Retake")
    }
}
