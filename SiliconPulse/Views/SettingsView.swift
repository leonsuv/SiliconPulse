import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var bindable = model
        TabView {
            Form {
                Section("Menu bar") {
                    ForEach(AppModel.menuOptions, id: \.self) { metric in
                        Toggle(isOn: Binding(get: { model.menuMetrics.contains(metric) }, set: { enabled in
                            if enabled { if !model.menuMetrics.contains(metric) { model.menuMetrics.append(metric) } }
                            else { model.menuMetrics.removeAll { $0 == metric } }
                        })) { Text(LocalizedStringKey(metric)) }
                    }
                    Picker("Popover refresh", selection: $bindable.refreshSeconds) {
                        Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0)
                    }.onChange(of: model.refreshSeconds) { _, value in UserDefaults.standard.set(value, forKey: "refreshSeconds"); model.restartTimer() }
                }
                Section("Units and appearance") {
                    Toggle("Use Fahrenheit", isOn: $bindable.fahrenheit).onChange(of: model.fahrenheit) { _, value in UserDefaults.standard.set(value, forKey: "fahrenheit") }
                    Toggle("Decimal GB", isOn: $bindable.decimalUnits).onChange(of: model.decimalUnits) { _, value in UserDefaults.standard.set(value, forKey: "decimalUnits") }
                    Toggle("Network speeds in bits", isOn: $bindable.networkBits).onChange(of: model.networkBits) { _, value in UserDefaults.standard.set(value, forKey: "networkBits") }
                    Picker("History length", selection: $bindable.historyMinutes) {
                        Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15)
                    }.onChange(of: model.historyMinutes) { _, value in UserDefaults.standard.set(value, forKey: "historyMinutes") }
                    Toggle("Compact rows", isOn: $bindable.compactRows).onChange(of: model.compactRows) { _, value in UserDefaults.standard.set(value, forKey: "compactRows") }
                }
                Section("Startup") {
                    Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in model.toggleLogin() }))
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }

            NavigationStack {
                List {
                    ForEach(model.sectionOrder, id: \.self) { section in
                        Toggle(isOn: Binding(get: { model.visibleSections.contains(section) }, set: { model.setVisibleSection(section, visible: $0) })) {
                            Text(LocalizedStringKey(section))
                        }
                    }.onMove(perform: model.moveSection)
                }.navigationTitle("Sections")
            }.tabItem { Label("Sections", systemImage: "rectangle.3.group") }

            Form {
                Section("Optional network request") {
                    Toggle("Probe 1.1.1.1 over TCP (makes a network request)", isOn: Binding(get: { model.latencyProbeEnabled }, set: { model.setLatencyProbeEnabled($0) }))
                }
                Section("Alerts") {
                    Toggle("Enable notifications", isOn: Binding(get: { model.alertsEnabled }, set: { model.setAlertsEnabled($0) }))
                    TextField("Battery below (%)", value: $bindable.batteryAlertThreshold, format: .number).onChange(of: model.batteryAlertThreshold) { _, value in UserDefaults.standard.set(value, forKey: "batteryAlertThreshold") }
                    TextField("Process CPU above (%)", value: $bindable.cpuAlertThreshold, format: .number).onChange(of: model.cpuAlertThreshold) { _, value in UserDefaults.standard.set(value, forKey: "cpuAlertThreshold") }
                }
            }.formStyle(.grouped).tabItem { Label("Privacy and alerts", systemImage: "bell.badge") }
        }.navigationTitle("SiliconPulse Settings")
    }
}
