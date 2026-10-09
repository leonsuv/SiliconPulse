import AppKit
import Foundation

/// Opt-in capture of the app's own windows. Run with a separate preferences domain.
@MainActor enum MonitorReleaseCapture {
    static func run(to directory: String) async {
        let app = AppModel.shared
        let controller = MonitorWindowController.shared
        app.language = "en"; app.appearance = "Dark"; app.applyAppearance()
        controller.show()
        guard let window = controller.window else { NSApp.terminate(nil); return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            controller.model.selectSection("Performance")
            controller.model.selection = "CPU"
            // Fill the real one-minute history; no fixtures or generated telemetry.
            try? await Task.sleep(for: .seconds(62))
            let captures: [(String, String, String, String, String)] = [
                ("monitor-cpu-1-2", "Performance", "CPU", "en", "Dark"),
                ("monitor-gpu-1-2", "Performance", "GPU", "en", "Dark"),
                ("monitor-memory-1-2", "Performance", "Memory", "en", "Dark"),
                ("monitor-silicon-1-2", "Apple Silicon", "CPU", "en", "Dark"),
                ("monitor-cpu-de-1-2", "Performance", "CPU", "de", "Light")
            ]
            for (name, section, metric, language, appearance) in captures {
                app.language = language; app.appearance = appearance; app.applyAppearance()
                controller.model.selectSection(section); controller.model.selection = metric
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(2))
                window.contentView?.layoutSubtreeIfNeeded(); window.contentView?.displayIfNeeded()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
                try process.run(); process.waitUntilExit()
                print("CAPTURE \(name) status=\(process.terminationStatus)"); fflush(stdout)
            }
        } catch { print("CAPTURE_FAILED \(error.localizedDescription)"); fflush(stdout) }
        NSApp.terminate(nil)
    }
}
