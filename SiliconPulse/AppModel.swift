import Foundation
import Observation
import ServiceManagement

@MainActor @Observable final class AppModel {
    var snapshot = TelemetrySnapshot()
    var cpuHistory: [TelemetryPoint] = []; var gpuHistory: [TelemetryPoint] = []
    var diskReadHistory: [TelemetryPoint] = []; var diskWriteHistory: [TelemetryPoint] = []
    var powerHistory: [TelemetryPoint] = []; var batteryPowerHistory: [TelemetryPoint] = []
    var memoryHistory: [TelemetryPoint] = []; var networkDownHistory: [TelemetryPoint] = []; var networkUpHistory: [TelemetryPoint] = []
    var temperatureHistory: [TelemetryPoint] = []; var thermalTimeline: [Int] = []
    var menuMetric = UserDefaults.standard.string(forKey: "menuMetric") ?? "Battery"
    var refreshSeconds = UserDefaults.standard.double(forKey: "refreshSeconds") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "refreshSeconds")
    var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit")
    var processMemorySort = false
    var expanded: Set<String> = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers"]

    private var cpuPrevious: [UInt32]?; private var cpuTotalPrevious: [UInt32]?
    private var networkCollector = NetworkCollector(); private var powerCollector = PowerCollector()
    private var processCollector = ProcessCollector(); private var gpuCollector = GPUCollector()
    private var diskIOCollector = DiskIOCollector(); private var memoryCollector = MemoryCollector()
    private var hidSensors = HIDSensors(); private var bluetoothCollector = BluetoothBatteryCollector(); private var fanCollector = FanCollector()
    private var sampleDates: [String: Date] = [:]
    private var chartIndex = 0
    private var timer: Task<Void, Never>?

    func start(open: Bool) {
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
    func setPopoverOpen(_ open: Bool) { start(open: open) }
    func restartTimer() { start(open: true) }
    func stop() { timer?.cancel(); timer = nil }
    func setProcessMemorySort(_ memory: Bool) { processMemorySort = memory; sampleDates.removeValue(forKey: "Processes") }

    private func due(_ key: String, every seconds: TimeInterval, now: Date) -> Bool {
        guard now.timeIntervalSince(sampleDates[key] ?? .distantPast) >= seconds else { return false }
        sampleDates[key] = now
        return true
    }

    private func sampleMenuMetric() async {
        snapshot.battery = BatteryCollector().collect()
        switch menuMetric {
        case "CPU": snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
        case "Power": snapshot.power = powerCollector.collect()
        case "Memory": snapshot.memory = memoryCollector.collect()
        case "GPU %": snapshot.gpu = gpuCollector.collect()
        case "Disk I/O": snapshot.diskIO = diskIOCollector.collect()
        default: break
        }
    }

    private func samplePopover() async {
        let now = Date()
        chartIndex += 1
        if expanded.contains("Battery"), due("Battery", every: 1, now: now) {
            snapshot.battery = BatteryCollector().collect()
            if snapshot.battery.temperatureC == nil, let hidTemp = snapshot.temperatures.sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = hidTemp }
            append(TelemetryPoint(id: chartIndex, value: snapshot.battery.watts), to: &batteryPowerHistory)
        }
        if expanded.contains("Power"), due("Power", every: 1, now: now) {
            snapshot.power = powerCollector.collect()
            append(TelemetryPoint(id: chartIndex, value: snapshot.power.combined), to: &powerHistory)
        }
        if expanded.contains("CPU"), due("CPU", every: 1, now: now) {
            snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotalPrevious)
            append(TelemetryPoint(id: chartIndex, value: snapshot.cpu.load.map { $0 * 100 }), to: &cpuHistory)
        }
        if expanded.contains("GPU"), due("GPU", every: 1, now: now) {
            snapshot.gpu = gpuCollector.collect()
            append(TelemetryPoint(id: chartIndex, value: snapshot.gpu.utilization), to: &gpuHistory)
        }
        if expanded.contains("Memory"), due("Memory", every: 2, now: now) { snapshot.memory = memoryCollector.collect(); append(TelemetryPoint(id: chartIndex, value: snapshot.memory.usedPercent), to: &memoryHistory) }
        if expanded.contains("Disk"), due("Disk", every: 2, now: now) {
            snapshot.disk = DiskCollector().collect()
            snapshot.diskIO = diskIOCollector.collect()
            if due("SMART", every: 60, now: now) {
                let status = await Task.detached(priority: .utility) { DiskCollector.smartStatus() }.value
                snapshot.disk.smartStatus = status
            }
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.readBytesPerSecond), to: &diskReadHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.diskIO.writeBytesPerSecond), to: &diskWriteHistory)
        }
        if expanded.contains("Network"), due("Network", every: 2, now: now) {
            snapshot.network = networkCollector.collect()
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.downBytesPerSecond), to: &networkDownHistory)
            append(TelemetryPoint(id: chartIndex, value: snapshot.network.upBytesPerSecond), to: &networkUpHistory)
        }
        if expanded.contains("Thermal"), due("Thermal", every: 2, now: now) {
            let sensors = hidSensors.collect()
            let cpuTemps = sensors.filter { $0.group == "CPU/SoC" }.map(\.celsius)
            snapshot.temperatures = TemperatureReading(sensors: sensors, cpuAverage: cpuTemps.isEmpty ? nil : cpuTemps.reduce(0, +) / Double(cpuTemps.count), cpuMaximum: cpuTemps.max())
            if snapshot.battery.temperatureC == nil, let batteryTemp = sensors.first(where: { $0.group == "Battery" })?.celsius { snapshot.battery.temperatureC = batteryTemp }
            append(TelemetryPoint(id: chartIndex, value: snapshot.temperatures.cpuMaximum), to: &temperatureHistory)
            thermalTimeline.append(snapshot.cpu.thermalState); if thermalTimeline.count > 300 { thermalTimeline.removeFirst(thermalTimeline.count - 300) }
        }
        if expanded.contains("Processes"), due("Processes", every: 3, now: now) { snapshot.processes = processCollector.collect(sortByMemory: processMemorySort) }
        if expanded.contains("Sleep blockers"), due("Sleep blockers", every: 5, now: now) { snapshot.sleepBlockers = SleepAssertionCollector().collect() }
        if due("Bluetooth", every: 30, now: now) { snapshot.bluetooth = bluetoothCollector.collect() }
        if due("Fans", every: 30, now: now) { snapshot.fans = fanCollector.collect() }
        if expanded.contains("System"), due("System", every: 5, now: now) { snapshot.system = SystemCollector().collect() }
    }

    private func append(_ point: TelemetryPoint, to values: inout [TelemetryPoint]) {
        values.append(point)
        if values.count > 900 { values.removeFirst(values.count - 900) }
    }
    func value(for metric: String) -> String {
        switch metric {
        case "CPU": return snapshot.cpu.load.map { DisplayValue.decimal($0 * 100, suffix: "%") } ?? "n/a"
        case "Power": return DisplayValue.decimal(snapshot.power.combined, suffix: " W")
        case "Memory": return DisplayValue.bytes(snapshot.memory.used)
        case "GPU %": return snapshot.gpu.utilization.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a"
        case "Disk I/O":
            guard let read = snapshot.diskIO.readBytesPerSecond, let write = snapshot.diskIO.writeBytesPerSecond else { return "n/a" }
            return DisplayValue.decimal((read + write) / 1_000_000, suffix: " MB/s")
        default: return snapshot.battery.percent.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        }
    }
    func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }
}
