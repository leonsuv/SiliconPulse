import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceURL = root.appendingPathComponent("Tools/line-art-source.png")
let outputDirectory = root.appendingPathComponent("docs/assets", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Cannot load recovered line art: \(sourceURL.path)") }

func render(size: CGSize, titleSize: CGFloat, taglineSize: CGFloat, output: String) throws {
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No CoreGraphics context") }
    context.setFillColor(NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.085, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: size))

    let sourceSize = source.size
    let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
    let drawn = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let extraX: CGFloat = output == "social-preview.jpg" ? -110 : 0
    source.draw(in: CGRect(x: (size.width - drawn.width) / 2 + extraX, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

    let fadeColors = [
        NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.06, alpha: 0.97).cgColor,
        NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.06, alpha: 0.80).cgColor,
        NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.06, alpha: 0.22).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: fadeColors, locations: [0, 0.46, 0.78, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height / 2), end: CGPoint(x: size.width * 0.76, y: size.height / 2), options: [])

    let margin = size.width * 0.065
    let title = NSAttributedString(string: "SiliconPulse", attributes: [
        .font: NSFont.systemFont(ofSize: titleSize, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1)
    ])
    let tagline = NSAttributedString(string: "Live Apple Silicon telemetry in your menu bar", attributes: [
        .font: NSFont.systemFont(ofSize: taglineSize, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)
    ])
    title.draw(at: CGPoint(x: margin, y: size.height * 0.56))
    tagline.draw(at: CGPoint(x: margin + 2, y: size.height * 0.43))
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { fatalError("Could not encode \(output)") }
    try jpeg.write(to: outputDirectory.appendingPathComponent(output))
}

try render(size: CGSize(width: 1600, height: 600), titleSize: 76, taglineSize: 26, output: "hero.jpg")
try render(size: CGSize(width: 1280, height: 640), titleSize: 60, taglineSize: 24, output: "social-preview.jpg")
