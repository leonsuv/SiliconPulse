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
            DashboardView().environment(model).frame(width: 380)
        } label: {
            HStack(spacing: 5) {
                ForEach(Array(model.menuMetrics.enumerated()), id: \.offset) { index, metric in
                    if index > 0 { Rectangle().fill(.tertiary).frame(width: 1, height: 13) }
                    HStack(spacing: 3) {
                        Image(systemName: model.menuSymbol(for: metric))
                        Text(model.value(for: metric)).monospacedDigit().lineLimit(1).frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.menuMetrics.map { "\($0): \(model.value(for: $0))" }.joined(separator: ", "))
            .task { model.startMenuTimer() }
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().environment(model).frame(width: 480, height: 640).padding() }
    }
}
