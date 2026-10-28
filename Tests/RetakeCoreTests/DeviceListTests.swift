import Foundation
import RetakeCore
import Testing

/// `devicectl list devices`' JSON, captured from real devices with their names and identifiers
/// replaced (Fixtures/devicectl-list-devices.json).
struct DeviceListTests {
    func fixture() throws -> [Device] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/devicectl-list-devices.json")
        return try DeviceList.parse(try Data(contentsOf: url))
    }

    @Test func realDevicesAreReadAndSimulatorsLeftOut() throws {
        let devices = try fixture()
        #expect(devices.map(\.name) == ["Sam’s Other iPhone", "Sam’s Apple Watch", "Sam’s iPad", "Sam’s iPad (2)", "Sam’s iPhone"])
    }

    @Test func aWiredIPadIsRecordable() throws {
        let ipad = try #require(try fixture().first { $0.name == "Sam’s iPad (2)" })
        #expect(ipad == Device(
            udid: "00008103-0000000000000007",
            name: "Sam’s iPad (2)",
            type: .ipad,
            model: "iPad13,4",
            marketingName: "iPad Pro (11-inch) (3rd generation)",
            osVersion: "26.6.2",
            osBuild: "23G90",
            transport: .wired,
            state: .connected,
            isPaired: true,
            tunnelAddress: ipad.tunnelAddress,
        ))
        #expect(ipad.tunnelAddress != nil)
        #expect(ipad.isRecordable && ipad.osDescription == "26.6.2 (23G90)")
    }

    @Test func devicesOffUSBOrUnavailableArentRecordable() throws {
        let devices = try fixture()
        let byName = Dictionary(uniqueKeysWithValues: devices.map { ($0.name, $0) })
        #expect(byName["Sam’s iPhone"]?.transport == .network && byName["Sam’s iPhone"]?.state == .disconnected)
        #expect(byName["Sam’s iPad"]?.state == .unavailable && byName["Sam’s iPad"]?.type == .ipad)
        #expect(byName["Sam’s Apple Watch"]?.type == nil)
        #expect(devices.filter(\.isRecordable).map(\.name) == ["Sam’s iPad (2)"])
    }

    @Test func theOlderFieldsAreReadWhenTheNewOnesArentThere() throws {
        let json = #"""
            {"result": {"devices": [{
              "hardwareProperties": {"udid": "00008150-0000000000000001", "deviceType": "iPhone", "productType": "iPhone18,5",
                                     "marketingName": "iPhone 17e", "reality": "physical"},
              "deviceProperties": {"name": "Test iPhone", "osVersionNumber": "27.0", "osBuildUpdate": "24A100"},
              "connectionProperties": {"transportType": "wired", "tunnelState": "connected", "pairingState": "paired",
                                       "tunnelIPAddress": "fd00::1"}
            }]}}
            """#
        let devices = try DeviceList.parse(Data(json.utf8))
        #expect(devices == [Device(
            udid: "00008150-0000000000000001", name: "Test iPhone", type: .iphone, model: "iPhone18,5", marketingName: "iPhone 17e",
            osVersion: "27.0", osBuild: "24A100", transport: .wired, state: .connected, isPaired: true, tunnelAddress: "fd00::1",
        )])
    }

    @Test func outputThatIsntAListOfDevicesFails() {
        #expect(throws: DeviceList.Failure.self) { try DeviceList.parse(Data(#"{"result": {}}"#.utf8)) }
        #expect(throws: DeviceList.Failure.self) { try DeviceList.parse(Data("not json".utf8)) }
    }
}

struct ScreenPointsTests {
    @Test func theScreenIsItsNativeSizeOverItsPointScaleInPortrait() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/devicectl-displays-ipad.json")
        // devicectl gives the iPad's 2388×1668 pixels landscape first, at 2 pixels a point.
        #expect(Devicectl.screenPoints(fromDisplays: try Data(contentsOf: url)) == CGSize(width: 834, height: 1194))
        #expect(Devicectl.screenPoints(fromDisplays: Data(#"{"result": {"displays": []}}"#.utf8)) == nil)
    }
}
