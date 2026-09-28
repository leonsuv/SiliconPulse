import Foundation
import Darwin
import Darwin.Mach
import IOKit
import CoreWLAN

struct MemoryCollector {
    func collect() -> MemoryReading {
        var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        guard status == KERN_SUCCESS else { return MemoryReading() }
        let page = UInt64(vm_kernel_page_size)
        let wired = UInt64(stats.wire_count) * page, compressed = UInt64(stats.compressor_page_count) * page
        let used = (UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let pressure = ProcessInfo.processInfo.thermalState == .critical ? "Critical" : "Normal"
        return MemoryReading(used: used, wired: wired, compressed: compressed, pressure: pressure)
    }
}
struct DiskCollector {
    func collect() -> DiskReading {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]), let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else { return DiskReading() }
        return DiskReading(total: UInt64(total), free: UInt64(free))
    }
}
struct NetworkCollector {
    private var previous: (Date, UInt64, UInt64)?
    mutating func collect() -> NetworkReading {
        var up: UInt64 = 0, down: UInt64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0, let first = head {
            var item: UnsafeMutablePointer<ifaddrs>? = first
            while let current = item {
                let entry = current.pointee
                if String(cString: entry.ifa_name).hasPrefix("en"), entry.ifa_addr.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    up += UInt64(data.ifi_obytes); down += UInt64(data.ifi_ibytes)
                }
                item = entry.ifa_next
            }
            freeifaddrs(first)
        }
        let now = Date(); var reading = NetworkReading()
        if let old = previous {
            let elapsed = now.timeIntervalSince(old.0)
            if elapsed > 0 && elapsed <= 10 {
                if up >= old.1 { reading.upBytesPerSecond = Double(up - old.1) / elapsed }
                if down >= old.2 { reading.downBytesPerSecond = Double(down - old.2) / elapsed }
            }
        }
        previous = (now, up, down)
        if let interface = CWWiFiClient.shared().interface(), interface.powerOn() {
            reading.rssi = interface.rssiValue(); reading.channel = interface.wlanChannel().map { "\($0.channelNumber)" }
            reading.linkMbps = interface.transmitRate()
        }
        return reading
    }
}
struct SystemCollector {
    func collect() -> SystemReading {
        var model: size_t = 0; sysctlbyname("hw.model", nil, &model, nil, 0)
        var bytes = [CChar](repeating: 0, count: Int(model)); if model > 0 { sysctlbyname("hw.model", &bytes, &model, nil, 0) }
        let chip = runSysctl("machdep.cpu.brand_string") ?? runSysctl("hw.optional.arm.FEAT_FlagM")
        let counts = performanceCoreCounts()
        let totalMemory = runUInt("hw.memsize")
        let version = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist") as? [String: Any]
        let build = version?["ProductBuildVersion"] as? String
        var boot = timeval()
        var bootSize = MemoryLayout<timeval>.size
        let bootDate: Date? = sysctlbyname("kern.boottime", &boot, &bootSize, nil, 0) == 0 ? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000) : nil
        return SystemReading(chip: chip, model: String(cString: bytes), macOS: ProcessInfo.processInfo.operatingSystemVersionString, build: build, uptime: ProcessInfo.processInfo.systemUptime, bootTime: bootDate, cpuCores: ProcessInfo.processInfo.processorCount, eCores: counts.e, pCores: counts.p, gpuCores: GPUCollector().collect().coreCount, memoryGB: totalMemory.map { Double($0) / 1_073_741_824 })
    }
    private func runSysctl(_ name: String) -> String? { var value = [CChar](repeating: 0, count: 256); var size = value.count; guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }; return String(cString: value) }
    private func runInt(_ name: String) -> Int? { var v: Int32 = 0; var n = MemoryLayout<Int32>.size; return sysctlbyname(name, &v, &n, nil, 0) == 0 ? Int(v) : nil }
    private func runUInt(_ name: String) -> UInt64? { var v: UInt64 = 0; var n = MemoryLayout<UInt64>.size; return sysctlbyname(name, &v, &n, nil, 0) == 0 ? v : nil }
}

func performanceCoreCounts() -> (e: Int?, p: Int?) {
    var efficiency: Int?
    var performance: Int?
    for level in 0...7 {
        guard let name = sysctlString("hw.perflevel\(level).name"),
              let count = sysctlInteger("hw.perflevel\(level).logicalcpu") else { continue }
        let lower = name.lowercased()
        if lower.contains("efficiency") { efficiency = count }
        else if lower.contains("performance") { performance = count }
    }
    return (efficiency, performance)
}

private func sysctlString(_ name: String) -> String? {
    var value = [CChar](repeating: 0, count: 128)
    var size = value.count
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return String(cString: value)
}
private func sysctlInteger(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}
