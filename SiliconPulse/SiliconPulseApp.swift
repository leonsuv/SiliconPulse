import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApplication.shared.setActivationPolicy(.accessory) }
}

@main struct SiliconPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel()
    var body: some Scene {
        MenuBarExtra {
            DashboardView().environment(model).frame(width: 360, height: 620)
                .onAppear { model.start(open: true) }.onDisappear { model.start(open: false) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text(model.value(for: model.menuMetric)).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
            }.accessibilityLabel("\(model.menuMetric): \(model.value(for: model.menuMetric))")
                .task { model.start(open: false) }
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().environment(model).frame(width: 420, height: 300).padding() }
    }
}
