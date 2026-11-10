import Foundation
import RetakeCore
import Testing

extension OnDevice {
    /// The example, as someone starting with Retake would take it: `retake` itself, from installing
    /// the app to cutting its tour, for the test device's type. It works on a copy of the example's
    /// `Retake/` folder, since `cut` rewrites the edit, with its own output directory.
    @Suite struct EndToEndTests {
        /// The `retake` the tests were built with, beside their bundle.
        static var binary: URL? {
            if let path = ProcessInfo.processInfo.environment["RETAKE_TEST_BINARY"] { return URL(filePath: path) }
            let bundle = Bundle(for: Marker.self).bundleURL
            return bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent().appending(path: "retake") : nil
        }

        /// A class of the test bundle's own, to find the bundle by.
        private final class Marker {}

        struct Run {
            var status: Int32
            var output: String
        }

        static func retake(_ arguments: [String], environment: [String: String]) throws -> Run {
            let binary = try #require(binary, "set RETAKE_TEST_BINARY to the retake to run")
            let result = try Subprocess.run(binary.path, arguments, environment: environment)
            return Run(status: result.status, output: result.outputText + result.errorText)
        }

        @Test func theExampleGoesFromInstallToACut() throws {
            let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Example").standardizedFileURL
            let work = FileManager.default.temporaryDirectory.appending(path: "RetakeEndToEnd-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: work) }
            let project = work.appending(path: "Retake", directoryHint: .isDirectory)
            let output = work.appending(path: "output", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            for folder in ["retake.json", "sets", "scenes", "edits", "data"] {
                try FileManager.default.copyItem(at: example.appending(path: "Retake/\(folder)"), to: project.appending(path: folder))
            }
            let device = try ExampleOnDevice().device
            let type = try #require(device.type).rawValue
            // The copy's build would look for the Xcode project beside it, so install from the example.
            var environment = ["RETAKE_DEVICE": testDevice!, "RETAKE_OUTPUT_DIR": output.path]
            environment["RETAKE_CONFIG"] = example.appending(path: "Retake/retake.json").path
            let install = try Self.retake(["install"], environment: environment)
            #expect(install.status == 0, "\(install.output)")
            environment["RETAKE_CONFIG"] = project.appending(path: "retake.json").path

            for command in [["validate", "--offline"], ["record", "--for", "tour"], ["validate"], ["cut", "tour", "--type", type]] {
                let run = try Self.retake(command, environment: environment)
                try #require(run.status == 0, "retake \(command.joined(separator: " ")): \(run.output)")
            }

            let video = output.appending(path: "cuts/\(type)/tour/tour-\(type).mp4")
            let info = try Self.retake(["info", "--json", video.path], environment: environment)
            #expect(info.status == 0)
            let record = try JSONParser.parse(info.output)
            guard case .array(let movies) = record, case .object(let movie)? = movies.first, case .object(let fields)? = movie["video"] else {
                Issue.record("info printed no video: \(info.output)")
                return
            }
            #expect(fields["edit"] == .string("tour") && fields["deviceType"] == .string(type))

            let status = try Self.retake(["status", "--json"], environment: environment)
            #expect(status.output.contains("\"upToDate\": true"), "\(status.output)")
        }
    }
}
