// swift-tools-version:6.0
import Foundation
import PackageDescription

// TheInsideJob, and everything it depends on, as one dynamic framework to inject into apps, built
// from a local clone of The Button Heist for working on both together. Releases of Retake carry
// The Button Heist's own published framework instead; scripts/fetch-insidejob.sh builds this one
// only when RETAKE_BUTTONHEIST_PATH names a clone.
let clone = ProcessInfo.processInfo.environment["RETAKE_BUTTONHEIST_PATH"] ?? "../../TheButtonHeist"

let package = Package(
    name: "RetakeInsideJob",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "RetakeInsideJob", type: .dynamic, targets: ["RetakeInsideJob"]),
    ],
    dependencies: [
        .package(name: "TheButtonHeist", path: clone),
    ],
    targets: [
        .target(
            name: "RetakeInsideJob",
            dependencies: [.product(name: "TheInsideJob", package: "TheButtonHeist")],
        ),
    ],
)
