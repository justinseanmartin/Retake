/// The kind of device a scene is written for and a video is rendered for, asked of the device itself.
/// It names the folders a command works in: `scenes/<type>/` and `RetakeOutput/takes/<type>/`.
public enum DeviceType: String, CaseIterable, Codable, Sendable {
    case iphone
    case ipad
}
