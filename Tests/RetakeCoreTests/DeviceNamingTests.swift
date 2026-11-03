import Foundation
import RetakeCore
import Testing

struct DeviceNamingTests {
    struct Screens: CaptureDeviceFinder {
        var screens: [CaptureDevice]
        func captureDevices(waitingFor name: String?, timeout: Double) -> [CaptureDevice] { screens }
    }

    let ipad = Device(udid: "00008103-0000000000000001", name: "Sam’s iPad (2)", type: .ipad, model: "iPad13,4")
    let iphone = Device(udid: "00008150-0000000000000002", name: "Sam’s iPhone", type: .iphone, model: "iPhone18,5")
    let watch = Device(udid: "00008310-0000000000000003", name: "Sam’s Apple Watch", type: nil)
    let networked = Device(udid: "00008150-0000000000000004", name: "Sam’s Other iPhone", type: .iphone, transport: .network)
    let ipadScreen = CaptureDevice(name: "Sam’s iPad (2)", uniqueID: "28B5A844-0000-0000-0000-000000000001")
    let iphoneScreen = CaptureDevice(name: "Sam’s iPhone", uniqueID: "28B5A844-0000-0000-0000-000000000002")

    func status(_ body: () throws -> Void) -> RetakeCore.ExitStatus? {
        do {
            try body()
            return nil
        } catch {
            return (error as? RetakeError)?.status
        }
    }

    @Test func aDeviceMissingFromOneListingIsListedAgainBeforeFailing() throws {
        let named = DeviceAlias(name: "ipad", udid: ipad.udid, captureID: ipadScreen.uniqueID, deviceName: ipad.name, type: .ipad, model: nil)
        func listings(_ devices: [[Device]]) -> () throws(RetakeError) -> DeviceDirectory {
            var remaining = devices
            return { DeviceDirectory(devices: remaining.count > 1 ? remaining.removeFirst() : remaining[0], aliases: DeviceAliases([named])) }
        }
        var slept = 0.0
        // The alias's iPad, left out of the first two listings, as devicectl does now and then.
        let found = try DeviceDirectory.resolving(list: listings([[], [iphone], [ipad, iphone]]), choose: { _ in
            DeviceChoice(device: "ipad", source: .commandLine)
        }, sleep: { slept += $0 })
        #expect(found.device == ipad && slept == 1)
        // Nothing connected for longer than its patience fails as before, having waited it out.
        slept = 0
        #expect(status { _ = try DeviceDirectory.resolving(list: listings([[]]), choose: { _ in nil }, sleep: { slept += $0 }) } == .environment)
        #expect(slept == 3)
        // What isn't a device going missing, such as one on the network, fails at once.
        slept = 0
        #expect(status { _ = try DeviceDirectory.resolving(list: listings([[networked]]), choose: { _ in DeviceChoice(device: networked.udid, source: .commandLine) }, sleep: { slept += $0 }) } == .environment)
        #expect(slept == 0)
    }

    @Test func initOffersEachUnnamedRecordableDeviceItsTypeOrTheNextFree() {
        let otherIPad = Device(udid: "00008103-0000000000000005", name: "Sam’s Other iPad", type: .ipad)
        let named = DeviceAlias(name: "ipad", udid: ipad.udid, captureID: ipadScreen.uniqueID, deviceName: ipad.name, type: .ipad, model: nil)
        let directory = DeviceDirectory(devices: [ipad, otherIPad, iphone, watch, networked], aliases: DeviceAliases([named]))
        #expect(DeviceNaming.unnamed(in: directory).map(\.udid) == [otherIPad.udid, iphone.udid])
        #expect(DeviceNaming.suggestedName(for: otherIPad, besides: directory.aliases) == "ipad2")
        #expect(DeviceNaming.suggestedName(for: iphone, besides: directory.aliases) == "iphone")
        // Asked for another, the iPhone it was offered and skipped isn't offered again.
        #expect(DeviceNaming.newlyConnected(in: directory, besides: [iphone.udid]).map(\.udid) == [otherIPad.udid])
    }

    @Test func theOnlyConnectedDeviceIsNamedWithItsCaptureIdentity() throws {
        let directory = DeviceDirectory(devices: [ipad, watch, networked], aliases: DeviceAliases())
        let alias = try DeviceNaming.alias("ipad", for: nil, in: directory, finder: Screens(screens: [ipadScreen]))
        #expect(alias == DeviceAlias(name: "ipad", udid: ipad.udid, captureID: ipadScreen.uniqueID, deviceName: ipad.name, type: .ipad, model: "iPad13,4"))
    }

    @Test func aDeviceIsGivenByUDIDOrName() throws {
        let directory = DeviceDirectory(devices: [ipad, iphone], aliases: DeviceAliases())
        let screens = Screens(screens: [ipadScreen, iphoneScreen])
        #expect(try DeviceNaming.alias("phone", for: iphone.udid, in: directory, finder: screens).udid == iphone.udid)
        #expect(try DeviceNaming.alias("phone", for: "Sam’s iPhone", in: directory, finder: screens).captureID == iphoneScreen.uniqueID)
    }

    @Test func severalConnectedAreAskedAboutOrRefused() throws {
        let directory = DeviceDirectory(devices: [ipad, iphone], aliases: DeviceAliases())
        let screens = Screens(screens: [ipadScreen, iphoneScreen])
        var offered: [Device] = []
        let alias = try DeviceNaming.alias("phone", for: nil, in: directory, finder: screens) { devices in
            offered = devices
            return devices.last
        }
        #expect(offered == [ipad, iphone] && alias.udid == iphone.udid)
        #expect(status { _ = try DeviceNaming.alias("phone", for: nil, in: directory, finder: screens) } == .usage)
    }

    @Test func whatCantBeNamedSaysWhy() {
        let taken = DeviceAliases([DeviceAlias(name: "ipad", udid: ipad.udid, captureID: "x", deviceName: ipad.name, type: .ipad, model: nil)])
        let directory = DeviceDirectory(devices: [ipad, watch, networked], aliases: taken)
        let screens = Screens(screens: [ipadScreen])
        #expect(status { _ = try DeviceNaming.alias("ipad", for: nil, in: directory, finder: screens) } == .usage, "the alias is taken")
        #expect(status { _ = try DeviceNaming.alias("my ipad", for: nil, in: directory, finder: screens) } == .usage, "not a valid alias")
        #expect(status { _ = try DeviceNaming.alias("other", for: "ipad", in: directory, finder: screens) } == .usage, "an alias, not a device")
        #expect(status { _ = try DeviceNaming.alias("other", for: "Nobody’s iPad", in: directory, finder: screens) } == .usage)
        #expect(status { _ = try DeviceNaming.alias("w", for: watch.udid, in: directory, finder: screens) } == .environment)
        #expect(status { _ = try DeviceNaming.alias("n", for: networked.udid, in: directory, finder: screens) } == .environment)
        #expect(status { _ = try DeviceNaming.alias("n", for: nil, in: DeviceDirectory(devices: [watch], aliases: DeviceAliases()), finder: screens) } == .environment)
        #expect(status { _ = try DeviceNaming.alias("x", for: nil, in: DeviceDirectory(devices: [ipad], aliases: DeviceAliases()), finder: Screens(screens: [])) } == .environment, "not offered for capture")
    }

    @Test func aliasesAreSavedAndReadBack() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "RetakeAliases-\(UUID().uuidString)/retake/devices.json")
        #expect(try DeviceAliases.load(from: file) == DeviceAliases(), "no file is no aliases")
        let aliases = DeviceAliases([
            DeviceAlias(name: "ipad", udid: ipad.udid, captureID: ipadScreen.uniqueID, deviceName: ipad.name, type: .ipad, model: "iPad13,4"),
            DeviceAlias(name: "phone", udid: iphone.udid, captureID: iphoneScreen.uniqueID, deviceName: iphone.name, type: .iphone, model: nil),
        ])
        try aliases.save(to: file)
        #expect(try DeviceAliases.load(from: file) == aliases)
    }
}

struct DeviceDirectoryTests {
    let ipad = Device(udid: "00008103-0000000000000001", name: "Sam’s iPad (2)", type: .ipad)
    let iphone = Device(udid: "00008150-0000000000000002", name: "Sam’s iPhone", type: .iphone)
    let away = Device(udid: "00008150-0000000000000003", name: "Sam’s Other iPhone", type: .iphone, state: .disconnected)

    var directory: DeviceDirectory {
        DeviceDirectory(devices: [ipad, iphone, away], aliases: DeviceAliases([
            DeviceAlias(name: "tablet", udid: ipad.udid, captureID: "c", deviceName: ipad.name, type: .ipad, model: nil),
            DeviceAlias(name: "old", udid: "gone", captureID: "c", deviceName: "Retired iPad", type: .ipad, model: nil),
            DeviceAlias(name: "away", udid: away.udid, captureID: "c", deviceName: away.name, type: .iphone, model: nil),
        ]))
    }

    /// The UDID the device resolves to, or the status it fails with.
    func resolve(_ device: String?) -> String {
        let choice = device.map { DeviceChoice(device: $0, source: .commandLine) }
        do {
            return try directory.resolve(choice).udid
        } catch {
            return "fails \(error.status.rawValue)"
        }
    }

    @Test func aliasesUDIDsAndNamesAllFindTheirDevice() {
        #expect(resolve("tablet") == ipad.udid)
        #expect(resolve(iphone.udid) == iphone.udid)
        #expect(resolve("Sam’s iPhone") == iphone.udid)
    }

    @Test func whatCantBeUsedSaysWhy() {
        #expect(resolve("nobody") == "fails 2")
        #expect(resolve("old") == "fails 3", "an alias for a device that isn't connected")
        #expect(resolve("away") == "fails 3")
        #expect(resolve(nil) == "fails 3", "several connected, none chosen")
        #expect(throws: RetakeError.self) { try DeviceDirectory(devices: [], aliases: DeviceAliases()).resolve(nil) }
    }
}
