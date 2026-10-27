// swift-tools-version:6.0
import Foundation
import PackageDescription

// Retake is built against exactly one release of The Button Heist. RETAKE_BUTTONHEIST_PATH builds it
// against a local clone instead, for changes that span both; see README.md, "Building from source".
let clonePath = ProcessInfo.processInfo.environment["RETAKE_BUTTONHEIST_PATH"].flatMap { $0.isEmpty ? nil : $0 }
let buttonHeist: Package.Dependency = if let path = clonePath {
    .package(name: "TheButtonHeist", path: path)
} else {
    .package(url: "https://github.com/TheButtonHeist/TheButtonHeist", exact: "0.7.1")
}

let package = Package(
    name: "Retake",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "retake", targets: ["retake"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        buttonHeist,
    ],
    targets: [
        .executableTarget(
            name: "retake",
            dependencies: ["RetakeCLI"],
        ),
        // The command line: each command's arguments, and how its outcome becomes an exit status.
        .target(
            name: "RetakeCLI",
            dependencies: [
                "RetakeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        // What the commands do, with no knowledge of how they're invoked.
        .target(
            name: "RetakeCore",
            dependencies: [.product(name: "TheScore", package: "TheButtonHeist")],
            // A build against a clone says so, in `retake version` and each take's metadata.
            swiftSettings: clonePath == nil ? [] : [.define("RETAKE_BUTTONHEIST_CLONE")],
        ),
        .testTarget(
            name: "RetakeCLITests",
            dependencies: ["RetakeCLI", "RetakeCore"],
        ),
        .testTarget(
            name: "RetakeCoreTests",
            dependencies: ["RetakeCore"],
        ),
    ],
)
