import Foundation
import IOKit

struct FanReading: Identifiable, Sendable { let id: Int; let rpm: Double?; let maximumRPM: Double? }
/// Best-effort public registry lookup; machines without exported AppleSMC fan properties show no card.
struct FanCollector {
    func collect() -> [FanReading] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any],
              let count = (values["FNum"] as? NSNumber)?.intValue else { return [] }
        return (0..<min(count, 16)).map { index in
            FanReading(id: index, rpm: (values["F\(index)Ac"] as? NSNumber)?.doubleValue, maximumRPM: (values["F\(index)Mx"] as? NSNumber)?.doubleValue)
        }
    }
}
