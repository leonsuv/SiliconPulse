import Foundation

struct DetailProcess: Identifiable, Sendable {
    let id: Int32
    var parent: Int32, uid: UInt32, name: String, path: String, status: String
    var cpu: Double?, memory: UInt64?, threads: Int?, faults: UInt64?, cpuSeconds: Double?, started: Date?
    var readRate: Double?, writeRate: Double?
    var architecture: String? = nil, priority: Int? = nil, peak: UInt64? = nil, resident: UInt64? = nil, virtual: UInt64? = nil
    var user: String
    var application: Bool { path.contains(".app/Contents/MacOS/") }
}
struct InspectorRow: Identifiable, Hashable, Sendable {
    var id: String, name: String, value: String
    var path = "", group = "", version = "", vendor = ""
    var modified: Date? = nil, lastOpened: Date? = nil, wired: UInt64? = nil
    var enabled: Bool? = nil, pid: Int32? = nil, size: UInt64? = nil
}
struct SocketReading: Identifiable, Hashable, Sendable {
    var id: String, pid: Int32, process: String, user: String, descriptor: String
    var transport: String, state: String, local: String, remote: String
    var exposure: String {
        if transport == "UNIX" { return "Local IPC" }
        if local.hasPrefix("*") || local.hasPrefix("[::]:") || local.hasPrefix("0.0.0.0:") { return "All interfaces" }
        let address = remote.isEmpty ? local : remote
        if address.hasPrefix("127.") || address.hasPrefix("[::1]") { return "Loopback" }
        if address.hasPrefix("192.168.") || address.hasPrefix("10.") || address.hasPrefix("[fe80:") || address.hasPrefix("[fd") || address.hasPrefix("[fc") { return "Local network" }
        if let first = address.split(separator: ":").first, first.hasPrefix("172."), let n = Int(first.split(separator: ".").dropFirst().first ?? ""), (16...31).contains(n) { return "Local network" }
        return "Internet"
    }
}
struct FlightFrame: Codable, Identifiable, Sendable {
    var id: Int
    var date: Date
    var values: [String: Double]
    var cores: [Double]
    var thermal: Int
}
struct FlightLog: Codable { var version = 1; var chip: String; var frames: [FlightFrame] }
struct BenchmarkResult: Codable, Identifiable, Sendable {
    var id = UUID(), date = Date()
    var kind: String, primary: Double, secondary: Double?, unit: String, notes: String
}
struct SensorValue: Identifiable, Sendable {
    var id: String, name: String, domain: String, value: Double?, unit: String
    var minimum: Double? = nil, maximum: Double? = nil
}
struct ResidencyReading: Sendable {
    var sensors: [SensorValue] = []
}
