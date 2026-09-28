import Foundation
import IOKit

struct DiskIOCollector {
    private var previousTotals: (readBytes: UInt64, writeBytes: UInt64, readOps: UInt64, writeOps: UInt64)?
    private var previousDate: Date?

    mutating func collect() -> DiskIOReading {
        var totals = (readBytes: UInt64(0), writeBytes: UInt64(0), readOps: UInt64(0), writeOps: UInt64(0))
        var hasReadBytes = false, hasWriteBytes = false, hasReadOps = false, hasWriteOps = false
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return DiskIOReading() }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any],
                  let stats = values["Statistics"] as? [String: Any] else { continue }
            if let value = stats["Bytes (Read)"] as? NSNumber { totals.readBytes &+= value.uint64Value; hasReadBytes = true }
            if let value = stats["Bytes (Write)"] as? NSNumber { totals.writeBytes &+= value.uint64Value; hasWriteBytes = true }
            if let value = stats["Operations (Read)"] as? NSNumber { totals.readOps &+= value.uint64Value; hasReadOps = true }
            if let value = stats["Operations (Write)"] as? NSNumber { totals.writeOps &+= value.uint64Value; hasWriteOps = true }
        }
        guard hasReadBytes || hasWriteBytes || hasReadOps || hasWriteOps else { return DiskIOReading() }
        let now = Date()
        defer { previousTotals = totals; previousDate = now }
        guard let old = previousTotals, let oldDate = previousDate else { return DiskIOReading() }
        let elapsed = now.timeIntervalSince(oldDate)
        guard elapsed > 0, elapsed <= 10 else { return DiskIOReading() }
        func rate(_ current: UInt64?, _ previous: UInt64) -> Double? {
            guard let current, current >= previous else { return nil }
            return Double(current - previous) / elapsed
        }
        return DiskIOReading(
            readBytesPerSecond: rate(hasReadBytes ? totals.readBytes : nil, old.readBytes),
            writeBytesPerSecond: rate(hasWriteBytes ? totals.writeBytes : nil, old.writeBytes),
            readIOPS: rate(hasReadOps ? totals.readOps : nil, old.readOps),
            writeIOPS: rate(hasWriteOps ? totals.writeOps : nil, old.writeOps)
        )
    }
}
