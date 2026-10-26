import ArgumentParser
import Foundation
@testable import RetakeCLI
import RetakeCore
import Testing

/// `RETAKE_DEVICE`, `RETAKE_SIGNING_IDENTITY` and `RETAKE_PROVISIONING_PROFILE`, against their flags.
struct EnvironmentTests {
    @Test func theDeviceComesFromTheFlagThenTheEnvironment() throws {
        func chosen(_ arguments: [String], _ environment: [String: String]) throws -> DeviceChoice? {
            try DeviceOptions.parse(arguments).choice(configuration: nil, connected: [], environment: environment)
        }
        #expect(try chosen([], [:]) == nil)
        #expect(try chosen([], ["RETAKE_DEVICE": "ipad"]) == DeviceChoice(device: "ipad", source: .environment(variable: "RETAKE_DEVICE")))
        #expect(try chosen([], ["RETAKE_DEVICE": ""]) == nil)
        #expect(try chosen(["--device", "iphone"], ["RETAKE_DEVICE": "ipad"]) == DeviceChoice(device: "iphone", source: .commandLine))
    }

    @Test func signingKeepsTheAppsOwnUnlessToldOtherwise() throws {
        #expect(try SigningOptions.parse([]).overrides(environment: [:], currentDirectory: "/work") == SigningOverrides())
    }

    @Test func signingComesFromTheEnvironmentWhenNoFlagIsGiven() throws {
        let environment = [
            "RETAKE_SIGNING_IDENTITY": "113FA27578EC2A9F8FE26CA4032200503C8F331A",
            "RETAKE_PROVISIONING_PROFILE": "profiles/dev.mobileprovision",
        ]
        let overrides = try SigningOptions.parse([]).overrides(environment: environment, currentDirectory: "/work")
        #expect(overrides.identity == "113FA27578EC2A9F8FE26CA4032200503C8F331A")
        #expect(overrides.profile?.path == "/work/profiles/dev.mobileprovision")
    }

    @Test func eachSigningFlagWinsOnItsOwn() throws {
        let environment = ["RETAKE_SIGNING_IDENTITY": "From environment", "RETAKE_PROVISIONING_PROFILE": "/env.mobileprovision"]
        let overrides = try SigningOptions.parse(["--identity", "From flag"])
            .overrides(environment: environment, currentDirectory: "/work")
        #expect(overrides.identity == "From flag")
        #expect(overrides.profile?.path == "/env.mobileprovision")
    }
}
