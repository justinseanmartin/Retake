import Foundation
import RetakeCore
import Testing

struct DeviceChoiceTests {
    let file = URL(filePath: "/work/Previews/retake.json")

    @Test func theCommandLineAndEnvironmentComeFirst() {
        let fromFlag = DeviceChoice.choose(named: ("iphone", nil), configuration: ("ipad", file), connected: ["A", "B"])
        #expect(fromFlag == DeviceChoice(device: "iphone", source: .commandLine))
        #expect(fromFlag?.reason == "from --device")

        let fromEnvironment = DeviceChoice.choose(named: ("iphone", "RETAKE_DEVICE"), configuration: ("ipad", file), connected: [])
        #expect(fromEnvironment?.source == .environment(variable: "RETAKE_DEVICE"))
        #expect(fromEnvironment?.reason == "from RETAKE_DEVICE")
    }

    @Test func thenTheConfigurationFileThenTheOneConnected() {
        let fromFile = DeviceChoice.choose(named: nil, configuration: ("ipad", file), connected: ["A"])
        #expect(fromFile?.device == "ipad")
        #expect(fromFile?.reason == "from retake.json")

        let onlyOne = DeviceChoice.choose(named: nil, configuration: nil, connected: ["00008103-0000000000000001"])
        #expect(onlyOne == DeviceChoice(device: "00008103-0000000000000001", source: .onlyConnected))
        #expect(onlyOne?.reason == "the only one connected")
    }

    @Test func noneOrSeveralConnectedChoosesNothing() {
        #expect(DeviceChoice.choose(named: nil, configuration: nil, connected: []) == nil)
        #expect(DeviceChoice.choose(named: nil, configuration: nil, connected: ["A", "B"]) == nil)
    }

    @Test func namingADeviceNotesAnEnvironmentThatNamesAnother() {
        let note = DeviceChoice.noteAfterNaming(
            alias: "phone", udid: "00008150-0000000000000002", name: "Sam’s iPhone",
            environmentDevice: ("ipad", "RETAKE_DEVICE"),
        )
        #expect(note == "Commands in this shell still use \"ipad\" (RETAKE_DEVICE); pass --device phone to use this one.")
    }

    @Test(arguments: ["phone", "00008150-0000000000000002", "Sam’s iPhone"])
    func namingTheDeviceTheEnvironmentNamesNeedsNoNote(_ environmentDevice: String) {
        #expect(DeviceChoice.noteAfterNaming(
            alias: "phone", udid: "00008150-0000000000000002", name: "Sam’s iPhone",
            environmentDevice: (environmentDevice, "RETAKE_DEVICE"),
        ) == nil)
        #expect(DeviceChoice.noteAfterNaming(
            alias: "phone", udid: "00008150-0000000000000002", name: "Sam’s iPhone", environmentDevice: nil,
        ) == nil)
    }
}
