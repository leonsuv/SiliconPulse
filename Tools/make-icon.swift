import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("SiliconPulse.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderIcon(size: Int, name: String) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No CoreGraphics context") }
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let rounded = CGPath(roundedRect: bounds.insetBy(dx: 34, dy: 34), cornerWidth: 220, cornerHeight: 220, transform: nil)
    context.addPath(rounded)
    context.clip()
    let colors = [CGColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1), CGColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(38)
    context.setStrokeColor(CGColor(red: 0.18, green: 0.88, blue: 0.84, alpha: 1))
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: 150, y: 510))
    pulse.addLine(to: CGPoint(x: 320, y: 510))
    pulse.addLine(to: CGPoint(x: 410, y: 355))
    pulse.addLine(to: CGPoint(x: 500, y: 675))
    pulse.addLine(to: CGPoint(x: 625, y: 420))
    pulse.addLine(to: CGPoint(x: 705, y: 510))
    pulse.addLine(to: CGPoint(x: 875, y: 510))
    context.addPath(pulse)
    context.strokePath()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    try png.write(to: iconset.appendingPathComponent(name))
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (size, name) in sizes { try renderIcon(size: size, name: name) }
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
