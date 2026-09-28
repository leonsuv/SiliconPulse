import SwiftUI
import AppKit

@main struct SiliconPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Settings { SettingsView().environment(model).environment(\.locale, model.locale).frame(minWidth: 620, minHeight: 520) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var menuTimer: Timer?
    private var rightClickRecognizer: NSClickGestureRecognizer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)
        let model = AppModel.shared
        panelController = PanelController(model: model)
        model.onMenuLabelUpdate = { [weak self] in self?.updateStatusLabel() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            let rightClick = NSClickGestureRecognizer(target: self, action: #selector(showContextMenu(_:)))
            rightClick.buttonMask = 0x2
            button.addGestureRecognizer(rightClick)
            rightClickRecognizer = rightClick
            panelController.setStatusButton(button)
        }
        model.startMenuTimer()
        updateStatusLabel()
        menuTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusLabel() }
        }
        menuTimer?.tolerance = 1
        if (UserDefaults.standard.object(forKey: "reopenPinnedAtLaunch") as? Bool ?? true), panelController.pinned {
            panelController.show()
        }
    }

    @objc private func togglePanel() { panelController.toggle() }

    @objc private func showContextMenu(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let menu = NSMenu()
        let pin = NSMenuItem(title: panelController.pinned ? "Unpin" : "Pin", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SiliconPulse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    }

    @objc private func togglePin() { panelController.setPinned(!panelController.pinned) }
    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func updateStatusLabel() {
        let metrics = AppModel.shared.menuMetrics
        let button = statusItem.button
        let iconName = metrics.first.map { AppModel.shared.menuSymbol(for: $0) } ?? "waveform.path.ecg"
        button?.image = AppModel.shared.showMenuIcons ? NSImage(systemSymbolName: iconName, accessibilityDescription: "SiliconPulse") : nil
        let parts = metrics.map { metric -> String in
            let value = String(AppModel.shared.value(for: metric).prefix(9)).padding(toLength: 9, withPad: " ", startingAt: 0)
            return "\(metric == "Battery %" ? "" : "\(metric.replacingOccurrences(of: " %", with: "")) ")\(value)"
        }
        let separator: String = switch AppModel.shared.menuSeparator { case "Bar": "  |  "; case "Space": "     "; default: "  ·  " }
        let text = parts.isEmpty ? "SiliconPulse" : parts.joined(separator: separator)
        button?.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        button?.toolTip = metrics.map { "\($0): \(AppModel.shared.value(for: $0))" }.joined(separator: "\n")
    }
}
