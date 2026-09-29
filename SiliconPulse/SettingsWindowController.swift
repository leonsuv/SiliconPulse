import AppKit
import SwiftUI

@MainActor final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var tabSelection: SettingsTabSelection?
    var currentWindow: NSWindow? { window }

    func show(model: AppModel, tab: Int = 0) {
        if window == nil {
            let tabSelection = SettingsTabSelection(tab)
            let root = AnyView(
                SettingsView(tab: tab, tabSelection: tabSelection)
                    .environment(model)
                    .environment(\.locale, model.locale)
                    .frame(minWidth: 760, minHeight: 560)
            )
            let hostingView = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SiliconPulse Settings"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 588)
            window.setFrameAutosaveName("SiliconPulseSettings")
            window.center()
            window.contentView = hostingView
            self.hostingView = hostingView
            self.window = window
            self.tabSelection = tabSelection
        } else {
            tabSelection?.index = tab
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        hideSwiftUISettingsScene(except: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak window] in
            guard let self, let window else { return }
            self.hideSwiftUISettingsScene(except: window)
        }
    }

    func close() { window?.orderOut(nil) }

    private func hideSwiftUISettingsScene(except settingsWindow: NSWindow) {
        for candidate in NSApp.windows where candidate !== settingsWindow {
            if candidate is ManagedPanel || candidate is OverlayPanel { continue }
            candidate.orderOut(nil)
        }
    }
}
