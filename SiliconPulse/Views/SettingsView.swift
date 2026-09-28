import SwiftUI
import ServiceManagement
import UserNotifications
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model
        TabView {
            Form {
                Section("Startup") {
                    Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in model.toggleLogin() }))
                    Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                    Toggle("Reopen pinned panel at launch", isOn: $settings.reopenPinnedAtLaunch)
                    Picker("Language", selection: $settings.language) {
                        Text("System").tag("System"); Text("English").tag("en"); Text("Deutsch").tag("de")
                    }
                }
                Section("Sampling and panel") {
                    Picker("Refresh interval", selection: $settings.refreshSeconds) {
                        Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0)
                    }.onChange(of: model.refreshSeconds) { _, value in UserDefaults.standard.set(value, forKey: "refreshSeconds"); model.restartTimer() }
                    Picker("History length", selection: $settings.historyMinutes) {
                        Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15)
                    }.onChange(of: model.historyMinutes) { _, value in UserDefaults.standard.set(value, forKey: "historyMinutes") }
                    Toggle("Compact rows", isOn: $settings.compactRows).onChange(of: model.compactRows) { _, value in UserDefaults.standard.set(value, forKey: "compactRows") }
                    LabeledContent("Pinned panel opacity") {
                        Slider(value: $settings.panelOpacity, in: 0.6...1) { Text("Opacity") }
                            .frame(width: 170).disabled(!PanelController.sharedPinned)
                    }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }

            Form {
                Section("Visible menu bar metrics") {
                    ForEach(Array(model.menuMetrics.enumerated()), id: \.element) { index, metric in
                        HStack {
                        Toggle(isOn: Binding(get: { model.menuMetrics.contains(metric) }, set: { enabled in
                            if enabled { if !model.menuMetrics.contains(metric) { model.menuMetrics.append(metric) } }
                            else { model.menuMetrics.removeAll { $0 == metric } }
                        })) { Label(metric, systemImage: model.menuSymbol(for: metric)) }
                            .onDrag { NSItemProvider(object: metric as NSString) }
                        Button { model.moveMenuMetric(metric, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).buttonStyle(.plain)
                        Button { model.moveMenuMetric(metric, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.menuMetrics.count - 1).buttonStyle(.plain)
                        }.onDrop(of: [UTType.plainText], delegate: MenuMetricDropDelegate(metric: metric, model: model))
                    }.onMove { source, destination in
                        var values = model.menuMetrics
                        let moving = source.map { values[$0] }
                        for index in source.sorted(by: >) { values.remove(at: index) }
                        values.insert(contentsOf: moving, at: min(destination, values.count))
                        model.menuMetrics = values
                    }
                    Text("Drag to reorder. Use the options below to add or remove metrics.").font(.caption).foregroundStyle(.secondary)
                    ForEach(AppModel.menuOptions.filter { !model.menuMetrics.contains($0) }, id: \.self) { metric in
                        Toggle(isOn: Binding(get: { false }, set: { if $0 { model.menuMetrics.append(metric) } })) {
                            Label(metric, systemImage: model.menuSymbol(for: metric))
                        }
                    }
                }
                Section("Label appearance") {
                    Toggle("Show SF Symbol", isOn: $settings.showMenuIcons)
                    Picker("Separator", selection: $settings.menuSeparator) {
                        Text("Dot").tag("Dot"); Text("Bar").tag("Bar"); Text("Space").tag("Space")
                    }
                }
                Section("Preview") {
                    Text(model.menuMetrics.map { "\(model.menuSymbol(for: $0))  \(model.value(for: $0))" }.joined(separator: "   ·   "))
                        .font(.system(.body, design: .monospaced)).lineLimit(2)
                }
            }.formStyle(.grouped).tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            NavigationStack {
                List {
                    ForEach(Array(model.sectionOrder.enumerated()), id: \.element) { index, section in
                        HStack {
                            Toggle(isOn: Binding(get: { model.visibleSections.contains(section) }, set: { model.setVisibleSection(section, visible: $0) })) {
                                Text(LocalizedStringKey(section))
                            }
                            Toggle("Expanded", isOn: Binding(get: { model.expanded.contains(section) }, set: { if $0 { model.expanded.insert(section) } else { model.expanded.remove(section) } }))
                                .toggleStyle(.checkbox).labelsHidden().help("Expanded by default")
                            Button { model.moveSection(section, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).buttonStyle(.plain)
                            Button { model.moveSection(section, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.sectionOrder.count - 1).buttonStyle(.plain)
                        }
                    }.onMove(perform: model.moveSection)
                }.navigationTitle("Sections")
            }.tabItem { Label("Sections", systemImage: "rectangle.3.group") }

            Form {
                Section("Temperature and capacity") {
                    Toggle("Use Fahrenheit", isOn: $settings.fahrenheit).onChange(of: model.fahrenheit) { _, value in UserDefaults.standard.set(value, forKey: "fahrenheit") }
                    Toggle("Decimal GB / TB", isOn: $settings.decimalUnits).onChange(of: model.decimalUnits) { _, value in UserDefaults.standard.set(value, forKey: "decimalUnits") }
                    Toggle("Network rates in bits", isOn: $settings.networkBits).onChange(of: model.networkBits) { _, value in UserDefaults.standard.set(value, forKey: "networkBits") }
                    Toggle("Use 24-hour time", isOn: $settings.use24HourTime)
                }
            }.formStyle(.grouped).tabItem { Label("Units", systemImage: "ruler") }

            Form {
                Section {
                    Toggle("Enable notifications", isOn: Binding(get: { model.alertsEnabled }, set: { model.setAlertsEnabled($0) }))
                    Toggle("Battery below threshold", isOn: preference("alertBatteryLow", default: true))
                    TextField("Battery threshold (%)", value: $settings.batteryAlertThreshold, format: .number).onChange(of: model.batteryAlertThreshold) { _, value in UserDefaults.standard.set(value, forKey: "batteryAlertThreshold") }
                    Toggle("Battery fully charged", isOn: preference("alertBatteryFull", default: false))
                    Toggle("Thermal state serious or worse", isOn: preference("alertThermal", default: true))
                    Toggle("High process CPU", isOn: preference("alertCPU", default: true))
                    HStack {
                        TextField("CPU threshold (%)", value: $settings.cpuAlertThreshold, format: .number)
                            .onChange(of: model.cpuAlertThreshold) { _, value in UserDefaults.standard.set(value, forKey: "cpuAlertThreshold") }
                        TextField("Duration (s)", value: preferenceInt("alertCPUSeconds", default: 30), format: .number)
                    }
                    Toggle("Memory pressure warning / critical", isOn: preference("alertMemoryPressure", default: false))
                    Toggle("Low disk space", isOn: preference("alertDiskLow", default: false))
                    TextField("Disk free threshold (GB)", value: preferenceDouble("alertDiskGB", default: 10), format: .number)
                    Toggle("SMART failure", isOn: preference("alertSMART", default: true))
                    Toggle("High temperature", isOn: preference("alertTemperature", default: false))
                    TextField("Temperature threshold (°C)", value: preferenceDouble("alertTemperatureC", default: 90), format: .number)
                    Toggle("Bluetooth battery low", isOn: preference("alertBluetooth", default: false))
                    TextField("Bluetooth threshold (%)", value: preferenceInt("alertBluetoothPercent", default: 15), format: .number)
                    Picker("Cooldown", selection: preferenceInt("alertCooldownMinutes", default: 10)) {
                        Text("5 min").tag(5); Text("10 min").tag(10); Text("30 min").tag(30); Text("60 min").tag(60)
                    }
                    HStack {
                        DatePicker("Quiet hours from", selection: datePreference("quietHoursStart", hour: 22), displayedComponents: .hourAndMinute)
                        DatePicker("to", selection: datePreference("quietHoursEnd", hour: 7), displayedComponents: .hourAndMinute)
                    }
                    Button("Send test notification") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                            let content = UNMutableNotificationContent(); content.title = "SiliconPulse"; content.body = "Notifications are working."; content.sound = .default
                            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                        }
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Notifications", systemImage: "bell.badge") }

            Form {
                Section("Optional network request") {
                    Toggle("Enable latency probe", isOn: Binding(get: { model.latencyProbeEnabled }, set: { model.setLatencyProbeEnabled($0) }))
                    Text("When enabled, SiliconPulse sends a TCP request to measure network latency.").font(.caption).foregroundStyle(.secondary)
                    TextField("Probe host", text: preferenceString("latencyHost", default: "1.1.1.1"))
                }
                Section("Sensor sources") {
                    Toggle("HID temperature sensors", isOn: $settings.enableHIDTemps)
                    Toggle("SMC fan speeds", isOn: $settings.enableSMCFans)
                }
                Section("Snapshot and configuration") {
                    Toggle("Include process names in copied snapshot", isOn: preference("copyProcessNames", default: false))
                    Button("Copy snapshot") { model.copySnapshot() }
                    HStack {
                        Button("Export settings…", action: exportSettings)
                        Button("Import settings…", action: importSettings)
                    }
                    if !model.settingsMessage.isEmpty { Text(model.settingsMessage).font(.caption).foregroundStyle(.secondary) }
                    Button("Reset all settings…", role: .destructive) { model.showSettingsResetConfirmation = true }
                        .confirmationDialog("Reset SiliconPulse settings?", isPresented: Binding(get: { model.showSettingsResetConfirmation }, set: { model.showSettingsResetConfirmation = $0 }), titleVisibility: .visible) {
                            Button("Reset Settings", role: .destructive) { resetAllSettings() }
                        } message: { Text("This restores the default layout and preferences.") }
                }
                Section("About") {
                    LabeledContent("SiliconPulse", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Link("GitHub project", destination: URL(string: "https://github.com")!)
                    Text("MIT License · Private telemetry interfaces: IOReport and AppleSMC sensor access.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }.padding(8).frame(minWidth: 650, minHeight: 520).navigationTitle("SiliconPulse Settings")
            .environment(\.locale, model.locale)
    }

    private func preference(_ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
    private func preferenceInt(_ key: String, default fallback: Int) -> Binding<Int> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
    private func preferenceDouble(_ key: String, default fallback: Double) -> Binding<Double> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Double ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
    private func preferenceString(_ key: String, default fallback: String) -> Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: key) ?? fallback }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
    private func datePreference(_ key: String, hour: Int) -> Binding<Date> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Date ?? Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)! }, set: { UserDefaults.standard.set($0, forKey: key) })
    }
    private func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SiliconPulse-settings.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let safe = UserDefaults.standard.dictionaryRepresentation().filter { $0.value is String || $0.value is NSNumber || $0.value is [String] }
        do { let data = try JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys]); try data.write(to: url); model.settingsMessage = "Settings exported." }
        catch { model.settingsMessage = "Could not export settings." }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { model.settingsMessage = "Could not import settings."; return }
        values.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        model.settingsMessage = "Settings imported. Reopen the panel to apply all changes."
    }
    private func resetAllSettings() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key != "AppleLanguages" { UserDefaults.standard.removeObject(forKey: key) }
        model.resetLayout()
        model.menuMetrics = ["Battery %"]
        model.language = "System"
        model.refreshSeconds = 1; model.historyMinutes = 1; model.fahrenheit = false
        model.decimalUnits = false; model.networkBits = false; model.compactRows = false
        model.panelOpacity = 0.94; model.showDockIcon = false; model.reopenPinnedAtLaunch = true
        model.showMenuIcons = true; model.menuSeparator = "Dot"; model.enableHIDTemps = true; model.enableSMCFans = true
        PanelController.active?.setPinned(false)
        model.restartTimer()
    }
}

private struct MenuMetricDropDelegate: DropDelegate {
    let metric: String
    let model: AppModel
    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let value = value as? String else { return }
            Task { @MainActor in model.moveMenuMetric(value, before: metric) }
        }
    }
    func performDrop(info: DropInfo) -> Bool { true }
}
