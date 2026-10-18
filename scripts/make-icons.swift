// Generates every logo and icon asset from one transparent PNG of the logo.
//
// Usage: swift scripts/make-icons.swift assets/logo.png
//
// Writes:
//   app/Shared/Resources/Shared.xcassets/Logo.imageset            the logo the screens show
//   app/macOS/Assets.xcassets/AppIcon.appiconset                    the macOS icon
//   app/tvOS/Assets.xcassets/App Icon & Top Shelf Image.brandassets the tvOS layered icon and Top Shelf
//
// Stray specks around the logo (left by background removal) are dropped: only the pixels
// connected to the logo's center survive.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icons.swift <logo.png>\n".utf8))
    exit(1)
}

let burgundy = (red: 0.361, green: 0.039, blue: 0.071)
let canvas = (red: 0.043, green: 0.024, blue: 0.024)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// The logo with specks removed, trimmed to its bounds.
func cleanLogo(_ url: URL) -> CGImage {
    guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("cannot read \(url.path)")
    }
    let width = source.width, height = source.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create a bitmap") }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Flood fill from the center over visible pixels.
    var keep = [Bool](repeating: false, count: width * height)
    var stack = [(width / 2) + (height / 2) * width]
    keep[stack[0]] = true
    while let index = stack.popLast() {
        let x = index % width, y = index / width
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
            let next = nx + ny * width
            if !keep[next] && pixels[next * 4 + 3] > 24 {
                keep[next] = true
                stack.append(next)
            }
        }
    }
    var minX = width, minY = height, maxX = 0, maxY = 0
    for index in 0..<(width * height) {
        if keep[index] {
            let x = index % width, y = index / width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } else {
            pixels[index * 4] = 0; pixels[index * 4 + 1] = 0; pixels[index * 4 + 2] = 0; pixels[index * 4 + 3] = 0
        }
    }
    guard let cleaned = context.makeImage(),
          let trimmed = cleaned.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    else { fail("cannot trim the logo") }
    return trimmed
}

/// Draws a `width`×`height` PNG at `url`.
func render(_ url: URL, width: Int, height: Int, opaque: Bool, _ draw: (CGContext, CGRect) -> Void) {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    ) else { fail("cannot create a \(width)×\(height) bitmap") }
    context.interpolationQuality = .high
    draw(context, CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fail("cannot encode \(url.lastPathComponent)") }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
}

/// Burgundy lit from the top, fading to the canvas color.
func drawWash(_ context: CGContext, _ rect: CGRect) {
    let colors = [
        CGColor(srgbRed: burgundy.red * 1.25, green: burgundy.green * 1.25, blue: burgundy.blue * 1.25, alpha: 1),
        CGColor(srgbRed: burgundy.red, green: burgundy.green, blue: burgundy.blue, alpha: 1),
        CGColor(srgbRed: canvas.red, green: canvas.green, blue: canvas.blue, alpha: 1),
    ]
    guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 0.45, 1]) else { return }
    context.drawRadialGradient(
        gradient, startCenter: CGPoint(x: rect.midX, y: rect.maxY), startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.maxY), endRadius: max(rect.width, rect.height) * 1.1,
        options: [.drawsAfterEndLocation]
    )
}

/// Draws the logo fitted into `box`, centered.
func drawLogo(_ logo: CGImage, _ context: CGContext, in box: CGRect, shadow: Bool) {
    let scale = min(box.width / CGFloat(logo.width), box.height / CGFloat(logo.height))
    let size = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
    let frame = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
    context.saveGState()
    if shadow {
        context.setShadow(offset: CGSize(width: 0, height: -box.height * 0.02), blur: box.height * 0.06, color: CGColor(gray: 0, alpha: 0.55))
    }
    context.draw(logo, in: frame)
    context.restoreGState()
}

func writeJSON(_ object: Any, to url: URL) {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let logo = cleanLogo(URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: root))

// MARK: Shared logo

let shared = root.appending(path: "app/Shared/Resources/Shared.xcassets")
try? FileManager.default.removeItem(at: shared)
writeJSON(["info": info], to: shared.appending(path: "Contents.json"))
let logoSet = shared.appending(path: "Logo.imageset")
render(logoSet.appending(path: "logo.png"), width: 1024, height: 1024 * logo.height / logo.width, opaque: false) { context, rect in
    drawLogo(logo, context, in: rect, shadow: false)
}
writeJSON(["images": [["idiom": "universal", "filename": "logo.png"]], "info": info], to: logoSet.appending(path: "Contents.json"))

// MARK: macOS icon

let mac = root.appending(path: "app/macOS/Assets.xcassets")
try? FileManager.default.removeItem(at: mac)
writeJSON(["info": info], to: mac.appending(path: "Contents.json"))
let appIcon = mac.appending(path: "AppIcon.appiconset")
var macImages: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        render(appIcon.appending(path: name), width: pixels, height: pixels, opaque: false) { context, rect in
            // macOS icons sit inside the canvas with a margin, on a continuous rounded square.
            let tile = rect.insetBy(dx: rect.width * 0.1, dy: rect.width * 0.1)
            let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.clip()
            drawWash(context, tile)
            context.restoreGState()
            drawLogo(logo, context, in: tile.insetBy(dx: tile.width * 0.15, dy: tile.width * 0.15), shadow: true)
        }
        macImages.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
writeJSON(["images": macImages, "info": info], to: appIcon.appending(path: "Contents.json"))

// MARK: tvOS layered icon and Top Shelf

let tv = root.appending(path: "app/tvOS/Assets.xcassets")
try? FileManager.default.removeItem(at: tv)
writeJSON(["info": info], to: tv.appending(path: "Contents.json"))
let brand = tv.appending(path: "App Icon & Top Shelf Image.brandassets")

/// An image stack with a wash in back and the logo in front, at `width`×`height` points.
func imageStack(_ name: String, width: Int, height: Int, scales: [Int]) {
    let stack = brand.appending(path: "\(name).imagestack")
    let layers: [(String, Bool)] = [("Front", false), ("Back", true)]
    for (layer, isBack) in layers {
        let set = stack.appending(path: "\(layer).imagestacklayer/Content.imageset")
        var images: [[String: String]] = []
        for scale in scales {
            let file = "\(layer.lowercased())@\(scale)x.png"
            render(set.appending(path: file), width: width * scale, height: height * scale, opaque: isBack) { context, rect in
                if isBack {
                    drawWash(context, rect)
                } else {
                    drawLogo(logo, context, in: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.1), shadow: true)
                }
            }
            images.append(["idiom": "tv", "scale": "\(scale)x", "filename": file])
        }
        writeJSON(["images": images, "info": info], to: set.appending(path: "Contents.json"))
        writeJSON(["info": info], to: stack.appending(path: "\(layer).imagestacklayer/Contents.json"))
    }
    writeJSON(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], to: stack.appending(path: "Contents.json"))
}

/// A Top Shelf image: the wash with the logo centered.
func topShelf(_ name: String, width: Int, height: Int) {
    let set = brand.appending(path: "\(name).imageset")
    var images: [[String: String]] = []
    for scale in [1, 2] {
        let file = "shelf@\(scale)x.png"
        render(set.appending(path: file), width: width * scale, height: height * scale, opaque: true) { context, rect in
            drawWash(context, rect)
            drawLogo(logo, context, in: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.2), shadow: true)
        }
        images.append(["idiom": "tv", "scale": "\(scale)x", "filename": file])
    }
    writeJSON(["images": images, "info": info], to: set.appending(path: "Contents.json"))
}

imageStack("App Icon", width: 400, height: 240, scales: [1, 2])
imageStack("App Icon - App Store", width: 1280, height: 768, scales: [1])
topShelf("Top Shelf Image", width: 1920, height: 720)
topShelf("Top Shelf Image Wide", width: 2320, height: 720)
writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brand.appending(path: "Contents.json"))

print("wrote \(shared.path), \(mac.path), \(tv.path)")
