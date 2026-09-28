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
        if let old = previous, now.timeIntervalSince(old.0) > 0 {
            let elapsed = now.timeIntervalSince(old.0)
            reading.upBytesPerSecond = Double(up >= old.1 ? up - old.1 : 0) / elapsed
            reading.downBytesPerSecond = Double(down >= old.2 ? down - old.2 : 0) / elapsed
        }
        previous = (now, up, down)
        if let interface = CWWiFiClient.shared().interface(), interface.powerOn() {
            reading.rssi = interface.rssiValue(); reading.channel = interface.wlanChannel().map { "\($0.channelNumber)" }
            reading.linkMbps = interface.transmitRate()
        }
        return reading
    }
}
struct ProcessCollector {
    func collect() -> [ProcessReading] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes)).filter { $0 > 0 }.compactMap { pid in
            var info = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { return nil }
            let name = proc_name(pid)
            return ProcessReading(id: pid, name: name.isEmpty ? "Process \(pid)" : name, cpuPercent: Double(info.pti_total_user + info.pti_total_system))
        }.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5).map { $0 }
    }
    private func proc_name(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = Darwin.proc_name(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : ""
    }
}
struct SystemCollector {
    func collect() -> SystemReading {
        var model: size_t = 0; sysctlbyname("hw.model", nil, &model, nil, 0)
        var bytes = [CChar](repeating: 0, count: Int(model)); if model > 0 { sysctlbyname("hw.model", &bytes, &model, nil, 0) }
        let chip = runSysctl("machdep.cpu.brand_string") ?? runSysctl("hw.optional.arm.FEAT_FlagM")
        let e = runInt("hw.perflevel0.logicalcpu"), p = runInt("hw.perflevel1.logicalcpu")
        let totalMemory = runUInt("hw.memsize")
        return SystemReading(chip: chip, model: String(cString: bytes), macOS: ProcessInfo.processInfo.operatingSystemVersionString, uptime: ProcessInfo.processInfo.systemUptime, cpuCores: ProcessInfo.processInfo.processorCount, eCores: e, pCores: p, memoryGB: totalMemory.map { Double($0) / 1_073_741_824 })
    }
    private func runSysctl(_ name: String) -> String? { var value = [CChar](repeating: 0, count: 256); var size = value.count; guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }; return String(cString: value) }
    private func runInt(_ name: String) -> Int? { var v: Int32 = 0; var n = MemoryLayout<Int32>.size; return sysctlbyname(name, &v, &n, nil, 0) == 0 ? Int(v) : nil }
    private func runUInt(_ name: String) -> UInt64? { var v: UInt64 = 0; var n = MemoryLayout<UInt64>.size; return sysctlbyname(name, &v, &n, nil, 0) == 0 ? v : nil }
}
