import SwiftUI
import AppKit

@MainActor enum OverlayRenderQA {
    static func render(model: AppModel, controller: OverlayController) {
        let output = URL(fileURLWithPath: "/tmp/SiliconPulseOverlayQA", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let prefs = controller.preferences
        prefs.metrics = ["CPU %", "GPU %", "RAM %", "Battery %", "Battery W", "CPU temp"]
        prefs.showLabels = true
        prefs.showSparklines = true
        prefs.compact = false
        prefs.hint = true
        prefs.hotKey = "⌃⌥O"
        prefs.background = "Subtle dark pill"
        prefs.opacity = 0.35
        prefs.textOpacity = 1
        prefs.cornerRadius = 10
        let backgrounds = ["white", "mid-grey", "black", "busy-gradient"]
        for layout in ["List", "Compact", "Bar"] {
            prefs.layout = layout == "Bar" ? "Bar" : "List"
            prefs.compact = layout == "Compact"
            for scale in [0.8, 1.0, 1.6] {
                prefs.scale = scale
                for language in ["en", "de"] {
                    let locale = Locale(identifier: language)
                    let width: CGFloat = (layout == "List" ? 360 : 112 * CGFloat(prefs.metrics.count) + 24) * scale
                    let contentHeight: CGFloat = layout == "Bar" ? 24 : CGFloat(prefs.metrics.count) * 22
                    let height: CGFloat = (contentHeight + 26 + 16) * scale
                    controller.enteredAt = .now
                    let cells = backgrounds.map { name in
                        AnyView(ZStack {
                            desktopBackground(name)
                            OverlayView(model: model, controller: controller)
                                .environment(\.locale, locale)
                                .frame(width: layout == "List" ? width : width, height: height)
                        }.frame(width: width, height: height).clipped())
                    }
                    let sheet = VStack(spacing: 12) {
                        HStack(spacing: 12) { cells[0]; cells[1] }
                        HStack(spacing: 12) { cells[2]; cells[3] }
                    }.padding(12).background(Color.gray.opacity(0.22))
                    let renderer = ImageRenderer(content: sheet)
                    renderer.scale = 2
                    guard let image = renderer.nsImage else { continue }
                    save(image, to: output.appendingPathComponent("\(layout.lowercased())_\(Int(scale * 100))_\(language).png"))
                }
            }
        }
        // Plain-text mode contrast sheets: same layouts on representative light, grey, and dark desktop colors.
        prefs.background = "None"
        prefs.layout = "List"
        prefs.compact = false
        prefs.scale = 1
        for language in ["en", "de"] {
            let locale = Locale(identifier: language)
            controller.enteredAt = .now
            let cells = ["white", "mid-grey", "black"].map { name in
                AnyView(ZStack { desktopBackground(name); OverlayView(model: model, controller: controller).environment(\.locale, locale).frame(width: 360, height: 6 * 22 + 35) }.frame(width: 360, height: 6 * 22 + 35).clipped())
            }
            let sheet = HStack(spacing: 12) { cells[0]; cells[1]; cells[2] }.padding(12).background(Color.gray.opacity(0.22))
            let renderer = ImageRenderer(content: sheet); renderer.scale = 2
            if let image = renderer.nsImage { save(image, to: output.appendingPathComponent("none_100_\(language).png")) }
        }
        print("OVERLAY_QA_RENDER_DIR=\(output.path)")
    }

    private static func desktopBackground(_ name: String) -> AnyView {
        switch name {
        case "white": AnyView(Color.white)
        case "mid-grey": AnyView(Color(red: 0.52, green: 0.52, blue: 0.52))
        case "black": AnyView(Color.black)
        default:
            AnyView(ZStack {
                LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.36), .purple, .orange, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, _ in
                    for index in 0..<22 {
                        let x = CGFloat((index * 71 + 19) % 360)
                        let y = CGFloat((index * 43 + 7) % 230)
                        let diameter = CGFloat(16 + (index * 13) % 54)
                        let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                        context.fill(Path(ellipseIn: rect), with: .color([Color.pink, .blue, .yellow, .green, .white][index % 5].opacity(0.45)))
                    }
                }
            })
        }
    }
    private static func save(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
