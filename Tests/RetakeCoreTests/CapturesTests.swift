import CoreImage
import CoreVideo
import Foundation
import ImageIO
@testable import RetakeCore
import Testing

/// The stills a scene's captures take, as `record` writes and keeps them.
struct CapturesTests {
    /// A BGRA frame `width` by `height`, all `color` but its top-left pixel, which is white.
    static func frame(width: Int, height: Int, color: (b: UInt8, g: UInt8, r: UInt8)) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &made)
        let pixels = try #require(made)
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<height {
            for x in 0..<width {
                let at = base + y * row + x * 4
                let white = x == 0 && y == 0
                (at[0], at[1], at[2], at[3]) = white ? (255, 255, 255, 255) : (color.b, color.g, color.r, 255)
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    @Test func aStillIsAPNGOfTheFramesSizeWithNoAlphaChannelAndItsPixels() throws {
        let still = try Still.png(Self.frame(width: 6, height: 4, color: (b: 0, g: 0, r: 255)), context: CIContext())
        #expect((still.width, still.height) == (6, 4))
        let source = try #require(CGImageSourceCreateWithData(still.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect((image.width, image.height) == (6, 4))
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo), "App Store Connect refuses a screenshot with an alpha channel")
        // Drawn into sRGB, the top-left pixel is white and the rest red.
        var bytes = [UInt8](repeating: 0, count: 6 * 4 * 4)
        let context = try #require(CGContext(
            data: &bytes, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 24,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 6, height: 4))
        #expect(Array(bytes[0..<3]) == [255, 255, 255])
        #expect(bytes[4] > 240 && bytes[5] < 15 && bytes[6] < 15)
    }

    /// A PNG `width` by `height` with an alpha channel, in Display P3, as an iPhone's screenshot is.
    static func screenshot(width: Int, height: Int) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [0, 0.5, 1, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aCaptureIsTheDevicesScreenshotWithoutItsAlphaOrTheStreamsFrameWhenItCantTakeOne() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RetakeCapturesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(configuration: root.appending(path: "retake.json"))
        let folder = root.appending(path: "taken", directoryHint: .isDirectory)
        let warnings = Readings()
        let report: @Sendable (Player.Event) -> Void = { event in if case .warning(let message) = event { warnings.names.append(message) } }
        let shot = try Self.screenshot(width: 8, height: 12)
        let frame = ScreenFrame(pixels: try Self.frame(width: 4, height: 6, color: (0, 0, 0)))

        let taker = CaptureTaker(scene: "home", folder: folder, project: project, report: report, screenshot: { url throws(RetakeError) in
            do { try shot.write(to: url) } catch { throw RetakeError(.failed, "\(error)") }
        })
        try await taker.take("library") { () throws(RetakeError) in frame }
        let kept = try #require(CGImageSourceCreateWithURL(folder.appending(path: "library.png") as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect((kept.width, kept.height) == (8, 12), "the screenshot, not the stream's smaller frame")
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(kept.alphaInfo))
        #expect(kept.colorSpace?.name == CGColorSpace.displayP3, "in the device's own color space")
        #expect(warnings.names.isEmpty)

        let failing = CaptureTaker(scene: "home", folder: folder, project: project, report: report, screenshot: { _ throws(RetakeError) in
            throw RetakeError(.environment, "devicectl device capture screenshot failed")
        })
        try await failing.take("note") { () throws(RetakeError) in frame }
        #expect(failing.taken.map { "\($0.width)×\($0.height)" } == ["4×6"], "the stream's frame")
        #expect(warnings.names == ["home: the device couldn't take note's screenshot, so it's captured from the recording's stream, which some iPads send smaller than their screen: devicectl device capture screenshot failed"])
    }

    /// A BGRA frame, black but for its top-left quarter, which is white.
    static func cornered(width: Int, height: Int) throws -> CVPixelBuffer {
        let pixels = try frame(width: width, height: height, color: (0, 0, 0))
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height / 2 { for x in 0..<width / 2 { let at = base + y * CVPixelBufferGetBytesPerRow(pixels) + x * 4; (at[0], at[1], at[2]) = (255, 255, 255) } }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    @Test func aScreenshotTakenAsIfTheDeviceHadntTurnedIsTurnedToFaceAsTheStreamDoes() throws {
        let context = CIContext(), space = CGColorSpace(name: CGColorSpace.sRGB)!
        let streamed = try Self.cornered(width: 80, height: 60)
        let upright = try #require(context.createCGImage(CIImage(cvPixelBuffer: streamed), from: CGRect(x: 0, y: 0, width: 80, height: 60)))
        for quarters in [0, 1, 3] {
            let taken = try Still.turned(upright, quarters: quarters, in: space)
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, taken, nil)
            #expect(CGImageDestinationFinalize(destination))
            let still = try Still.png(screenshot: data as Data, facingAs: streamed, context: context)
            #expect((still.width, still.height) == (80, 60), "turned \(quarters) quarters")
            let image = try #require(CGImageSourceCreateWithData(still.data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            var bytes = [UInt8](repeating: 0, count: 80 * 60 * 4)
            let drawn = try #require(CGContext(data: &bytes, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            drawn.draw(image, in: CGRect(x: 0, y: 0, width: 80, height: 60))
            #expect(bytes[(5 * 80 + 5) * 4] > 200 && bytes[(55 * 80 + 75) * 4] < 50, "white at the top left, as the stream has it, turned \(quarters) quarters")
        }
    }

    @Test func capturesTakenReplaceTheScenesOnlyOnceKeptAndAreListedWithTheirSizes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RetakeCapturesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(configuration: root.appending(path: "retake.json"))
        let captures = project.captures(for: .iphone)
        func write(_ name: String, in folder: URL, width: Int) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Still.png(Self.frame(width: width, height: 4, color: (0, 0, 0)), context: CIContext()).data.write(to: folder.appending(path: "\(name).png"))
        }
        try write("old", in: CaptureStore.folder(of: "home", for: .iphone, in: project), width: 2)
        try write("list", in: CaptureStore.recording(of: "home", in: captures), width: 3)
        try write("detail", in: CaptureStore.recording(of: "home", in: captures), width: 5)
        #expect(CaptureStore.scenes(for: .iphone, in: project) == ["home"], "captures being taken aren't a scene's")

        try CaptureStore.keepRecording(of: "home", in: captures)
        let kept = CaptureStore.captures(in: CaptureStore.folder(of: "home", for: .iphone, in: project))
        #expect(kept.map { "\($0.name) \($0.width)×\($0.height)" } == ["detail 5×4", "list 3×4"], "the old ones are replaced")
        #expect(!FileManager.default.fileExists(atPath: CaptureStore.recording(of: "home", in: captures).path))
    }

    @Test func eachSizeIsNamedForTheAppStoreDisplayItsTakenForAndTheRequiredOneWhenItIsntThat() {
        #expect(AppStoreScreenshots.displayName(width: 1170, height: 2532, for: .iphone) == "iPhone with Face ID (medium display)")
        #expect(AppStoreScreenshots.displayName(width: 2532, height: 1170, for: .iphone) == "iPhone with Face ID (medium display)")
        #expect(AppStoreScreenshots.displayName(width: 1668, height: 2388, for: .ipad) == "iPad 11-inch display")
        #expect(AppStoreScreenshots.displayName(width: 2048, height: 2732, for: .ipad) == "iPad 13-inch display", "the required display, which 12.9-inch shares")
        #expect(AppStoreScreenshots.displayName(width: 1136, height: 600, for: .iphone) == "iPhone with Home Button (4\" display)", "landscape without a status bar")
        #expect(AppStoreScreenshots.displayName(width: 1096, height: 640, for: .iphone) == nil, "isn't a portrait size turned")
        #expect(AppStoreScreenshots.displayName(width: 1170, height: 2532, for: .ipad) == nil, "an iPhone's size isn't an iPad's")
        #expect(AppStoreScreenshots.note(width: 1170, height: 2532, for: .iphone) == "Captures of 1170×2532 are App Store Connect's size for iPhone with Face ID (medium display). App Store Connect requires iPhone with Dynamic Island (medium display) screenshots, 1179×2556 or 1206×2622, and scales them down for the other displays.")
        #expect(AppStoreScreenshots.note(width: 2622, height: 1206, for: .iphone) == "Captures of 2622×1206 are App Store Connect's size for iPhone with Dynamic Island (medium display), the display it requires.")
        #expect(AppStoreScreenshots.note(width: 1000, height: 2000, for: .ipad) == "Captures of 1000×2000 aren't a size App Store Connect takes for iPad screenshots. App Store Connect requires iPad 13-inch display screenshots, 2064×2752 or 2048×2732, and scales them down for the other displays.")
    }
}
