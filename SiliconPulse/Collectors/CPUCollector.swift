import Foundation
import Darwin
import Darwin.Mach

struct CPUCollector {
    func collect(previous: inout [UInt32]?) -> CPUReading {
        var info: processor_info_array_t?
        var count = mach_msg_type_number_t()
        var processors = natural_t()
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count)
        guard result == KERN_SUCCESS, let info else { return CPUReading(thermalState: ProcessInfo.processInfo.thermalState.rawValue) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let values = Array(UnsafeBufferPointer(start: info, count: Int(count))).map { UInt32(bitPattern: $0) }
        let old = previous; previous = values
        var cores: [CoreUsage] = []
        let eCount = performanceCoreCounts().e ?? 0
        var eNumber = 0
        var pNumber = 0
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
        return CPUReading(cores: cores, load: load, thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
