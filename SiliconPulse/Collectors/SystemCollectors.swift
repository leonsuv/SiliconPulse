import Foundation
import Darwin
import Darwin.Mach
import IOKit
import CoreWLAN

struct MemoryCollector {
    private var previousPages: (Date, UInt64, UInt64)?

    mutating func collect() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return MemoryReading(used: nil, wired: nil, compressed: nil, pressure: nil) }
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = UInt64(stats.inactive_count) * pageSize
        let used = (UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed: UInt64? = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? UInt64(swap.xsu_used) : nil
        let now = Date()
        let pageIn: Double?, pageOut: Double?
        if let previousPages, now.timeIntervalSince(previousPages.0) > 0 && now.timeIntervalSince(previousPages.0) <= 10 {
            let elapsed = now.timeIntervalSince(previousPages.0)
            pageIn = stats.pageins >= previousPages.1 ? Double(stats.pageins - previousPages.1) / elapsed : nil
            pageOut = stats.pageouts >= previousPages.2 ? Double(stats.pageouts - previousPages.2) / elapsed : nil
        } else { pageIn = nil; pageOut = nil }
        previousPages = (now, stats.pageins, stats.pageouts)
        var total: UInt64 = 0; var totalSize = MemoryLayout<UInt64>.size
        let physical = sysctlbyname("hw.memsize", &total, &totalSize, nil, 0) == 0 ? total : nil
        let percentage = physical.map { $0 > 0 ? Double(used) / Double($0) * 100 : 0 }
        return MemoryReading(used: used, wired: wired, compressed: compressed, pressure: nil, free: free, app: Self.appMemoryFootprint(), cached: cached, swapUsed: swapUsed, pageInPerSecond: pageIn, pageOutPerSecond: pageOut, usedPercent: percentage)
    }
    private static func appMemoryFootprint() -> UInt64? {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return nil }
        var total: UInt64 = 0
        for pid in pids.prefix(Int(bytes)).filter({ $0 > 0 }) {
            var usage: rusage_info_t?
            if proc_pid_rusage(pid, RUSAGE_INFO_V4, &usage) == 0, let usage {
                total &+= usage.assumingMemoryBound(to: rusage_info_v4.self).pointee.ri_phys_footprint
            }
        }
        return total > 0 ? total : nil
    }

}

struct DiskCollector {
    func collect() -> DiskReading {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? root.resourceValues(forKeys: keys) else { return DiskReading(total: nil, free: nil) }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsEjectableKey], options: [.skipHiddenVolumes]) ?? []
        let external = volumes.compactMap { url -> ExternalVolume? in
            guard let info = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsEjectableKey]),
                  info.volumeIsRemovable == true || info.volumeIsEjectable == true else { return nil }
            return ExternalVolume(id: url.path, name: info.volumeName ?? url.lastPathComponent, total: info.volumeTotalCapacity.map(UInt64.init), free: info.volumeAvailableCapacity.map(UInt64.init))
        }
        let filesystem: String? = nil
        return DiskReading(total: values.volumeTotalCapacity.map(UInt64.init), free: values.volumeAvailableCapacity.map(UInt64.init), importantFree: values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }, volumeName: values.volumeName, fileSystem: values.volumeLocalizedFormatDescription ?? filesystem, externalVolumes: external)
    }

    static func smartStatus() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["SMARTStatus"] as? String
    }
}

struct NetworkCollector {
    private var previous: (Date, UInt64, UInt64)?

    mutating func collect() -> NetworkReading {
        var up: UInt64 = 0, down: UInt64 = 0
        var localIP: String?, interfaceName: String?, vpn = false
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0, let first = head {
            var item: UnsafeMutablePointer<ifaddrs>? = first
            while let current = item {
                let entry = current.pointee
                if let address = entry.ifa_addr {
                    let name = String(cString: entry.ifa_name)
                    if address.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                        if name.hasPrefix("en") { up += UInt64(data.ifi_obytes); down += UInt64(data.ifi_ibytes); if interfaceName == nil { interfaceName = name } }
                    } else if address.pointee.sa_family == UInt8(AF_INET) {
                        let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inet_ntoa($0.pointee.sin_addr).map { String(cString: $0) } }
                        if name.hasPrefix("en"), localIP == nil { localIP = ipv4 }
                        if name.hasPrefix("utun"), ipv4 != nil { vpn = true }
                    }
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
        reading.totalUp = up; reading.totalDown = down; reading.localIPv4 = localIP; reading.interfaceName = interfaceName; reading.vpnActive = vpn
        if let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() {
            reading.rssi = wifi.rssiValue(); reading.noise = wifi.noiseMeasurement()
            if let rssi = reading.rssi, let noise = reading.noise { reading.snr = rssi - noise }
            reading.channel = wifi.wlanChannel().map { "\($0.channelNumber)" }
            reading.linkMbps = wifi.transmitRate()
            reading.phyMode = String(describing: wifi.activePHYMode())
            reading.security = String(describing: wifi.security())
            reading.transmitPower = wifi.transmitPower()
        }
        return reading
    }
}

struct SystemCollector {
    func collect() -> SystemReading {
        let model = readString("hw.model")
        let chip = readString("machdep.cpu.brand_string")
        let counts = performanceCoreCounts()
        let totalMemory = readUInt("hw.memsize")
        let version = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist") as? [String: Any]
        var boot = timeval(); var size = MemoryLayout<timeval>.size
        let bootTime: Date? = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 ? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000) : nil
        return SystemReading(chip: chip, model: model, macOS: ProcessInfo.processInfo.operatingSystemVersionString, build: version?["ProductBuildVersion"] as? String, uptime: ProcessInfo.processInfo.systemUptime, bootTime: bootTime, cpuCores: ProcessInfo.processInfo.processorCount, eCores: counts.e, pCores: counts.p, gpuCores: GPUCollector().collect().coreCount, memoryGB: totalMemory.map { Double($0) / 1_000_000_000 })
    }
    private func readString(_ name: String) -> String? { var value = [CChar](repeating: 0, count: 256); var size = value.count; guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }; return String(cString: value) }
    private func readUInt(_ name: String) -> UInt64? { var value: UInt64 = 0; var size = MemoryLayout<UInt64>.size; return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil }
}

func performanceCoreCounts() -> (e: Int?, p: Int?) {
    var efficiency: Int?, performance: Int?
    for level in 0...7 {
        guard let name = sysctlString("hw.perflevel\(level).name"), let count = sysctlInteger("hw.perflevel\(level).logicalcpu") else { continue }
        if name.lowercased().contains("efficiency") { efficiency = count }
        else if name.lowercased().contains("performance") { performance = count }
    }
    return (efficiency, performance)
}
private func sysctlString(_ name: String) -> String? { var value = [CChar](repeating: 0, count: 128); var size = value.count; guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }; return String(cString: value) }
private func sysctlInteger(_ name: String) -> Int? { var value: Int32 = 0; var size = MemoryLayout<Int32>.size; guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }; return Int(value) }
