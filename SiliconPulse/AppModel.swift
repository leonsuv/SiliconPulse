import Foundation
import Observation
import ServiceManagement

@MainActor @Observable final class AppModel {
    var snapshot = TelemetrySnapshot()
    var cpuHistory: [TelemetryPoint] = []
    var gpuHistory: [TelemetryPoint] = []
    var diskReadHistory: [TelemetryPoint] = []
    var diskWriteHistory: [TelemetryPoint] = []
    var powerHistory: [TelemetryPoint] = []
    var batteryPowerHistory: [TelemetryPoint] = []
    var menuMetric = UserDefaults.standard.string(forKey: "menuMetric") ?? "Battery"
    var refreshSeconds = UserDefaults.standard.double(forKey: "refreshSeconds") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "refreshSeconds")
    var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit")
    var processMemorySort = false
    var expanded: Set<String> = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers"]

    private var cpuPrevious: [UInt32]?
    private var networkCollector = NetworkCollector()
    private var powerCollector = PowerCollector()
    private var processCollector = ProcessCollector()
    private var gpuCollector = GPUCollector()
    private var diskIOCollector = DiskIOCollector()
    private var processSampleDate: Date?
    private var sleepSampleDate: Date?
    private var chartIndex = 0
    private var timer: Task<Void, Never>?

    func start(open: Bool) {
        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                if open { await samplePopover() } else { await sampleMenuMetric() }
                let interval = open ? max(1, refreshSeconds) : 5
                if open { try? await Task.sleep(for: .seconds(interval)) }
                else { try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(1)) }
            }
        }
    }
    func startMenuTimer() { if timer == nil { start(open: false) } }
    func setPopoverOpen(_ open: Bool) { start(open: open) }
    func restartTimer() { start(open: true) }
    func setProcessMemorySort(_ memory: Bool) {
        processMemorySort = memory
        processSampleDate = nil
    }
    func stop() { timer?.cancel(); timer = nil }

    private func sampleMenuMetric() async {
        snapshot.battery = BatteryCollector().collect()
        switch menuMetric {
        case "CPU": snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious)
        case "Power": snapshot.power = powerCollector.collect()
        case "Memory": snapshot.memory = MemoryCollector().collect()
        case "GPU %": snapshot.gpu = gpuCollector.collect()
        case "Disk I/O": snapshot.diskIO = diskIOCollector.collect()
        default: break
        }
    }

    private func samplePopover() async {
        let cpu = CPUCollector().collect(previous: &cpuPrevious)
        var next = TelemetrySnapshot()
        next.battery = BatteryCollector().collect()
        next.power = powerCollector.collect()
        next.cpu = cpu
        next.gpu = gpuCollector.collect()
        next.diskIO = diskIOCollector.collect()
        next.memory = MemoryCollector().collect()
        next.disk = DiskCollector().collect()
        next.network = networkCollector.collect()
        next.system = SystemCollector().collect()
        let now = Date()
        if processSampleDate.map({ now.timeIntervalSince($0) >= 3 }) ?? true {
            next.processes = processCollector.collect(sortByMemory: processMemorySort)
            processSampleDate = now
        } else { next.processes = snapshot.processes }
        if sleepSampleDate.map({ now.timeIntervalSince($0) >= 5 }) ?? true {
            next.sleepBlockers = SleepAssertionCollector().collect()
            sleepSampleDate = now
        } else { next.sleepBlockers = snapshot.sleepBlockers }
        snapshot = next
        chartIndex += 1
        append(TelemetryPoint(id: chartIndex, value: cpu.load.map { $0 * 100 }), to: &cpuHistory)
        append(TelemetryPoint(id: chartIndex, value: next.gpu.utilization), to: &gpuHistory)
        append(TelemetryPoint(id: chartIndex, value: next.diskIO.readBytesPerSecond), to: &diskReadHistory)
        append(TelemetryPoint(id: chartIndex, value: next.diskIO.writeBytesPerSecond), to: &diskWriteHistory)
        append(TelemetryPoint(id: chartIndex, value: next.power.combined), to: &powerHistory)
        append(TelemetryPoint(id: chartIndex, value: next.battery.watts), to: &batteryPowerHistory)
    }

    private func append(_ point: TelemetryPoint, to values: inout [TelemetryPoint]) {
        values.append(point)
        if values.count > 60 { values.removeFirst(values.count - 60) }
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
