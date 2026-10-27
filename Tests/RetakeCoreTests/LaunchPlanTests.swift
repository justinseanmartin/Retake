import Foundation
import RetakeCore
import Testing

struct LaunchPlanTests {
    let project = Project(configuration: URL(filePath: "/work/Previews/retake.json"))

    func plan(set: ResolvedSet, scene: SceneFile = SceneFile(steps: [Step(nil, hold: 1)])) -> LaunchPlan {
        LaunchPlan.make(project: project, set: set, scene: scene, type: .ipad, bundleID: "com.example.notes", take: "create-note-3", port: 31000, token: "secret")
    }

    @Test func theEnvironmentIsTheSetsThenTheScenesThenRetakes() {
        let set = ResolvedSet(name: "base", environment: [Named("MODE", "set"), Named("REGION", "neutral")])
        let scene = SceneFile(environment: [Named("MODE", "scene")], steps: [Step(nil, hold: 1)])
        let environment = plan(set: set, scene: scene).environment
        #expect(environment["MODE"] == "scene" && environment["REGION"] == "neutral")
        #expect(environment["RETAKE_STATE"] == "clean" && environment["RETAKE_TAKE"] == "create-note-3")
        #expect(environment["DYLD_INSERT_LIBRARIES"] == "@executable_path/Frameworks/RetakeSupport.dylib:@executable_path/Frameworks/TheInsideJob.framework/TheInsideJob")
        #expect(environment["INSIDEJOB_PORT"] == "31000" && environment["INSIDEJOB_TOKEN"] == "secret")
        #expect(environment["INSIDEJOB_FINGERPRINTS"] == "false")
    }

    @Test func theSetsFilesAreStagedWhereTheLibraryLooks() {
        let set = ResolvedSet(name: "a", files: [
            SetFile.FileCopy(destination: "Documents/notes.json", source: "data/notes.json"),
            SetFile.FileCopy(destination: "Library/Media/", source: "data/media/"),
        ])
        let staging = plan(set: set).staging
        #expect(staging.map(\.destination) == ["tmp/RetakeSet/Documents/notes.json", "tmp/RetakeSet/Library/Media/"])
        #expect(staging.map(\.source.path) == ["/work/Previews/data/notes.json", "/work/Previews/data/media"])
    }

    @Test func devicectlLaunchesAttachedWithTheSetsArguments() throws {
        let set = ResolvedSet(name: "a", arguments: ["-AppleLanguages", "(en)"])
        let launch = plan(set: set)
        let arguments = launch.launchArguments(udid: "00008103-1")
        #expect(arguments.prefix(9) == ["devicectl", "device", "process", "launch", "--device", "00008103-1", "--terminate-existing", "--activate", "--console"])
        #expect(arguments.suffix(4) == ["com.example.notes", "--", "-AppleLanguages", "(en)"], "devicectl would read -AppleLocale as its own -l")
        #expect(plan(set: ResolvedSet(name: "b")).launchArguments(udid: "u").last == "com.example.notes")
        let json = try #require(arguments.firstIndex(of: "--environment-variables").map { arguments[$0 + 1] })
        guard case .object(let object) = try JSONParser.parse(json) else {
            Issue.record("the environment isn't an object")
            return
        }
        #expect(object["RETAKE_TAKE"] == .string("create-note-3"))
        #expect(!json.contains("\n"), "devicectl takes it as one argument")
    }

    @Test func orientationsAreNamedAsDevicectlNamesThem() {
        #expect(SceneFile.Orientation.allCases.map(LaunchPlan.devicectlName) == ["portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight"])
    }
}
