import Foundation
import Observation
import ServiceManagement

@MainActor @Observable final class AppModel {
    var snapshot = TelemetrySnapshot()
    var history: [Double] = []
    var menuMetric = UserDefaults.standard.string(forKey: "menuMetric") ?? "Battery"
    var refreshSeconds = UserDefaults.standard.double(forKey: "refreshSeconds") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "refreshSeconds")
    var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit")
    var expanded: Set<String> = ["Battery", "Power", "CPU"]
    private var cpuPrevious: [UInt32]?
    private var networkCollector = NetworkCollector()
    private var powerCollector = PowerCollector()
    private var timer: Task<Void, Never>?
    func start(open: Bool) {
        timer?.cancel()
        let interval: UInt64 = open ? UInt64(max(1, refreshSeconds)) : 5
        timer = Task { while !Task.isCancelled { await sample(); try? await Task.sleep(for: .seconds(interval)) } }
    }
    func stop() { timer?.cancel(); timer = nil }
    func sample() async {
        let cpu = CPUCollector().collect(previous: &cpuPrevious)
        var next = TelemetrySnapshot()
        next.battery = BatteryCollector().collect(); next.power = powerCollector.collect(); next.cpu = cpu
        next.memory = MemoryCollector().collect(); next.disk = DiskCollector().collect(); next.network = networkCollector.collect()
        next.processes = ProcessCollector().collect(); next.system = SystemCollector().collect()
        snapshot = next
        history.append((cpu.load ?? 0) * 100); if history.count > 60 { history.removeFirst(history.count - 60) }
    }
    func value(for metric: String) -> String {
        switch metric {
        case "CPU": return DisplayValue.decimal((snapshot.cpu.load ?? 0) * 100, suffix: "%")
        case "Power": return DisplayValue.decimal(snapshot.power.combined, suffix: " W")
        case "Memory": return DisplayValue.bytes(snapshot.memory.used)
        default: return snapshot.battery.percent.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        }
    }
    func toggleLogin() { if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() } }
}
