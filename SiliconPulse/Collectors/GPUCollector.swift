import Foundation
import IOKit

struct GPUCollector {
    func collect() -> GPUReading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != IO_OBJECT_NULL else { return GPUReading() }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else { return GPUReading() }
        let stats = values["PerformanceStatistics"] as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? { stats[key] as? NSNumber }
        var cores = (values["gpu-core-count"] as? NSNumber)?.intValue
        if cores == nil {
            var parentEntry: io_registry_entry_t = IO_OBJECT_NULL
            let parent = IORegistryEntryGetParentEntry(service, kIOServicePlane, &parentEntry)
            if parent == KERN_SUCCESS {
                var parentProperties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(parentEntry, &parentProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let parentValues = parentProperties?.takeRetainedValue() as? [String: Any] {
                    cores = (parentValues["gpu-core-count"] as? NSNumber)?.intValue
                }
                IOObjectRelease(parentEntry)
            }
        }
        return GPUReading(
            utilization: number("Device Utilization %")?.doubleValue,
            rendererUtilization: number("Renderer Utilization %")?.doubleValue,
            tilerUtilization: number("Tiler Utilization %")?.doubleValue,
            memoryInUse: number("In use system memory")?.uint64Value,
            coreCount: cores
        )
    }
}
