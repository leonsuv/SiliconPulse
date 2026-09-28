import Foundation

struct TelemetryPoint: Identifiable, Sendable { let id: Int; let value: Double? }
struct BatteryReading: Sendable {
    var percent: Double?; var charging: Bool?; var externalConnected: Bool?; var fullyCharged: Bool?
    var timeRemainingMinutes: Int?; var timeToFullMinutes: Int?; var cycles: Int?; var health: Double?
    var nominalCapacity: Int?; var designCapacity: Int?; var remainingCapacity: Int?; var fullChargeCapacity: Int?
    var voltage: Double?; var amperage: Double?; var watts: Double?; var temperatureC: Double?; var adapterWatts: Double?
}
struct PowerReading: Sendable {
    var cpu: Double?; var gpu: Double?; var ane: Double?; var dram: Double?; var combined: Double?
    var eFrequencyMHz: Double?; var pFrequencyMHz: Double?; var gpuFrequencyMHz: Double?
    var eResidency: Double?; var pResidency: Double?
    static let unavailable = PowerReading(cpu: nil, gpu: nil, ane: nil, dram: nil, combined: nil, eFrequencyMHz: nil, pFrequencyMHz: nil, gpuFrequencyMHz: nil, eResidency: nil, pResidency: nil)
}
struct CoreUsage: Identifiable, Sendable { let id: Int; let percent: Double; let kind: String; let number: Int }
struct CPUReading: Sendable { var cores: [CoreUsage] = []; var load: Double?; var thermalState: Int }
struct GPUReading: Sendable { var utilization: Double?; var rendererUtilization: Double?; var tilerUtilization: Double?; var memoryInUse: UInt64?; var coreCount: Int? }
struct MemoryReading: Sendable { var used: UInt64?; var wired: UInt64?; var compressed: UInt64?; var pressure: String? }
struct DiskReading: Sendable { var total: UInt64?; var free: UInt64? }
struct DiskIOReading: Sendable { var readBytesPerSecond: Double?; var writeBytesPerSecond: Double?; var readIOPS: Double?; var writeIOPS: Double? }
struct NetworkReading: Sendable { var upBytesPerSecond: Double?; var downBytesPerSecond: Double?; var rssi: Int?; var channel: String?; var linkMbps: Double? }
struct ProcessReading: Identifiable, Sendable { let id: Int32; let name: String; let cpuPercent: Double; let memoryBytes: UInt64 }
struct SleepBlocker: Identifiable, Sendable { let id: Int32; let name: String; let assertions: [String] }
struct SystemReading: Sendable {
    var chip: String?; var model: String?; var macOS: String; var build: String?; var uptime: TimeInterval
    var bootTime: Date?; var cpuCores: Int; var eCores: Int?; var pCores: Int?; var gpuCores: Int?; var memoryGB: Double?
    var sleepAssertions: [String] = []
}
struct TelemetrySnapshot: Sendable {
    var battery = BatteryReading(); var power = PowerReading.unavailable; var cpu = CPUReading(thermalState: 0); var gpu = GPUReading()
    var memory = MemoryReading(); var disk = DiskReading(); var diskIO = DiskIOReading(); var network = NetworkReading()
    var processes: [ProcessReading] = []; var sleepBlockers: [SleepBlocker] = []; var system: SystemReading
    init() { system = SystemReading(macOS: ProcessInfo.processInfo.operatingSystemVersionString, uptime: ProcessInfo.processInfo.systemUptime, cpuCores: ProcessInfo.processInfo.processorCount) }
}
enum DisplayValue {
    static func number<T: BinaryInteger>(_ value: T?) -> String { value.map(String.init) ?? "n/a" }
    static func decimal(_ value: Double?, digits: Int = 1, suffix: String = "") -> String {
        guard let value, value.isFinite else { return "n/a" }
        return "\(value.formatted(.number.precision(.fractionLength(digits))))\(suffix)"
    }
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "n/a" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
