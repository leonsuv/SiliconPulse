import AppKit
import SwiftUI

/// Captures the production views with real sampled telemetry, without desktop capture.
@MainActor enum InterfaceRenderQA {
    static func render(model: AppModel, panel: PanelController, to directory: String) throws {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        model.stop()
        panel.setPinned(true)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            panel.category = "Overview"
            panel.editMode = false
            panel.panel.setContentSize(NSSize(width: 420, height: 820))
            try capture(panel.panel, to: output.appendingPathComponent("dashboard-\(mode).png"))
            panel.panel.setContentSize(NSSize(width: 760, height: 900))
            try capture(panel.panel, to: output.appendingPathComponent("dashboard-wide-\(mode).png"))
            panel.category = "Performance"
            try capture(panel.panel, to: output.appendingPathComponent("performance-\(mode).png"))
            panel.panel.setContentSize(NSSize(width: 420, height: 640))
            for category in ["Performance", "Energy", "System"] {
                panel.category = category
                try capture(panel.panel, to: output.appendingPathComponent("category-\(category.lowercased())-\(mode).png"))
            }
            panel.editMode = true
            panel.panel.setContentSize(NSSize(width: 420, height: 660))
            try capture(panel.panel, to: output.appendingPathComponent("edit-\(mode).png"))
            panel.editMode = false
            for tab in 0...6 {
                SettingsWindowController.shared.show(model: model, tab: tab)
                if let window = SettingsWindowController.shared.currentWindow {
                    window.setContentSize(NSSize(width: 860, height: 680))
                    try capture(window, to: output.appendingPathComponent("settings-\(tab)-\(mode).png"))
                }
            }
        }
        // Verify the supported minimum, independently of a saved window frame.
        panel.panel.setContentSize(NSSize(width: 340, height: 420))
        panel.category = "Overview"
        try capture(panel.panel, to: output.appendingPathComponent("minimum-panel.png"))
        print("UI_RENDER_OK: compact 420×820, wide 760×900, minimum 340×420, seven settings sections; light and dark")
    }

    static func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw CocoaError(.fileWriteUnknown) }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI observation and AppKit layout settle before rasterizing.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        print("SNAPSHOT \(url.lastPathComponent) \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
    }
}
