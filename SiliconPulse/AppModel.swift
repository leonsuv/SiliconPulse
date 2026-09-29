import Foundation
import Observation
import ServiceManagement
import AppKit
import UserNotifications

@MainActor @Observable final class OverlayMetricState {
    var text = "n/a"
    var numeric: Double?
    var charging: Bool?
}

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    static let allSections = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers", "System", "Bluetooth", "Fans"]
    static let menuOptions = ["Battery %", "Battery W", "CPU %", "GPU %", "RAM %", "Disk I/O", "Net down", "Net up", "Temperature", "Power W"]

    var snapshot = TelemetrySnapshot()
    var cpuHistory: [TelemetryPoint] = []; var gpuHistory: [TelemetryPoint] = []
    let overlayMetricStates = Dictionary(uniqueKeysWithValues: OverlayPreferences.allMetrics.map { ($0, OverlayMetricState()) })
    var diskReadHistory: [TelemetryPoint] = []; var diskWriteHistory: [TelemetryPoint] = []
    var powerHistory: [TelemetryPoint] = []; var batteryPowerHistory: [TelemetryPoint] = []
    var memoryHistory: [TelemetryPoint] = []; var networkDownHistory: [TelemetryPoint] = []; var networkUpHistory: [TelemetryPoint] = []
    var temperatureHistory: [TelemetryPoint] = []; var thermalTimeline: [Int] = []

    var menuMetrics: [String] = UserDefaults.standard.stringArray(forKey: "menuMetrics") ?? ["Battery %"] {
        didSet { UserDefaults.standard.set(menuMetrics, forKey: "menuMetrics"); onMenuLabelUpdate?() }
    }
    var language = UserDefaults.standard.string(forKey: "appLanguage") ?? "System" { didSet { UserDefaults.standard.set(language, forKey: "appLanguage") } }
    var locale: Locale { Locale(identifier: language == "System" ? Locale.current.identifier : language) }
    var enableHIDTemps = UserDefaults.standard.object(forKey: "enableHIDTemps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enableHIDTemps, forKey: "enableHIDTemps"); if !enableHIDTemps { snapshot.temperatures = TemperatureReading() } }
    }
    var enableSMCFans = UserDefaults.standard.object(forKey: "enableSMCFans") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enableSMCFans, forKey: "enableSMCFans"); if !enableSMCFans { snapshot.fans = [] } else { fansDiscoveryDone = false } }
    }
    var refreshSeconds = UserDefaults.standard.double(forKey: "refreshSeconds") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "refreshSeconds")
    var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit")
    var networkBits = UserDefaults.standard.bool(forKey: "networkBits")
    var decimalUnits = UserDefaults.standard.bool(forKey: "decimalUnits")
    var historyMinutes = UserDefaults.standard.integer(forKey: "historyMinutes") == 0 ? 1 : UserDefaults.standard.integer(forKey: "historyMinutes")
    var compactRows = UserDefaults.standard.bool(forKey: "compactRows")
    var panelOpacity: Double = UserDefaults.standard.object(forKey: "panelOpacity") as? Double ?? 0.94 { didSet { UserDefaults.standard.set(panelOpacity, forKey: "panelOpacity") } }
    var showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon") {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon"); NSApplication.shared.setActivationPolicy(showDockIcon ? .regular : .accessory) }
    }
    var reopenPinnedAtLaunch: Bool = UserDefaults.standard.object(forKey: "reopenPinnedAtLaunch") as? Bool ?? true { didSet { UserDefaults.standard.set(reopenPinnedAtLaunch, forKey: "reopenPinnedAtLaunch") } }
    var showMenuIcons = UserDefaults.standard.object(forKey: "showMenuIcons") as? Bool ?? true { didSet { UserDefaults.standard.set(showMenuIcons, forKey: "showMenuIcons") } }
    var menuSeparator = UserDefaults.standard.string(forKey: "menuSeparator") ?? "Dot" { didSet { UserDefaults.standard.set(menuSeparator, forKey: "menuSeparator") } }
    var use24HourTime = UserDefaults.standard.bool(forKey: "use24HourTime") { didSet { UserDefaults.standard.set(use24HourTime, forKey: "use24HourTime") } }
    var latencyProbeEnabled = UserDefaults.standard.bool(forKey: "latencyProbeEnabled")
    var alertsEnabled = UserDefaults.standard.bool(forKey: "alertsEnabled")
    var batteryAlertThreshold = UserDefaults.standard.double(forKey: "batteryAlertThreshold") == 0 ? 20.0 : UserDefaults.standard.double(forKey: "batteryAlertThreshold")
    var cpuAlertThreshold = UserDefaults.standard.double(forKey: "cpuAlertThreshold") == 0 ? 80.0 : UserDefaults.standard.double(forKey: "cpuAlertThreshold")
    var processMemorySort = false
    var showSettingsResetConfirmation = false
    var settingsMessage = ""
    var sectionOrder: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "sectionOrder") ?? []
        return saved + AppModel.allSections.filter { !saved.contains($0) }
    }() { didSet { UserDefaults.standard.set(sectionOrder, forKey: "sectionOrder") } }
    var visibleSections = Set(UserDefaults.standard.stringArray(forKey: "visibleSections") ?? AppModel.allSections) { didSet { UserDefaults.standard.set(Array(visibleSections), forKey: "visibleSections") } }
    var expanded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "expandedSections") ?? ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers"]) { didSet { UserDefaults.standard.set(Array(expanded), forKey: "expandedSections") } }

    private var cpuPrevious: [UInt32]?; private var cpuTotalPrevious: [UInt32]?
    private var networkCollector = NetworkCollector(); private var powerCollector = PowerCollector()
    private var processCollector = ProcessCollector(); private var gpuCollector = GPUCollector()
    private var diskIOCollector = DiskIOCollector(); private var memoryCollector = MemoryCollector()
    private var memoryPressureMonitor = MemoryPressureMonitor(); private var hidSensors = HIDSensors(); private var bluetoothCollector = BluetoothBatteryCollector(); private var fanCollector = FanCollector()
    private var sampleDates: [String: Date] = [:]
    private var chartIndex = 0
    private var timer: Task<Void, Never>?
    private var overlayTask: Task<Void, Never>?
    private var overlaySampling = false
    private var bluetoothDiscoveryDone = false; private var fansDiscoveryDone = false
    private var highCPUStart: Date?
    private var lastAlerts: [String: Date] = [:]
    private var latencyCollector = NetworkLatencyProbe()
    var onMenuLabelUpdate: (() -> Void)?

    func start(open: Bool) {
        guard !overlaySampling else { return }
        popoverOpen = open
        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                if open { await samplePopover() } else { await sampleMenuMetric() }
                if open { try? await Task.sleep(for: .seconds(max(1, refreshSeconds))) }
                else { try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1)) }
            }
        }
    }
    func startMenuTimer() { if timer == nil { start(open: false) } }
    func setPopoverOpen(_ open: Bool) {
        guard !overlaySampling, popoverOpen != open else { return }
        popoverOpen = open
        if open { bluetoothDiscoveryDone = false; fansDiscoveryDone = false }
        start(open: open)
    }
    private(set) var popoverOpen = false
    func restartTimer() { start(open: popoverOpen) }
    func stop() { timer?.cancel(); timer = nil; overlayTask?.cancel(); overlayTask = nil }
    func beginOverlaySampling(metrics: [String], interval: Double) {
        overlaySampling = true
        timer?.cancel(); timer = nil
        overlayTask?.cancel()
        overlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.overlaySampling {
                self.sampleOverlay(metrics: metrics)
                try? await Task.sleep(for: .seconds(max(0.5, interval)))
            }
        }
    }
    func pauseOverlaySampling() {
        overlayTask?.cancel(); overlayTask = nil
    }
    func endOverlaySampling(reopen: Bool) {
        overlaySampling = false
        overlayTask?.cancel(); overlayTask = nil
        start(open: reopen)
    }
    private func sampleOverlay(metrics: [String]) {
        let now = Date(); chartIndex += 1
        let selected = Set(metrics)
        if !selected.isDisjoint(with: ["Battery %", "Battery W", "Time remaining"]) {
            let started = ProcessInfo.processInfo.systemUptime
            snapshot.battery = BatteryCollector().collect()
            traceOverlaySample("battery", started)
            if OverlayPreferences.shared.showSparklines { append(TelemetryPoint(id: chartIndex, value: snapshot.battery.watts), to: &batteryPowerHistory) }
        }
        if selected.contains("Thermal state") {
            snapshot.cpu.thermalState = ProcessInfo.processInfo.thermalState.rawValue
        }
        if selected.contains("CPU %") || selected.contains("CPU power W") || selected.contains("Total power W") {
            let started = ProcessInfo.processInfo.systemUptime
            snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
            traceOverlaySample("cpu", started)
            if OverlayPreferences.shared.showSparklines { append(TelemetryPoint(id: chartIndex, value: snapshot.cpu.load.map { $0 * 100 }), to: &cpuHistory) }
        }
        if selected.contains("GPU %") || selected.contains("GPU power W") || selected.contains("Total power W") {
            let started = ProcessInfo.processInfo.systemUptime
            snapshot.gpu = gpuCollector.collect()
            traceOverlaySample("gpu", started)
            if OverlayPreferences.shared.showSparklines { append(TelemetryPoint(id: chartIndex, value: snapshot.gpu.utilization), to: &gpuHistory) }
        }
        if !selected.isDisjoint(with: ["CPU power W", "GPU power W", "Total power W"]) { snapshot.power = powerCollector.collect() }
        if selected.contains("RAM %") {
            let started = ProcessInfo.processInfo.systemUptime
            snapshot.memory = memoryCollector.collect()
            traceOverlaySample("memory", started); snapshot.memory.pressure = memoryPressureMonitor.state
            if OverlayPreferences.shared.showSparklines { append(TelemetryPoint(id: chartIndex, value: snapshot.memory.usedPercent), to: &memoryHistory) }
        }
        if selected.contains("Network down") || selected.contains("Network up") { snapshot.network = networkCollector.collect() }
        if selected.contains("Disk read") || selected.contains("Disk write") {
            snapshot.diskIO = diskIOCollector.collect()
            if OverlayPreferences.shared.showSparklines {
                append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.readBytesPerSecond), to: &diskReadHistory)
                append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.writeBytesPerSecond), to: &diskWriteHistory)
            }
        }
        if (selected.contains("CPU temp") || selected.contains("Hottest temp")), due("OverlayTemperature", every: 3, now: now) {
            let started = ProcessInfo.processInfo.systemUptime
            let sensors = hidSensors.collect()
            traceOverlaySample("temperature", started); let cpuTemps = sensors.filter { $0.group == "CPU/SoC" }.map(\.celsius)
            snapshot.temperatures = TemperatureReading(sensors: sensors, cpuAverage: cpuTemps.isEmpty ? nil : cpuTemps.reduce(0, +) / Double(cpuTemps.count), cpuMaximum: cpuTemps.max())
            if OverlayPreferences.shared.showSparklines { append(TelemetryPoint(id: chartIndex, value: snapshot.temperatures.cpuMaximum), to: &temperatureHistory) }
        }
        if selected.contains("Top process"), due("OverlayProcesses", every: 3, now: now) {
            let started = ProcessInfo.processInfo.systemUptime
            snapshot.processes = processCollector.collect(sortByMemory: false)
            traceOverlaySample("process", started)
        }
        publishOverlayMetricValues(selected, now: now)
        if (snapshot.cpu.load ?? 0) >= 0.1 || (snapshot.gpu.utilization ?? 0) >= 10 { OverlayController.active?.noteActivity() }
    }

    private func publishOverlayMetricValues(_ metrics: Set<String>, now: Date) {
        let s = snapshot
        for metric in metrics {
            guard let state = overlayMetricStates[metric] else { continue }
            let text: String
            let numeric: Double?
            switch metric {
            case "CPU %": numeric = s.cpu.load.map { $0 * 100 }; text = numeric.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
            case "GPU %": numeric = s.gpu.utilization; text = numeric.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
            case "RAM %": numeric = s.memory.usedPercent; text = numeric.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
            case "CPU power W": numeric = s.power.cpu; text = overlayPower(s.power.cpu)
            case "GPU power W": numeric = s.power.gpu; text = overlayPower(s.power.gpu)
            case "Total power W": numeric = s.power.combined; text = overlayPower(s.power.combined)
            case "Battery %": numeric = s.battery.percent.map { $0 * 100 }; text = numeric.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
            case "Battery W": numeric = s.battery.watts; text = s.battery.watts.map { overlayPower(abs($0)) } ?? "n/a"
            case "Time remaining": numeric = nil; text = s.battery.timeRemainingMinutes.map { DisplayValue.duration(Double($0 * 60)) } ?? "n/a"
            case "CPU temp": numeric = s.temperatures.cpuAverage; text = overlayTemperature(s.temperatures.cpuAverage)
            case "Hottest temp": numeric = s.temperatures.cpuMaximum; text = overlayTemperature(s.temperatures.cpuMaximum)
            case "Network down": numeric = s.network.downBytesPerSecond; text = formatRate(numeric)
            case "Network up": numeric = s.network.upBytesPerSecond; text = formatRate(numeric)
            case "Disk read": numeric = s.diskIO.readBytesPerSecond; text = formatRate(numeric)
            case "Disk write": numeric = s.diskIO.writeBytesPerSecond; text = formatRate(numeric)
            case "Thermal state":
                numeric = nil
                let states = ["Nominal", "Fair", "Serious", "Critical"]
                text = states.indices.contains(s.cpu.thermalState) ? OverlayL10n.text(states[s.cpu.thermalState], locale: locale) : "n/a"
            case "Top process": numeric = nil; text = s.processes.first.map { "\($0.name) · \(Int($0.cpuPercent))%" } ?? "n/a"
            case "Clock time": numeric = nil; text = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
            default: continue
            }
            if state.text != text { state.text = text }
            if state.numeric != numeric { state.numeric = numeric }
            if state.charging != s.battery.charging { state.charging = s.battery.charging }
        }
    }

    private func overlayPower(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "n/a" }
        if abs(watts) < 1 { return DisplayValue.decimal(watts * 1000, digits: 0, suffix: " mW") }
        return DisplayValue.decimal(watts, digits: 1, suffix: " W")
    }

    private func overlayTemperature(_ celsius: Double?) -> String {
        guard let celsius else { return "n/a" }
        return DisplayValue.decimal(fahrenheit ? celsius * 9 / 5 + 32 : celsius, digits: 0, suffix: fahrenheit ? "°F" : "°C")
    }
    func setProcessMemorySort(_ memory: Bool) { processMemorySort = memory; sampleDates.removeValue(forKey: "Processes") }
    func setVisibleSection(_ section: String, visible: Bool) {
        if visible { visibleSections.insert(section); if section == "Bluetooth" { bluetoothDiscoveryDone = false }; if section == "Fans" { fansDiscoveryDone = false } }
        else { visibleSections.remove(section); expanded.remove(section) }
        UserDefaults.standard.set(Array(visibleSections), forKey: "visibleSections")
    }
    func moveSection(from source: IndexSet, to destination: Int) {
        var updated = sectionOrder
        let moving = source.map { updated[$0] }
        for index in source.sorted(by: >) { updated.remove(at: index) }
        updated.insert(contentsOf: moving, at: min(destination, updated.count))
        sectionOrder = updated
        UserDefaults.standard.set(updated, forKey: "sectionOrder")
    }
    func moveSection(_ section: String, by offset: Int) {
        guard let index = sectionOrder.firstIndex(of: section) else { return }
        let target = index + offset
        guard sectionOrder.indices.contains(target) else { return }
        sectionOrder.swapAt(index, target)
    }
    func moveSection(_ section: String, before destination: String) {
        guard section != destination, let source = sectionOrder.firstIndex(of: section), let target = sectionOrder.firstIndex(of: destination) else { return }
        sectionOrder.remove(at: source)
        sectionOrder.insert(section, at: min(target > source ? target - 1 : target, sectionOrder.count))
    }
    func moveMenuMetric(_ metric: String, by offset: Int) {
        guard let index = menuMetrics.firstIndex(of: metric) else { return }
        let target = index + offset
        guard menuMetrics.indices.contains(target) else { return }
        menuMetrics.swapAt(index, target)
    }
    func moveMenuMetric(_ metric: String, before destination: String) {
        guard metric != destination, let source = menuMetrics.firstIndex(of: metric), let target = menuMetrics.firstIndex(of: destination) else { return }
        menuMetrics.remove(at: source)
        menuMetrics.insert(metric, at: min(target > source ? target - 1 : target, menuMetrics.count))
    }
    func resetLayout() {
        sectionOrder = AppModel.allSections
        visibleSections = Set(AppModel.allSections)
        expanded = Set(["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers"])
    }
    func setAlertsEnabled(_ value: Bool) {
        alertsEnabled = value
        UserDefaults.standard.set(value, forKey: "alertsEnabled")
        if value { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
    }
    func setLatencyProbeEnabled(_ value: Bool) { latencyProbeEnabled = value; UserDefaults.standard.set(value, forKey: "latencyProbeEnabled") }

    private func due(_ key: String, every seconds: TimeInterval, now: Date) -> Bool {
        guard now.timeIntervalSince(sampleDates[key] ?? .distantPast) >= seconds else { return false }
        sampleDates[key] = now; return true
    }
    private func sampleMenuMetric() async {
        snapshot.battery = BatteryCollector().collect()
        for metric in menuMetrics {
            switch metric {
            case "CPU %": snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
            case "Power W": snapshot.power = powerCollector.collect()
            case "RAM %": snapshot.memory = memoryCollector.collect()
            case "GPU %": snapshot.gpu = gpuCollector.collect()
            case "Disk I/O": snapshot.diskIO = diskIOCollector.collect()
            case "Net down", "Net up": snapshot.network = networkCollector.collect()
            case "Temperature":
                let sensors = hidSensors.collect(); snapshot.temperatures.sensors = sensors
                let cpu = sensors.filter { $0.group == "CPU/SoC" }.map(\.celsius)
                snapshot.temperatures.cpuAverage = cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count)
                snapshot.temperatures.cpuMaximum = cpu.max()
            default: break
            }
        }
        onMenuLabelUpdate?()
    }
    private func samplePopover() async {
        let now = Date(); chartIndex += 1
        if (visibleSections.contains("Battery") || menuMetrics.contains("Battery %") || menuMetrics.contains("Battery W")), due("Battery", every: 1, now: now) {
            snapshot.battery = BatteryCollector().collect()
            if snapshot.battery.temperatureC == nil, let fallback = snapshot.temperatures.sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = fallback }
            append(TelemetryPoint(id: chartIndex, value: snapshot.battery.watts), to: &batteryPowerHistory)
        }
        if visibleSections.contains("Power"), expanded.contains("Power"), due("Power", every: 1, now: now) {
            snapshot.power = powerCollector.collect(); append(TelemetryPoint(id: chartIndex, value: snapshot.power.combined), to: &powerHistory)
        }
        if visibleSections.contains("CPU"), due("CPU", every: 1, now: now) {
            snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
            append(TelemetryPoint(id: chartIndex, value: snapshot.cpu.load.map { $0 * 100 }), to: &cpuHistory)
        }
        if visibleSections.contains("GPU"), due("GPU", every: 1, now: now) {
            snapshot.gpu = gpuCollector.collect(); append(TelemetryPoint(id: chartIndex, value: snapshot.gpu.utilization), to: &gpuHistory)
        }
        if visibleSections.contains("Memory"), due("Memory", every: 2, now: now) {
            snapshot.memory = memoryCollector.collect(); snapshot.memory.pressure = memoryPressureMonitor.state; append(TelemetryPoint(id: chartIndex, value: snapshot.memory.usedPercent), to: &memoryHistory)
        }
        if visibleSections.contains("Disk"), expanded.contains("Disk"), due("Disk", every: 2, now: now) {
            snapshot.disk = DiskCollector().collect(); snapshot.diskIO = diskIOCollector.collect()
            if due("SMART", every: 60, now: now) { snapshot.disk.smartStatus = await Task.detached(priority: .utility) { DiskCollector.smartStatus() }.value }
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.readBytesPerSecond), to: &diskReadHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.writeBytesPerSecond), to: &diskWriteHistory)
        }
        if visibleSections.contains("Network"), expanded.contains("Network"), due("Network", every: 2, now: now) {
            snapshot.network = networkCollector.collect()
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.downBytesPerSecond), to: &networkDownHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.upBytesPerSecond), to: &networkUpHistory)
            if latencyProbeEnabled, due("Latency", every: 5, now: now) {
                let host = UserDefaults.standard.string(forKey: "latencyHost") ?? "1.1.1.1"
                snapshot.network.latencyMs = await Task.detached(priority: .utility) { NetworkLatencyProbe.measure(host: host) }.value
            }
        }
        if visibleSections.contains("Thermal"), expanded.contains("Thermal"), enableHIDTemps, due("Thermal", every: 2, now: now) {
            let sensors = hidSensors.collect(); let cpuTemps = sensors.filter { $0.group == "CPU/SoC" }.map(\.celsius)
            snapshot.temperatures = TemperatureReading(sensors: sensors, cpuAverage: cpuTemps.isEmpty ? nil : cpuTemps.reduce(0, +) / Double(cpuTemps.count), cpuMaximum: cpuTemps.max())
            if snapshot.battery.temperatureC == nil, let batteryTemp = sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = batteryTemp }
            append(TelemetryPoint(id: chartIndex, value: snapshot.temperatures.cpuMaximum), to: &temperatureHistory)
            thermalTimeline.append(snapshot.cpu.thermalState); if thermalTimeline.count > 150 { thermalTimeline.removeFirst(thermalTimeline.count - 300) }
        }
        let screenshotMode = ProcessInfo.processInfo.arguments.contains("--release-screenshot")
        if !screenshotMode, visibleSections.contains("Processes"), expanded.contains("Processes"), due("Processes", every: 3, now: now) { snapshot.processes = processCollector.collect(sortByMemory: processMemorySort) }
        if !screenshotMode, visibleSections.contains("Sleep blockers"), expanded.contains("Sleep blockers"), due("Sleep blockers", every: 5, now: now) { snapshot.sleepBlockers = SleepAssertionCollector().collect() }
        if !screenshotMode, visibleSections.contains("Bluetooth") {
            if !bluetoothDiscoveryDone { snapshot.bluetooth = bluetoothCollector.collect(); bluetoothDiscoveryDone = true; sampleDates["Bluetooth"] = now }
            else if !snapshot.bluetooth.isEmpty && expanded.contains("Bluetooth"), due("Bluetooth", every: 30, now: now) { snapshot.bluetooth = bluetoothCollector.collect() }
        }
        if !screenshotMode, visibleSections.contains("Fans"), enableSMCFans {
            if !fansDiscoveryDone { snapshot.fans = fanCollector.collect(); fansDiscoveryDone = true; sampleDates["Fans"] = now }
            else if !snapshot.fans.isEmpty && expanded.contains("Fans"), due("Fans", every: 30, now: now) { snapshot.fans = fanCollector.collect() }
        }
        if visibleSections.contains("System"), expanded.contains("System"), due("System", every: 5, now: now) { snapshot.system = SystemCollector().collect() }
        evaluateAlerts(now: now)
        onMenuLabelUpdate?()
    }
    private func traceOverlaySample(_ domain: String, _ start: TimeInterval) {
        guard ProcessInfo.processInfo.arguments.contains("--overlay-qa-timing") else { return }
        print("OVERLAY_SAMPLE \(domain) \((ProcessInfo.processInfo.systemUptime - start) * 1000)ms")
    }

    private func append(_ point: TelemetryPoint, to values: inout [TelemetryPoint]) {
        values.append(point)
        let oldest = chartIndex - historyMinutes * 60
        while let first = values.first, first.id < oldest { values.removeFirst() }
    }
    func formatBytes(_ value: UInt64?) -> String {
        guard let value else { return "n/a" }
        let base = decimalUnits ? 1_000.0 : 1_024.0
        let units = decimalUnits ? ["B", "KB", "MB", "GB", "TB"] : ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = Double(value); var index = 0
        while amount >= base && index < units.count - 1 { amount /= base; index += 1 }
        return "\(amount.formatted(.number.precision(.fractionLength(index == 0 ? 0 : 1)))) \(units[index])"
    }
    func formatRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite else { return "n/a" }
        let amount = bytesPerSecond * (networkBits ? 8 : 1)
        let base = networkBits ? 1_000.0 : 1_000.0
        let units = networkBits ? ["bit/s", "kbit/s", "Mbit/s", "Gbit/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = amount; var index = 0
        while value >= base && index < units.count - 1 { value /= base; index += 1 }
        return value.formatted(.number.locale(locale).precision(.fractionLength(1))) + " \(units[index])"
    }
    func value(for metric: String) -> String {
        switch metric {
        case "Battery W": return DisplayValue.decimal(snapshot.battery.watts, suffix: " W")
        case "CPU %": return snapshot.cpu.load.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        case "Power W": return DisplayValue.decimal(snapshot.power.combined, suffix: " W")
        case "Memory", "RAM %": return metric == "RAM %" ? DisplayValue.decimal(snapshot.memory.usedPercent, digits: 0, suffix: "%") : formatBytes(snapshot.memory.used)
        case "GPU %": return snapshot.gpu.utilization.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
        case "Disk I/O": return formatRate(snapshot.diskIO.readBytesPerSecond.map { $0 + (snapshot.diskIO.writeBytesPerSecond ?? 0) })
        case "Net down": return formatRate(snapshot.network.downBytesPerSecond)
        case "Net up": return formatRate(snapshot.network.upBytesPerSecond)
        case "Temperature": return snapshot.temperatures.cpuMaximum.map { DisplayValue.decimal(fahrenheit ? $0 * 9 / 5 + 32 : $0, digits: 0, suffix: fahrenheit ? "°F" : "°C") } ?? "n/a"
        default: return snapshot.battery.percent.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        }
    }
    func menuSymbol(for metric: String) -> String {
        switch metric { case "Battery %", "Battery W": "battery.100percent"; case "CPU %": "cpu"; case "GPU %": "display"; case "RAM %": "memorychip"; case "Disk I/O": "internaldrive"; case "Net down": "arrow.down"; case "Net up": "arrow.up"; case "Temperature": "thermometer.medium"; default: "bolt.fill" }
    }
    func copySnapshot() {
        var lines = ["SiliconPulse — \(Date.now.formatted())"]
        lines += ["Battery: \(value(for: "Battery %"))", "Battery power: \(value(for: "Battery W"))", "CPU: \(value(for: "CPU %"))", "GPU: \(value(for: "GPU %"))", "Power: \(value(for: "Power W"))", "Memory: \(formatBytes(snapshot.memory.used))", "Disk I/O: \(value(for: "Disk I/O"))", "Network down/up: \(value(for: "Net down")) / \(value(for: "Net up"))", "Temperature: \(value(for: "Temperature"))", "Thermal state: \(snapshot.cpu.thermalState)"]
        if UserDefaults.standard.bool(forKey: "copyProcessNames") { lines += snapshot.processes.map { "Process \($0.name): \(DisplayValue.decimal($0.cpuPercent, digits: 0, suffix: "%"))" } }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
    func diagnosticDump() -> String {
        [
            "SiliconPulse \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")",
            "macOS: \(snapshot.system.macOS)",
            "Chip: \(snapshot.system.chip ?? "n/a")",
            "Model: \(snapshot.system.model ?? "n/a")",
            "CPU cores: \(snapshot.system.cpuCores) (E: \(snapshot.system.eCores.map(String.init) ?? "n/a"), P: \(snapshot.system.pCores.map(String.init) ?? "n/a"))",
            "Battery: \(value(for: "Battery %")); health: \(snapshot.battery.health.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a")",
            "CPU load: \(value(for: "CPU %")); GPU load: \(value(for: "GPU %"))",
            "Power: \(value(for: "Power W")); memory: \(formatBytes(snapshot.memory.used))",
            "Thermal state: \(["Nominal", "Fair", "Serious", "Critical"].indices.contains(snapshot.cpu.thermalState) ? ["Nominal", "Fair", "Serious", "Critical"][snapshot.cpu.thermalState] : "n/a")"
        ].joined(separator: "\n")
    }
    private func evaluateAlerts(now: Date) {
        guard alertsEnabled else { highCPUStart = nil; return }
        if preferenceEnabled("alertBatteryLow", fallback: true), let percent = snapshot.battery.percent, percent * 100 < batteryAlertThreshold { notify("battery", title: "Low battery", body: "Battery is below \(Int(batteryAlertThreshold))%.", now: now) }
        if preferenceEnabled("alertBatteryFull", fallback: false), snapshot.battery.fullyCharged == true { notify("batteryFull", title: "Battery fully charged", body: "The battery is fully charged.", now: now) }
        if preferenceEnabled("alertThermal", fallback: true), snapshot.cpu.thermalState >= 2 { notify("thermal", title: "High thermal pressure", body: "Thermal state is serious or critical.", now: now) }
        if preferenceEnabled("alertCPU", fallback: true), snapshot.processes.contains(where: { $0.cpuPercent >= cpuAlertThreshold }) {
            if highCPUStart == nil { highCPUStart = now }
            let duration = UserDefaults.standard.object(forKey: "alertCPUSeconds") as? Int ?? 30
            if let since = highCPUStart, now.timeIntervalSince(since) >= Double(duration) { notify("cpu", title: "High process CPU", body: "A process has exceeded the configured CPU threshold for \(duration) seconds.", now: now) }
        } else { highCPUStart = nil }
        if preferenceEnabled("alertMemoryPressure", fallback: false), (snapshot.memory.pressure == "Warning" || snapshot.memory.pressure == "Critical") {
            notify("memoryPressure", title: "Memory pressure", body: "Memory pressure is \(snapshot.memory.pressure ?? "high").", now: now)
        }
        if preferenceEnabled("alertSMART", fallback: true), snapshot.disk.smartStatus?.localizedCaseInsensitiveContains("fail") == true { notify("smart", title: "Storage health warning", body: "SMART reports a failing status.", now: now) }
        let diskLimit = UserDefaults.standard.object(forKey: "alertDiskGB") as? Double ?? 10
        if preferenceEnabled("alertDiskLow", fallback: false), let free = snapshot.disk.free, Double(free) < diskLimit * 1_000_000_000 { notify("diskLow", title: "Low disk space", body: "Boot volume free space is below the configured limit.", now: now) }
        let hotLimit = UserDefaults.standard.object(forKey: "alertTemperatureC") as? Double ?? 90
        if preferenceEnabled("alertTemperature", fallback: false), let hot = snapshot.temperatures.sensors.map(\.celsius).max(), hot >= hotLimit { notify("hotTemperature", title: "High temperature", body: "A temperature sensor exceeded the configured limit.", now: now) }
        let bluetoothLimit = UserDefaults.standard.object(forKey: "alertBluetoothPercent") as? Int ?? 15
        if preferenceEnabled("alertBluetooth", fallback: false), let device = snapshot.bluetooth.first(where: { $0.percent <= bluetoothLimit }) { notify("bluetooth", title: "Bluetooth battery low", body: "\(device.name) is below the configured battery threshold.", now: now) }
    }
    private func preferenceEnabled(_ key: String, fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private func notify(_ id: String, title: String, body: String, now: Date) {
        let cooldown = UserDefaults.standard.object(forKey: "alertCooldownMinutes") as? Int ?? 10
        guard now.timeIntervalSince(lastAlerts[id] ?? .distantPast) >= Double(cooldown * 60) else { return }
        if let start = UserDefaults.standard.object(forKey: "quietHoursStart") as? Date,
           let end = UserDefaults.standard.object(forKey: "quietHoursEnd") as? Date {
            let calendar = Calendar.current
            let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let begin = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
            let finish = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
            let quiet = begin <= finish ? minute >= begin && minute < finish : minute >= begin || minute < finish
            if quiet { return }
        }
        lastAlerts[id] = now
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "siliconpulse.\(id)", content: content, trigger: nil))
    }
    func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }
}
