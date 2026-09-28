import Foundation
import Darwin

struct ProcessCollector {
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousWallNanoseconds: UInt64?
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    mutating func collect(sortByMemory: Bool = false) -> [ProcessReading] {
        var pids = [pid_t](repeating: 0, count: 4096)
        // proc_listallpids returns a PID count, not a byte count.
        let pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard pidCount > 0 else { return [] }
        let wallNow = mach_absolute_time()
        let wallNowNs = UInt64((Double(wallNow) * Double(timebase.numer)) / Double(timebase.denom))
        let oldWall = previousWallNanoseconds
        var nextCPU: [Int32: UInt64] = [:]
        var readings: [ProcessReading] = []
        for pid in pids.prefix(min(Int(pidCount), pids.count)).filter({ $0 > 0 }) {
            var info = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            let cpuNs = UInt64((Double(ticks) * Double(timebase.numer)) / Double(timebase.denom))
            nextCPU[pid] = cpuNs
            guard let oldCPU = previousCPU[pid], let oldWall, wallNowNs > oldWall else { continue }
            let wallDelta = wallNowNs - oldWall
            guard wallDelta <= 10_000_000_000 else { continue }
            let cpuDelta = cpuNs >= oldCPU ? cpuNs - oldCPU : 0
            let footprint = UInt64(info.pti_resident_size)
            let name = processName(pid)
            let percent = Double(cpuDelta) / Double(wallDelta) * 100
            readings.append(ProcessReading(id: pid, name: name.isEmpty ? "Process \(pid)" : name, cpuPercent: percent, memoryBytes: footprint))
        }
        previousCPU = nextCPU
        previousWallNanoseconds = wallNowNs
        if sortByMemory { return readings.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(8).map { $0 } }
        return readings.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8).map { $0 }
    }

    private func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let count = Darwin.proc_name(pid, &buffer, UInt32(buffer.count))
        return count > 0 ? String(cString: buffer) : ""
    }
}
