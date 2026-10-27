import Foundation
import RetakeCore
import Testing

struct DoctorTests {
    let udid = "00008103-0000000000000001"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let signer = "0123456789ABCDEF0123456789ABCDEF01234567"

    func profile(_ appID: String, development: Bool = true, devices: [String]? = nil, expires: TimeInterval = 86_400, certificates: [String]? = nil) -> Doctor.Profile {
        Doctor.Profile(
            name: appID, appID: appID, isDevelopment: development, devices: devices ?? [udid],
            expires: now.addingTimeInterval(expires), certificates: certificates ?? [signer],
        )
    }

    var identities: [Doctor.Identity] { [Doctor.Identity(sha1: signer, name: "Apple Development: Sam (ABCDE12345)")] }

    @Test func identitiesAreReadFromSecuritysListing() {
        let output = """
              1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Sam (ABCDE12345)"
              2) 89abcdef0123456789abcdef0123456789abcdef "iPhone Distribution: Sam (FGHIJ67890)"
                 2 valid identities found
            """
        let read = Doctor.identities(fromFindIdentity: output)
        #expect(read.map(\.sha1) == [signer, "89ABCDEF0123456789ABCDEF0123456789ABCDEF"])
        #expect(read.map(\.isDevelopment) == [true, false])
    }

    @Test func aProfileIsReadFromItsContentsWithItsCertificatesHashed() throws {
        let certificate = Data("certificate".utf8)
        let read = try #require(Doctor.Profile([
            "Name": "iOS Team Provisioning Profile: *",
            "Entitlements": ["application-identifier": "FGHIJ67890.*", "get-task-allow": true],
            "ProvisionedDevices": [udid], "ExpirationDate": now, "Platform": ["iOS", "xrOS"],
            "DeveloperCertificates": [certificate],
        ]))
        #expect(read.appID == "*" && read.isDevelopment && read.devices == [udid] && read.isForIOS && read.expires == now)
        #expect(read.certificates == ["735AD571C189D7BA84464BF4A9F1D2280175B128"], "the certificate's SHA-1, as security lists identities by")
        #expect(Doctor.Profile(["Name": "no app ID"]) == nil)
    }

    @Test func anAppIDCoversItsBundleIDOrByWildcard() {
        #expect(profile("com.example.notes").covers("com.example.notes"))
        #expect(profile("com.example.*").covers("com.example.notes"))
        #expect(profile("*").covers("com.example.notes"))
        #expect(!profile("com.example.*").covers("com.other.notes"))
        #expect(!profile("com.example").covers("com.example.notes"))
    }

    @Test func theCoveringProfileIsTheMostSpecificThenTheLatest() {
        let profiles = [profile("*", expires: 9_000_000), profile("com.example.notes", expires: 1000), profile("com.example.notes", expires: 2000)]
        let (chosen, _) = Doctor.covering(profiles, bundleID: "com.example.notes", udid: udid, identities: identities, now: now)
        #expect(chosen == profiles[2])
    }

    @Test(arguments: [
        ("store", "No development provisioning profile is for com.example.notes."),
        ("expired", "Every development profile for com.example.notes has expired."),
        ("other device", "No development profile for com.example.notes includes the device, 00008103-0000000000000001; it may not be registered on the team."),
        ("other signer", "No profile for com.example.notes and the device is for a signing identity in the keychain."),
    ])
    func whyNoProfileCoversIsSaid(_ case: String, _ why: String) {
        let only = switch `case` {
        case "store": profile("com.example.notes", development: false)
        case "expired": profile("com.example.notes", expires: -1)
        case "other device": profile("com.example.notes", devices: ["00008150-0000000000000002"])
        default: profile("com.example.notes", certificates: ["0000000000000000000000000000000000000000"])
        }
        let result = Doctor.covering([only], bundleID: "com.example.notes", udid: udid, identities: identities, now: now)
        #expect(result.profile == nil && result.why == why)
    }

    @Test func doctorEndsWithTheFirstFailuresStatus() {
        let passed = Doctor.Check("tools", .passed, "")
        #expect(Doctor.status(of: [passed, Doctor.Check("signing", .warned, "")]) == .done)
        let failures = [
            Doctor.Check("device", .failed, "", status: .environment), Doctor.Check("app", .failed, "", status: .usage),
            Doctor.Check.skipped("launch", needing: "the app installed"),
        ]
        #expect(Doctor.status(of: [passed] + failures) == .environment)
        #expect(Doctor.Check("app", .failed, "").status == .failed, "a failure with no status of its own fails (1)")
    }
}
