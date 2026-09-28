import Foundation
import Darwin
import Darwin.Mach

struct CPUCollector {
    func collect(previous: inout [UInt32]?, previousTotal: inout [UInt32]?) -> CPUReading {
        var info: processor_info_array_t?
        var count = mach_msg_type_number_t()
        var processors = natural_t()
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count)
        guard result == KERN_SUCCESS, let info else { return CPUReading(thermalState: ProcessInfo.processInfo.thermalState.rawValue) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let values = Array(UnsafeBufferPointer(start: info, count: Int(count))).map { UInt32(bitPattern: $0) }
        let old = previous
        previous = values
        let eCount = performanceCoreCounts().e ?? 0
        var eNumber = 0, pNumber = 0
        var cores: [CoreUsage] = []
        for index in 0..<Int(processors) {
            let base = index * Int(CPU_STATE_MAX)
            guard base + 3 < values.count else { continue }
            let total = (0..<4).reduce(UInt32(0)) { $0 &+ values[base + $1] }
            let oldTotal = old.flatMap { oldValues in oldValues.count > base + 3 ? (0..<4).reduce(UInt32(0)) { sum, offset in sum &+ oldValues[base + offset] } : nil }
            let oldIdle = old.flatMap { $0.count > base + Int(CPU_STATE_IDLE) ? $0[base + Int(CPU_STATE_IDLE)] : nil }
            let delta = oldTotal.map { total &- $0 } ?? 0
            let idleDelta = oldIdle.map { values[base + Int(CPU_STATE_IDLE)] &- $0 } ?? 0
            let use = delta > 0 ? Double(delta &- idleDelta) / Double(delta) : 0
            let kind = index < eCount ? "E" : "P"
            if kind == "E" { eNumber += 1 } else { pNumber += 1 }
            cores.append(CoreUsage(id: index, percent: max(0, min(1, use)), kind: kind, number: kind == "E" ? eNumber : pNumber))
        }
        let load = cores.isEmpty ? nil : cores.map(\.percent).reduce(0, +) / Double(cores.count)
        let eValues = cores.filter { $0.kind == "E" }.map(\.percent)
        let pValues = cores.filter { $0.kind == "P" }.map(\.percent)

        var totalStats = [integer_t](repeating: 0, count: Int(CPU_STATE_MAX))
        var statsCount = mach_msg_type_number_t(totalStats.count)
        let globalStatus = totalStats.withUnsafeMutableBufferPointer { buffer in
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, buffer.baseAddress!, &statsCount)
        }
        var previousGlobal = previousTotal
        var user: Double?, system: Double?, idle: Double?
        if globalStatus == KERN_SUCCESS {
            let current = totalStats.map { UInt32(bitPattern: $0) }
            if let oldGlobal = previousGlobal, oldGlobal.count >= 4 {
                let deltas = (0..<4).map { current[$0] &- oldGlobal[$0] }
                let sum = deltas.reduce(UInt32(0), &+)
                if sum > 0 {
                    user = Double(deltas[Int(CPU_STATE_USER)] &+ deltas[Int(CPU_STATE_NICE)]) / Double(sum) * 100
                    system = Double(deltas[Int(CPU_STATE_SYSTEM)]) / Double(sum) * 100
                    idle = Double(deltas[Int(CPU_STATE_IDLE)]) / Double(sum) * 100
                }
            }
            previousTotal = current
            previousGlobal = current
        }
        var averages = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&averages, 3)
        let loadAverage = loadCount > 0 ? Array(averages.prefix(Int(loadCount))) : []
        var pids = [pid_t](repeating: 0, count: 4096)
        let pidBytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let processCount = pidBytes > 0 ? pids.prefix(Int(pidBytes)).filter { $0 > 0 }.count : nil
        return CPUReading(cores: cores, load: load, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                          user: user, system: system, idle: idle, loadAverage: loadAverage, processCount: processCount,
                          eAverage: eValues.isEmpty ? nil : eValues.reduce(0, +) / Double(eValues.count),
                          pAverage: pValues.isEmpty ? nil : pValues.reduce(0, +) / Double(pValues.count))
    }
}
