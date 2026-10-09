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
    private var overlayController: OverlayController!
    private var menuTimer: Timer?
    private var rightClickRecognizer: NSClickGestureRecognizer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        NSApplication.shared.setActivationPolicy(UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)
        let model = AppModel.shared
        model.applyAppearance()
        if let argument = args.first(where: { $0.hasPrefix("--monitor-release-capture=") }) {
            Task { @MainActor in await MonitorReleaseCapture.run(to: String(argument.dropFirst("--monitor-release-capture=".count))) }
        }
        if let argument = args.first(where: { $0.hasPrefix("--monitor-qa=") }) {
            Task { @MainActor in await MonitorRenderQA.run(to: String(argument.dropFirst("--monitor-qa=".count))) }
        }
        if let snapshotArg = args.first(where: { $0.hasPrefix("--ui-snapshot=") }) {
            let domain = Bundle.main.bundleIdentifier ?? "io.github.leonsuv.SiliconPulse"
            let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.panelController.show()
                model.setPopoverOpen(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self else { return }
                var succeeded = true
                do {
                    try InterfaceRenderQA.render(model: model, panel: self.panelController, to: String(snapshotArg.dropFirst("--ui-snapshot=".count)))
                } catch { succeeded = false; fputs("UI_RENDER_FAILED: \(error)\n", stderr) }
                UserDefaults.standard.setPersistentDomain(saved, forName: domain)
                UserDefaults.standard.synchronize()
                exit(succeeded ? 0 : 1)
            }
        }
        if args.contains("--release-screenshot-de") { model.language = "de" }
        else if args.contains("--release-screenshot-en") || args.contains("--release-screenshot") { model.language = "en" }
        if args.contains("--release-screenshot") {
            model.visibleSections = Set(AppModel.allSections)
            model.expanded = Set(AppModel.allSections)
        }
        model.snapshot.system = SystemCollector().collect()
        panelController = PanelController(model: model)
        overlayController = OverlayController(model: model, panelController: panelController)
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
        if args.contains("--monitor-open") { MonitorWindowController.shared.show() }
        model.startMenuTimer()
        updateStatusLabel()
        menuTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusLabel() }
        }
        menuTimer?.tolerance = 1
        if args.contains(where: { $0.hasPrefix("--monitor-qa=") }) { /* Explicit QA starts with only its monitor window. */ }
        else if overlayController.isActive { overlayController.restoreOnLaunch() }
        else if (UserDefaults.standard.object(forKey: "reopenPinnedAtLaunch") as? Bool ?? true), panelController.isPinned {
            panelController.show()
        }
        if args.contains("--pin-qa-relaunch") {
            panelController.panel.qaLogging = true
            panelController.panel.logPinState("launch-restored")
        }
        if args.contains("--pin-qa") {
            panelController.panel.qaLogging = true
            panelController.setPinned(true)
            panelController.show()
        }
        if args.contains("--pin-qa-escape") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.panelController.panel.handleEscape()
            }
        }
        if args.contains("--pin-qa-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.openSettings()
                self?.panelController.panel.logPinState("settings-open")
            }
        }
        if args.contains("--overlay-qa-render") {
            overlayController.activate()
            model.beginOverlaySampling(metrics: ["CPU %", "GPU %", "RAM %", "Battery %", "Battery W", "CPU temp"], interval: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                for window in NSApp.windows where window !== self.overlayController.panel && window !== self.panelController.panel { window.orderOut(nil) }
                OverlayRenderQA.render(model: model, controller: self.overlayController)
                NSApp.terminate(nil)
            }
        }
        if args.contains("--overlay-qa-live") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                for window in NSApp.windows where window !== self.overlayController.panel && window !== self.panelController.panel {
                    window.orderOut(nil)
                }
            }
        }
        if args.contains("--settings-qa-open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                self.panelController.openSettings()
                print("SETTINGS_WINDOW_OPEN=\(SettingsWindowController.shared.currentWindow?.isVisible == true)")
                fflush(stdout)
            }
        }
        if let tabArgument = args.first(where: { $0.hasPrefix("--settings-qa-tab=") }),
           let tab = Int(tabArgument.split(separator: "=").last ?? "0") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                SettingsWindowController.shared.show(model: model, tab: tab)
                print("SETTINGS_WINDOW_OPEN=\(SettingsWindowController.shared.currentWindow?.isVisible == true) TAB=\(tab)")
                fflush(stdout)
            }
        }
        if args.contains("--release-screenshot-panel") || args.contains(where: { $0.hasPrefix("--release-screenshot-card=") }) || args.contains(where: { $0.hasPrefix("--release-screenshot-pinned=") }) || args.contains("--release-screenshot-edit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let selectedCard = args.first(where: { $0.hasPrefix("--release-screenshot-card=") })?.split(separator: "=", maxSplits: 1).last.map(String.init)
                if selectedCard == "Bluetooth" || selectedCard == "Fans" { self.panelController.editMode = true }
                if let pinArgument = args.first(where: { $0.hasPrefix("--release-screenshot-pinned=") }) {
                    self.panelController.setPinned(true)
                    let sizeName = String(pinArgument.split(separator: "=", maxSplits: 1).last ?? "compact")
                    if sizeName == "large" { self.panelController.resizePanel(width: 620, height: 780) }
                    else { self.panelController.resizePanel(width: 380, height: 520) }
                }
                if args.contains("--release-screenshot-edit") { self.panelController.editMode = true }
                self.panelController.show()
            }
        }
        if args.contains(where: { $0.hasPrefix("--release-screenshot-overlay=") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.overlayController.activate() }
        }
        if args.contains("--diagnostic-dump") {
            model.setPopoverOpen(true)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                print(model.diagnosticDump())
                fflush(stdout)
                NSApplication.shared.terminate(nil)
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { panelController.persistFrame() }

    @objc private func togglePanel() { if overlayController.isActive { overlayController.deactivate() } else { panelController.toggle() } }

    @objc private func showContextMenu(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let menu = NSMenu()
        let pin = NSMenuItem(title: panelController.isPinned ? "Unpin" : "Pin", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)
        menu.addItem(.separator())
        let monitor = NSMenuItem(title: OverlayL10n.text("Open monitor…", locale: AppModel.shared.locale), action: #selector(openMonitor), keyEquivalent: "0")
        monitor.target = self
        menu.addItem(monitor)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if overlayController.isActive {
            let overlaySettings = NSMenuItem(title: "Overlay Settings…", action: #selector(openSettings), keyEquivalent: "")
            overlaySettings.target = self
            menu.addItem(overlaySettings)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SiliconPulse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    }

    @objc private func togglePin() { panelController.setPinned(!panelController.isPinned) }
    @objc private func toggleOverlay() { overlayController.toggle() }
    @objc private func moveOverlay() { overlayController.beginMoveMode() }
    @objc private func openMonitor() { MonitorWindowController.shared.show() }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(model: AppModel.shared)
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
