import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var bindable = model
        Form {
            Picker("Menu bar metric", selection: $bindable.menuMetric) { ForEach(["Battery", "CPU", "Power", "Memory", "GPU %", "Disk I/O"], id: \.self) { Text($0) } }.onChange(of: model.menuMetric) { _, v in UserDefaults.standard.set(v, forKey: "menuMetric") }
            Picker("Popover refresh", selection: $bindable.refreshSeconds) { Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0) }.onChange(of: model.refreshSeconds) { _, v in UserDefaults.standard.set(v, forKey: "refreshSeconds"); model.restartTimer() }
            Toggle("Use Fahrenheit", isOn: $bindable.fahrenheit).onChange(of: model.fahrenheit) { _, v in UserDefaults.standard.set(v, forKey: "fahrenheit") }
            Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in model.toggleLogin() }))
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        }.formStyle(.grouped).navigationTitle("SiliconPulse Settings")
    }
}
