import SwiftUI
import ServiceManagement
import UserNotifications
import AppKit
import UniformTypeIdentifiers
import Combine

final class SettingsTabSelection: ObservableObject {
    @Published var index: Int
    init(_ index: Int) { self.index = index }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var tabSelection: SettingsTabSelection

    init(tab: Int = 0, tabSelection: SettingsTabSelection? = nil) {
        _tabSelection = StateObject(wrappedValue: tabSelection ?? SettingsTabSelection(tab))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Label("SiliconPulse", systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(.blue).padding(.horizontal, 12).padding(.top, 24)
                VStack(spacing: 4) {
                    ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                        Button { tabSelection.index = index } label: {
                            Label(LocalizedStringKey(tab.0), systemImage: tab.1)
                                .font(.system(size: 13, weight: tabSelection.index == index ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                                .foregroundStyle(tabSelection.index == index ? Color.white : Color.primary)
                                .background(tabSelection.index == index ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityAddTraits(tabSelection.index == index ? .isSelected : [])
                    }
                }
                Spacer()
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0")")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }.padding(.horizontal, 10).frame(width: 180).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey(Self.tabs[min(6, max(0, tabSelection.index))].0))
                    .font(.system(size: 24, weight: .semibold)).padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
                settingsContent
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 760, minHeight: 560)
            .environment(\.locale, model.locale)
    }

    private static let tabs = [("General", "slider.horizontal.3"), ("Menu Bar", "menubar.rectangle"), ("Sections", "rectangle.3.group"), ("Units", "ruler"), ("Notifications", "bell.badge"), ("Advanced", "gearshape.2"), ("Overlay", "rectangle.inset.filled")]

    @ViewBuilder private var settingsContent: some View {
        @Bindable var settings = model
        switch tabSelection.index {
        case 0:
            Form {
                Section("Startup") {
                    Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in model.toggleLogin() }))
                    Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                    Toggle("Reopen pinned panel at launch", isOn: $settings.reopenPinnedAtLaunch)
                    Picker("Language", selection: $settings.language) {
                        Text("System").tag("System"); Text("English").tag("en"); Text("Deutsch").tag("de")
                    }
                }
                Section("Energy") {
                    LowPowerModeControl()
                    Text("Changing Low Power Mode requires administrator authorization.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Sampling and panel") {
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                    }
                    Picker("Refresh interval", selection: $settings.refreshSeconds) {
                        Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0)
                    }.onChange(of: model.refreshSeconds) { _, value in UserDefaults.standard.set(value, forKey: "refreshSeconds"); model.restartTimer() }
                    Picker("History length", selection: $settings.historyMinutes) {
                        Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15)
                    }.onChange(of: model.historyMinutes) { _, value in UserDefaults.standard.set(value, forKey: "historyMinutes") }
                    Toggle("Compact rows", isOn: $settings.compactRows).onChange(of: model.compactRows) { _, value in UserDefaults.standard.set(value, forKey: "compactRows") }
                    LabeledContent("Pinned panel opacity") {
                        Slider(value: $settings.panelOpacity, in: 0.6...1) { Text("Opacity") }.labelsHidden()
                            .frame(width: 170).disabled(!PanelController.sharedPinned)
                    }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }.formStyle(.grouped)
        case 1:
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
            }.formStyle(.grouped)
        case 2:
            Form {
                Section("Card layout") {
                    HStack {
                        Text("Sections").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Visible").frame(width: 60)
                        Text("Expanded").frame(width: 80)
                        Text("Order").frame(width: 54)
                    }.font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(model.sectionOrder.enumerated()), id: \.element) { index, section in
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(section)).frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Visible", isOn: Binding(get: { model.visibleSections.contains(section) }, set: { model.setVisibleSection(section, visible: $0) }))
                                .toggleStyle(.checkbox).labelsHidden().frame(width: 60).accessibilityLabel(Text("Show \(section)"))
                            Toggle("Expanded", isOn: Binding(get: { model.expanded.contains(section) }, set: { if $0 { model.expanded.insert(section) } else { model.expanded.remove(section) } }))
                                .toggleStyle(.checkbox).labelsHidden().frame(width: 80).accessibilityLabel(Text("Expand \(section) by default"))
                            HStack(spacing: 10) {
                                Button { model.moveSection(section, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).accessibilityLabel(Text("Move \(section) up"))
                                Button { model.moveSection(section, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.sectionOrder.count - 1).accessibilityLabel(Text("Move \(section) down"))
                            }.buttonStyle(.plain).frame(width: 54)
                        }.padding(.vertical, 3)
                    }
                    Text("The overview starts with compact cards. Expanded defaults apply to category details.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        case 3:
            Form {
                Section("Temperature and capacity") {
                    Toggle("Use Fahrenheit", isOn: $settings.fahrenheit).onChange(of: model.fahrenheit) { _, value in UserDefaults.standard.set(value, forKey: "fahrenheit") }
                    Toggle("Decimal GB / TB", isOn: $settings.decimalUnits).onChange(of: model.decimalUnits) { _, value in UserDefaults.standard.set(value, forKey: "decimalUnits") }
                    Toggle("Network rates in bits", isOn: $settings.networkBits).onChange(of: model.networkBits) { _, value in UserDefaults.standard.set(value, forKey: "networkBits") }
                    Toggle("Use 24-hour time", isOn: $settings.use24HourTime)
                }
            }.formStyle(.grouped)
        case 4:
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
            }.formStyle(.grouped)
        case 5:
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
                    Link("GitHub project", destination: URL(string: "https://github.com/leonsuv/SiliconPulse")!)
                    Text("MIT License · Private telemetry interfaces: IOReport and AppleSMC sensor access.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        case 6:
            overlaySettings
        default: EmptyView()
        }
    }

    private var overlaySettings: some View {
        @Bindable var preferences = OverlayPreferences.shared
        let controller = OverlayController.active
        return Form {
            Section("Overlay mode") {
                Toggle("Enable telemetry overlay", isOn: Binding(get: { controller?.isActive ?? UserDefaults.standard.bool(forKey: "overlay.active") }, set: { enabled in
                    if enabled { controller?.activate() } else { controller?.deactivate() }
                }))
                Picker("Global shortcut", selection: $preferences.hotKey) {
                    Text("Control–Option–O").tag("⌃⌥O"); Text("Control–Option–Command–O").tag("⌃⌥⌘O")
                    Text("Control–Option–P").tag("⌃⌥P"); Text("Control–Option–H").tag("⌃⌥H")
                }.onChange(of: preferences.hotKey) { _, _ in controller?.preferencesChanged() }
                Text("The shortcut toggles the click-through HUD without changing dashboard pin state.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Metrics and layout") {
                Picker("Layout", selection: $preferences.layout) { Text("Vertical list").tag("List"); Text("Horizontal bar").tag("Bar") }
                    .onChange(of: preferences.layout) { _, _ in controller?.preferencesChanged() }
                ForEach(Array(preferences.metrics.enumerated()), id: \.element) { index, metric in
                    HStack {
                        Toggle(isOn: Binding(get: { preferences.metrics.contains(metric) }, set: { enabled in
                            var values = preferences.metrics
                            if enabled { if !values.contains(metric) { values.append(metric) } } else { values.removeAll { $0 == metric } }
                            controller?.setMetrics(values); if controller == nil { preferences.metrics = values }
                        })) { Label(overlaySettingMetricLabel(metric), systemImage: overlaySymbol(metric)) }
                        Button { var values = preferences.metrics; guard index > 0 else { return }; values.swapAt(index, index - 1); controller?.setMetrics(values); if controller == nil { preferences.metrics = values } } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(index == 0)
                        Button { var values = preferences.metrics; guard index + 1 < values.count else { return }; values.swapAt(index, index + 1); controller?.setMetrics(values); if controller == nil { preferences.metrics = values } } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(index == preferences.metrics.count - 1)
                    }.onDrag { preferences.draggedMetric = metric; return NSItemProvider(object: metric as NSString) }
                        .onDrop(of: [UTType.plainText], delegate: OverlayMetricDropDelegate(metric: metric, preferences: preferences, controller: controller))
                }
                ForEach(OverlayPreferences.allMetrics.filter { !preferences.metrics.contains($0) }, id: \.self) { metric in
                    Toggle(isOn: Binding(get: { false }, set: { enabled in if enabled { var values = preferences.metrics; values.append(metric); controller?.setMetrics(values); if controller == nil { preferences.metrics = values } } })) { Label(overlaySettingMetricLabel(metric), systemImage: overlaySymbol(metric)) }
                }
                Toggle("Show metric names", isOn: $preferences.showLabels)
                Toggle("Show 30-second sparklines", isOn: $preferences.showSparklines)
                Toggle("Compact rows", isOn: $preferences.compact)
            }
            Section("Appearance") {
                Picker("Background", selection: $preferences.background) { Text("None").tag("None"); Text("Subtle dark pill").tag("Subtle dark pill"); Text("Blurred material").tag("Material") }
                LabeledContent("Background opacity") { Slider(value: $preferences.opacity, in: 0.92...1).frame(width: 180) }
                LabeledContent("Text opacity") { Slider(value: $preferences.textOpacity, in: 0.9...1).frame(width: 180) }
                LabeledContent("Corner radius") { Slider(value: $preferences.cornerRadius, in: 0...28).frame(width: 180) }
                LabeledContent("Text scale") { Slider(value: $preferences.scale, in: 0.8...1.6).frame(width: 180) }.onChange(of: preferences.scale) { _, _ in controller?.preferencesChanged() }
                LabeledContent("Sample interval") { Picker("Sample interval", selection: $preferences.refresh) { Text("0.5 s").tag(0.5); Text("1 s").tag(1.0); Text("2 s").tag(2.0); Text("5 s").tag(5.0) }.labelsHidden() }
                Toggle("Color values by thresholds", isOn: $preferences.colorsEnabled)
                HStack { TextField("CPU warning %", value: $preferences.cpuWarning, format: .number); TextField("GPU warning %", value: $preferences.gpuWarning, format: .number) }
                HStack { TextField("RAM warning %", value: $preferences.ramWarning, format: .number); TextField("Temperature warning °C", value: $preferences.temperatureWarning, format: .number) }
                HStack { TextField("Battery red below %", value: $preferences.batteryRed, format: .number); TextField("Battery orange below %", value: $preferences.batteryOrange, format: .number) }
                Toggle("Show hint on enter", isOn: $preferences.hint)
                Toggle("Hide when CPU and GPU are idle", isOn: $preferences.autoHide)
                Toggle("Hide from screen capture", isOn: $preferences.screenshotMode).onChange(of: preferences.screenshotMode) { _, _ in controller?.preferencesChanged() }
            }
            Section("Position and display") {
                Picker("Anchor", selection: $preferences.anchor) { Text("Top left").tag("Top left"); Text("Top center").tag("Top center"); Text("Top right").tag("Top right"); Text("Bottom left").tag("Bottom left"); Text("Bottom center").tag("Bottom center"); Text("Bottom right").tag("Bottom right"); Text("Left center").tag("Left center"); Text("Right center").tag("Right center") }
                    .onChange(of: preferences.anchor) { _, _ in controller?.preferencesChanged() }
                Toggle("Follow display under pointer", isOn: $preferences.followActiveDisplay).onChange(of: preferences.followActiveDisplay) { _, _ in controller?.preferencesChanged() }
                Picker("Saved display", selection: $preferences.displayName) { Text("Main").tag("Main"); ForEach(NSScreen.screens, id: \.localizedName) { Text($0.localizedName).tag($0.localizedName) } }.onChange(of: preferences.displayName) { _, _ in controller?.preferencesChanged() }
                HStack { TextField("Horizontal offset", value: $preferences.offsetX, format: .number); TextField("Vertical offset", value: $preferences.offsetY, format: .number) }
                    .onChange(of: preferences.offsetX) { _, _ in controller?.preferencesChanged() }.onChange(of: preferences.offsetY) { _, _ in controller?.preferencesChanged() }
                Button("Move overlay…") { controller?.beginMoveMode() }
                Button("Preview for 5 seconds") { controller?.preview() }
                Text("Move mode accepts a drag. Press Return, Escape, or Done; it ends after 30 seconds of inactivity.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                HStack { Image(systemName: "cpu"); Text("CPU %"); Spacer(); Text(model.value(for: "CPU %")) }
                    .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                Text("Metrics without available hardware support display n/a.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).tabItem { Label("Overlay", systemImage: "rectangle.inset.filled") }.tag(6)
    }

    private func overlaySettingMetricLabel(_ metric: String) -> String {
        let key = switch metric { case "Battery %": "Battery"; case "Battery W": "Battery power"; case "CPU temp": "CPU temperature"; default: metric }
        return OverlayL10n.text(key, locale: model.locale)
    }
    private func overlaySymbol(_ metric: String) -> String {
        switch metric { case "CPU %", "CPU power W", "CPU temp", "Hottest temp": "cpu"; case "GPU %", "GPU power W": "display"; case "RAM %": "memorychip"; case "Battery %", "Battery W", "Time remaining": "battery.100percent"; case "Network down": "arrow.down"; case "Network up": "arrow.up"; case "Disk read": "arrow.down.to.line"; case "Disk write": "arrow.up.to.line"; default: "waveform.path.ecg" }
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
        model.appearance = "System"
        model.panelOpacity = 0.94; model.showDockIcon = false; model.reopenPinnedAtLaunch = true
        model.showMenuIcons = true; model.menuSeparator = "Dot"; model.enableHIDTemps = true; model.enableSMCFans = true
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

private struct OverlayMetricDropDelegate: DropDelegate {
    let metric: String
    let preferences: OverlayPreferences
    let controller: OverlayController?
    func dropEntered(info: DropInfo) {
        guard let source = preferences.draggedMetric, source != metric,
              let from = preferences.metrics.firstIndex(of: source), let to = preferences.metrics.firstIndex(of: metric) else { return }
        var reordered = preferences.metrics
        reordered.remove(at: from)
        reordered.insert(source, at: to)
        if let controller { controller.setMetrics(reordered) } else { preferences.metrics = reordered }
    }
    func performDrop(info: DropInfo) -> Bool { preferences.draggedMetric = nil; return true }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
