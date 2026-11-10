import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The stills a scene's `capture` steps take, as `record` keeps them: for each device type, in
/// `output/captures/<type>/<scene>/`, `<name>.png` for each. Taken into `<scene>.recording/` first,
/// they replace the scene's captures only once every step has run. See README.md, "Captures".
public enum CaptureStore {
    /// What follows the scene in the name of its folder of captures still being taken.
    static let recordingSuffix = ".recording"

    /// The scene's captures.
    public static func folder(of scene: String, for type: DeviceType, in project: Project) -> URL {
        project.captures(for: type).appending(path: scene, directoryHint: .isDirectory)
    }

    /// Where a recording of the scene takes its captures, until they're kept.
    static func recording(of scene: String, in root: URL) -> URL {
        root.appending(path: scene + recordingSuffix, directoryHint: .isDirectory)
    }

    static func discardRecording(of scene: String, in root: URL) {
        try? FileManager.default.removeItem(at: recording(of: scene, in: root))
    }

    /// The captures just taken, in place of those the scene had; none taken leaves none.
    static func keepRecording(of scene: String, in root: URL) throws {
        let files = FileManager.default
        let kept = root.appending(path: scene, directoryHint: .isDirectory), taken = recording(of: scene, in: root)
        if files.fileExists(atPath: kept.path) { try files.removeItem(at: kept) }
        if files.fileExists(atPath: taken.path) { try files.moveItem(at: taken, to: kept) }
    }

    /// Each capture in `folder`, by name, with its size, in order of name.
    public static func captures(in folder: URL) -> [(name: String, width: Int, height: Int)] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") && !$0.hasPrefix(".") }.sorted()
        return names.compactMap { name in
            guard let source = CGImageSourceCreateWithURL(folder.appending(path: name) as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            return (String(name.dropLast(4)), width, height)
        }
    }

    /// The scenes with captures kept for a device type, by name.
    public static func scenes(for type: DeviceType, in project: Project) -> [String] {
        let root = project.captures(for: type)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var folder: ObjCBool = false
            return !name.hasPrefix(".") && !name.hasSuffix(recordingSuffix)
                && FileManager.default.fileExists(atPath: root.appending(path: name).path, isDirectory: &folder) && folder.boolValue
        }.sorted()
    }
}

/// A frame of the device's screen, as the capture stream sent it.
public struct ScreenFrame: @unchecked Sendable {
    public var pixels: CVPixelBuffer
}

/// A still: a PNG with no alpha channel, which App Store Connect refuses in a screenshot.
public enum Still {
    /// A frame from the stream, in sRGB. The stream's frames are tagged as video, with Rec. 709's
    /// primaries, which are sRGB's, and sRGB's curve, so converting changes nothing but the tag,
    /// which image tools read more readily than a video's.
    public static func png(_ pixels: CVPixelBuffer, context: CIContext) throws(RetakeError) -> (data: Data, width: Int, height: Int) {
        let image = CIImage(cvPixelBuffer: pixels)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let rendered = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else {
            throw RetakeError(.failed, "Couldn't make a still of the screen's \(Int(image.extent.width))×\(Int(image.extent.height)) frame.")
        }
        return try opaque(rendered, in: space)
    }

    /// A screenshot the device took, as a PNG, without its alpha channel, in its own color space,
    /// and facing as `frame`, the stream's frame of the same screen, does. Just after a turn, the
    /// device can take its screenshot as if it still faced the old way, a landscape screen turned
    /// a quarter into a portrait picture, so it's turned whichever way matches the stream's.
    public static func png(screenshot data: Data, facingAs frame: CVPixelBuffer?, context: CIContext) throws(RetakeError) -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RetakeError(.failed, "The device's screenshot isn't an image that can be read.")
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if let frame, let streamed = context.createCGImage(CIImage(cvPixelBuffer: frame), from: CIImage(cvPixelBuffer: frame).extent) {
            image = try upright(image, like: streamed, in: space)
        }
        return try opaque(image, in: space)
    }

    /// Quarter turns clockwise, in the order they're tried.
    static let turns = [0, 2, 1, 3]

    /// `image` turned by whichever quarter turns make it look most like `reference`, of those that
    /// give it the reference's shape.
    static func upright(_ image: CGImage, like reference: CGImage, in space: CGColorSpace) throws(RetakeError) -> CGImage {
        let referenceIsLandscape = reference.width > reference.height
        let candidates = turns.filter { ((image.width > image.height) != ($0 % 2 == 1)) == referenceIsLandscape }
        let target = thumbnail(reference, turns: 0)
        guard let best = candidates.min(by: { difference(thumbnail(image, turns: $0), target) < difference(thumbnail(image, turns: $1), target) }), best != 0 else {
            return image
        }
        return try turned(image, quarters: best, in: space)
    }

    /// The image turned `quarters` quarter turns clockwise.
    static func turned(_ image: CGImage, quarters: Int, in space: CGColorSpace) throws(RetakeError) -> CGImage {
        let sideways = quarters % 2 == 1
        let width = sideways ? image.height : image.width, height = sideways ? image.width : image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RetakeError(.failed, "Couldn't turn the device's \(image.width)×\(image.height) screenshot.") }
        // Core Graphics turns counterclockwise with its origin at the bottom left.
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(quarters) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let made = context.makeImage() else { throw RetakeError(.failed, "Couldn't turn the device's \(image.width)×\(image.height) screenshot.") }
        return made
    }

    /// Side of the gray thumbnails pictures are compared at, squeezed square.
    static let thumbnailSide = 32

    /// The image turned `turns` quarter turns clockwise and squeezed into a small gray square.
    static func thumbnail(_ image: CGImage, turns: Int) -> [UInt8] {
        let side = thumbnailSide
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .medium
            context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
            context.rotate(by: -CGFloat(turns) * .pi / 2)
            context.draw(image, in: CGRect(x: -CGFloat(side) / 2, y: -CGFloat(side) / 2, width: CGFloat(side), height: CGFloat(side)))
        }
        return pixels
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }

    static func opaque(_ image: CGImage, in space: CGColorSpace) throws(RetakeError) -> (data: Data, width: Int, height: Int) {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw RetakeError(.failed, "Couldn't make a \(width)×\(height) still.") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let opaque = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RetakeError(.failed, "Couldn't make a \(width)×\(height) still.")
        }
        CGImageDestinationAddImage(destination, opaque, nil)
        guard CGImageDestinationFinalize(destination) else { throw RetakeError(.failed, "Couldn't write a \(width)×\(height) still as a PNG.") }
        return (data as Data, width, height)
    }
}

/// The captures one recording of a scene takes, into its folder of captures being recorded: each a
/// screenshot the device takes, at its screen's own resolution, while its screen is open for
/// recording, so its status bar is the one recording shows; or, when the device can't take one,
/// the stream's last frame, which on some iPads is smaller than the screen.
final class CaptureTaker: @unchecked Sendable {
    let scene: String
    let folder: URL
    let project: Project
    let report: @Sendable (Player.Event) -> Void
    /// Saves a screenshot of the device's screen to the URL; nil takes the stream's frame alone.
    let screenshot: (@Sendable (URL) throws(RetakeError) -> Void)?
    private let context = CIContext()
    private let lock = NSLock()
    private var sizes: [Size] = []

    struct Size: Equatable, Hashable, Sendable {
        var width: Int
        var height: Int
    }

    init(
        scene: String, folder: URL, project: Project, report: @escaping @Sendable (Player.Event) -> Void,
        screenshot: (@Sendable (URL) throws(RetakeError) -> Void)?,
    ) {
        self.scene = scene
        self.folder = folder
        self.project = project
        self.report = report
        self.screenshot = screenshot
    }

    /// The size of each capture taken, in order.
    var taken: [Size] { lock.withLock { sizes } }

    /// Takes the capture `name`: the device's screenshot, or failing that, `frame`, the stream's.
    func take(_ name: String, frame: @Sendable () async throws(RetakeError) -> ScreenFrame) async throws(RetakeError) {
        var still: (data: Data, width: Int, height: Int)?
        var streamed: ScreenFrame?
        if let screenshot {
            let taken = FileManager.default.temporaryDirectory.appending(path: "retake-screenshot-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: taken) }
            do throws(RetakeError) {
                try screenshot(taken)
                guard let data = FileManager.default.contents(atPath: taken.path) else { throw RetakeError(.failed, "it wrote no file") }
                streamed = try? await frame()
                still = try Still.png(screenshot: data, facingAs: streamed?.pixels, context: context)
            } catch {
                report(.warning("\(scene): the device couldn't take \(name)'s screenshot, so it's captured from the recording's stream, which some iPads send smaller than their screen: \(error.message)"))
            }
        }
        if still == nil {
            let fallback: ScreenFrame
            if let streamed { fallback = streamed } else { fallback = try await frame() }
            still = try Still.png(fallback.pixels, context: context)
        }
        guard let still else { return }
        let url = folder.appending(path: "\(name).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try still.data.write(to: url)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(project.displayPath(url)): \(error.localizedDescription)")
        }
        lock.withLock { sizes.append(Size(width: still.width, height: still.height)) }
    }
}

/// The sizes App Store Connect takes screenshots in, by display, as its screenshot specifications
/// name them, https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications,
/// read 2026-11-09. Each orientation's sizes are listed, as a landscape size without a status bar
/// isn't a portrait one turned. Of each device type's, one display is required, and App Store
/// Connect scales its screenshots down for the others.
public enum AppStoreScreenshots {
    struct Display: Sendable {
        var name: String
        var portrait: [(Int, Int)]
        var landscape: [(Int, Int)]
        var required = false

        func sizes(landscape turned: Bool) -> [(Int, Int)] { turned ? landscape : portrait }
    }

    /// Each display's portrait sizes, turned for landscape.
    static func turned(_ sizes: [(Int, Int)]) -> [(Int, Int)] { sizes.map { ($0.1, $0.0) } }

    static let displays: [DeviceType: [Display]] = {
        func display(_ name: String, _ portrait: [(Int, Int)], landscape: [(Int, Int)]? = nil, required: Bool = false) -> Display {
            Display(name: name, portrait: portrait, landscape: landscape ?? turned(portrait), required: required)
        }
        return [
            .iphone: [
                display("iPhone with Dynamic Island (medium display)", [(1179, 2556), (1206, 2622)], required: true),
                display("iPhone with Dynamic Island (large display)", [(1260, 2736), (1290, 2796), (1320, 2868)]),
                display("iPhone with Face ID (large display)", [(1284, 2778), (1242, 2688)]),
                display("iPhone with Face ID (medium display)", [(1170, 2532), (1125, 2436), (1080, 2340)]),
                display("iPhone Duo (outer display)", [(1398, 2034)]),
                display("iPhone Duo (inner display)", [(2007, 2853)]),
                display("iPhone with Home Button (large display)", [(1242, 2208)]),
                display("iPhone with Home Button (medium display)", [(750, 1334)]),
                display("iPhone with Home Button (4\" display)", [(640, 1096), (640, 1136)], landscape: [(1136, 600), (1136, 640)]),
                display("iPhone with Home Button (3.5\" display)", [(640, 920), (640, 960)], landscape: [(960, 600), (960, 640)]),
            ],
            .ipad: [
                display("iPad 13-inch display", [(2064, 2752), (2048, 2732)], required: true),
                display("iPad 12.9-inch display", [(2048, 2732)]),
                display("iPad 11-inch display", [(1488, 2266), (1512, 2316), (1668, 2420), (1668, 2388), (1640, 2360)]),
                display("iPad 10.5-inch display", [(1668, 2224)]),
                display("iPad 9.7-inch display", [(1536, 2008), (1536, 2048), (768, 1004), (768, 1024)], landscape: [(2048, 1496), (2048, 1536), (1024, 748), (1024, 768)]),
            ],
        ]
    }()

    /// The display App Store Connect takes a screenshot this size for, the required one first
    /// where several take it; nil when none does.
    static func display(width: Int, height: Int, for type: DeviceType) -> Display? {
        displays[type]?.first { $0.sizes(landscape: width > height).contains { $0 == (width, height) } }
    }

    /// The name of the display App Store Connect takes a screenshot this size for, such as `iPhone
    /// with Face ID (medium display)`; nil when it takes none this size.
    public static func displayName(width: Int, height: Int, for type: DeviceType) -> String? {
        display(width: width, height: height, for: type)?.name
    }

    /// What `record` says of a capture's size: the display it's for, and the one App Store Connect
    /// requires when it isn't that.
    public static func note(width: Int, height: Int, for type: DeviceType) -> String {
        let size = "\(width)×\(height)"
        let required = displays[type]!.first(where: \.required)!
        let requiredSizes = required.sizes(landscape: width > height).map { "\($0.0)×\($0.1)" }.joined(separator: " or ")
        let requires = "App Store Connect requires \(required.name) screenshots, \(requiredSizes), and scales them down for the other displays."
        guard let display = display(width: width, height: height, for: type) else {
            return "Captures of \(size) aren't a size App Store Connect takes for \(type == .iphone ? "iPhone" : "iPad") screenshots. \(requires)"
        }
        if display.required { return "Captures of \(size) are App Store Connect's size for \(display.name), the display it requires." }
        return "Captures of \(size) are App Store Connect's size for \(display.name). \(requires)"
    }
}
