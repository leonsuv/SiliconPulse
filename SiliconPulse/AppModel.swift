import Foundation
import Observation
import ServiceManagement
import AppKit
import UserNotifications

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    static let allSections = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers", "System", "Bluetooth", "Fans"]
    static let menuOptions = ["Battery %", "Battery W", "CPU %", "GPU %", "RAM %", "Disk I/O", "Net down", "Net up", "Temperature", "Power W"]

    var snapshot = TelemetrySnapshot()
    var cpuHistory: [TelemetryPoint] = []; var gpuHistory: [TelemetryPoint] = []
    var diskReadHistory: [TelemetryPoint] = []; var diskWriteHistory: [TelemetryPoint] = []
    var powerHistory: [TelemetryPoint] = []; var batteryPowerHistory: [TelemetryPoint] = []
    var memoryHistory: [TelemetryPoint] = []; var networkDownHistory: [TelemetryPoint] = []; var networkUpHistory: [TelemetryPoint] = []
    var temperatureHistory: [TelemetryPoint] = []; var thermalTimeline: [Int] = []

    var menuMetrics: [String] = UserDefaults.standard.stringArray(forKey: "menuMetrics") ?? ["Battery %"] {
        didSet { UserDefaults.standard.set(menuMetrics, forKey: "menuMetrics") }
    }
    var refreshSeconds = UserDefaults.standard.double(forKey: "refreshSeconds") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "refreshSeconds")
    var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit")
    var networkBits = UserDefaults.standard.bool(forKey: "networkBits")
    var decimalUnits = UserDefaults.standard.bool(forKey: "decimalUnits")
    var historyMinutes = UserDefaults.standard.integer(forKey: "historyMinutes") == 0 ? 1 : UserDefaults.standard.integer(forKey: "historyMinutes")
    var compactRows = UserDefaults.standard.bool(forKey: "compactRows")
    var latencyProbeEnabled = UserDefaults.standard.bool(forKey: "latencyProbeEnabled")
    var alertsEnabled = UserDefaults.standard.bool(forKey: "alertsEnabled")
    var batteryAlertThreshold = UserDefaults.standard.double(forKey: "batteryAlertThreshold") == 0 ? 20.0 : UserDefaults.standard.double(forKey: "batteryAlertThreshold")
    var cpuAlertThreshold = UserDefaults.standard.double(forKey: "cpuAlertThreshold") == 0 ? 80.0 : UserDefaults.standard.double(forKey: "cpuAlertThreshold")
    var processMemorySort = false
    var sectionOrder: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "sectionOrder") ?? []
        return saved + AppModel.allSections.filter { !saved.contains($0) }
    }()
    var visibleSections = Set(UserDefaults.standard.stringArray(forKey: "visibleSections") ?? AppModel.allSections)
    var expanded: Set<String> = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers"]

    private var cpuPrevious: [UInt32]?; private var cpuTotalPrevious: [UInt32]?
    private var networkCollector = NetworkCollector(); private var powerCollector = PowerCollector()
    private var processCollector = ProcessCollector(); private var gpuCollector = GPUCollector()
    private var diskIOCollector = DiskIOCollector(); private var memoryCollector = MemoryCollector()
    private var memoryPressureMonitor = MemoryPressureMonitor(); private var hidSensors = HIDSensors(); private var bluetoothCollector = BluetoothBatteryCollector(); private var fanCollector = FanCollector()
    private var sampleDates: [String: Date] = [:]
    private var chartIndex = 0
    private var timer: Task<Void, Never>?
    private var bluetoothDiscoveryDone = false; private var fansDiscoveryDone = false
    private var highCPUStart: Date?
    private var lastAlerts: [String: Date] = [:]
    private var latencyCollector = NetworkLatencyProbe()
    var onMenuLabelUpdate: (() -> Void)?

    func start(open: Bool) {
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
        guard popoverOpen != open else { return }
        popoverOpen = open
        if open { bluetoothDiscoveryDone = false; fansDiscoveryDone = false }
        start(open: open)
    }
    private(set) var popoverOpen = false
    func restartTimer() { start(open: popoverOpen) }
    func stop() { timer?.cancel(); timer = nil }
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
        if due("Battery", every: 1, now: now) {
            snapshot.battery = BatteryCollector().collect()
            if snapshot.battery.temperatureC == nil, let fallback = snapshot.temperatures.sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = fallback }
            append(TelemetryPoint(id: chartIndex, value: snapshot.battery.watts), to: &batteryPowerHistory)
        }
        if expanded.contains("Power"), due("Power", every: 1, now: now) {
            snapshot.power = powerCollector.collect(); append(TelemetryPoint(id: chartIndex, value: snapshot.power.combined), to: &powerHistory)
        }
        if due("CPU", every: 1, now: now) {
            snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
            append(TelemetryPoint(id: chartIndex, value: snapshot.cpu.load.map { $0 * 100 }), to: &cpuHistory)
        }
        if due("GPU", every: 1, now: now) {
            snapshot.gpu = gpuCollector.collect(); append(TelemetryPoint(id: chartIndex, value: snapshot.gpu.utilization), to: &gpuHistory)
        }
        if due("Memory", every: 2, now: now) {
            snapshot.memory = memoryCollector.collect(); snapshot.memory.pressure = memoryPressureMonitor.state; append(TelemetryPoint(id: chartIndex, value: snapshot.memory.usedPercent), to: &memoryHistory)
        }
        if expanded.contains("Disk"), due("Disk", every: 2, now: now) {
            snapshot.disk = DiskCollector().collect(); snapshot.diskIO = diskIOCollector.collect()
            if due("SMART", every: 60, now: now) { snapshot.disk.smartStatus = await Task.detached(priority: .utility) { DiskCollector.smartStatus() }.value }
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.readBytesPerSecond), to: &diskReadHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.writeBytesPerSecond), to: &diskWriteHistory)
        }
        if expanded.contains("Network"), due("Network", every: 2, now: now) {
            snapshot.network = networkCollector.collect()
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.downBytesPerSecond), to: &networkDownHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.upBytesPerSecond), to: &networkUpHistory)
            if latencyProbeEnabled, due("Latency", every: 5, now: now) { snapshot.network.latencyMs = await Task.detached(priority: .utility) { NetworkLatencyProbe.measure() }.value }
        }
        if expanded.contains("Thermal"), due("Thermal", every: 2, now: now) {
            let sensors = hidSensors.collect(); let cpuTemps = sensors.filter { $0.group == "CPU/SoC" }.map(\.celsius)
            snapshot.temperatures = TemperatureReading(sensors: sensors, cpuAverage: cpuTemps.isEmpty ? nil : cpuTemps.reduce(0, +) / Double(cpuTemps.count), cpuMaximum: cpuTemps.max())
            if snapshot.battery.temperatureC == nil, let batteryTemp = sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = batteryTemp }
            append(TelemetryPoint(id: chartIndex, value: snapshot.temperatures.cpuMaximum), to: &temperatureHistory)
            thermalTimeline.append(snapshot.cpu.thermalState); if thermalTimeline.count > 150 { thermalTimeline.removeFirst(thermalTimeline.count - 300) }
        }
        if expanded.contains("Processes"), due("Processes", every: 3, now: now) { snapshot.processes = processCollector.collect(sortByMemory: processMemorySort) }
        if expanded.contains("Sleep blockers"), due("Sleep blockers", every: 5, now: now) { snapshot.sleepBlockers = SleepAssertionCollector().collect() }
        if visibleSections.contains("Bluetooth") {
            if !bluetoothDiscoveryDone { snapshot.bluetooth = bluetoothCollector.collect(); bluetoothDiscoveryDone = true; sampleDates["Bluetooth"] = now }
            else if !snapshot.bluetooth.isEmpty && expanded.contains("Bluetooth"), due("Bluetooth", every: 30, now: now) { snapshot.bluetooth = bluetoothCollector.collect() }
        }
        if visibleSections.contains("Fans") {
            if !fansDiscoveryDone { snapshot.fans = fanCollector.collect(); fansDiscoveryDone = true; sampleDates["Fans"] = now }
            else if !snapshot.fans.isEmpty && expanded.contains("Fans"), due("Fans", every: 30, now: now) { snapshot.fans = fanCollector.collect() }
        }
        if expanded.contains("System"), due("System", every: 5, now: now) { snapshot.system = SystemCollector().collect() }
        evaluateAlerts(now: now)
        onMenuLabelUpdate?()
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
        return DisplayValue.decimal(value, suffix: " \(units[index])")
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
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
    private func evaluateAlerts(now: Date) {
        guard alertsEnabled else { highCPUStart = nil; return }
        if let percent = snapshot.battery.percent, percent * 100 < batteryAlertThreshold { notify("battery", title: "Low battery", body: "Battery is below \(Int(batteryAlertThreshold))%.", now: now) }
        if snapshot.cpu.thermalState >= 2 { notify("thermal", title: "High thermal pressure", body: "Thermal state is serious or critical.", now: now) }
        if snapshot.processes.contains(where: { $0.cpuPercent >= cpuAlertThreshold }) {
            if highCPUStart == nil { highCPUStart = now }
            if let since = highCPUStart, now.timeIntervalSince(since) >= 30 { notify("cpu", title: "High process CPU", body: "A process has exceeded the configured CPU threshold for 30 seconds.", now: now) }
        } else { highCPUStart = nil }
        if snapshot.disk.smartStatus?.localizedCaseInsensitiveContains("fail") == true { notify("smart", title: "Storage health warning", body: "SMART reports a failing status.", now: now) }
    }
    private func notify(_ id: String, title: String, body: String, now: Date) {
        guard now.timeIntervalSince(lastAlerts[id] ?? .distantPast) >= 600 else { return }
        lastAlerts[id] = now
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "siliconpulse.\(id)", content: content, trigger: nil))
    }
    func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }
}
