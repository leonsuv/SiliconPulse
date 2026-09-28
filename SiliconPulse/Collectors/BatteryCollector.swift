import Foundation
import IOKit

struct BatteryCollector {
    func collect() -> BatteryReading {
        var result = BatteryReading()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return result }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return result }
        let nested = dict["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? { (nested[key] as? NSNumber) ?? (dict[key] as? NSNumber) }
        func int(_ key: String) -> Int? { number(key).map { Int(truncating: $0) } }
        let nominal = int("NominalChargeCapacity"), design = int("DesignCapacity")
        result.percent = number("CurrentCapacity").map { $0.doubleValue / 100 }
        result.charging = (dict["IsCharging"] as? NSNumber)?.boolValue
        result.cycles = int("CycleCount"); result.nominalCapacity = nominal; result.designCapacity = design
        result.health = Self.health(nominal: nominal, design: design)
        result.voltage = number("Voltage").map { $0.doubleValue / 1_000 }
        let rawCurrent = number("InstantAmperage")?.uint64Value ?? number("Amperage")?.uint64Value
        if let rawCurrent { result.amperage = Double(Int64(bitPattern: rawCurrent)) / 1_000 }
        if let voltage = number("Voltage"), let rawCurrent { result.watts = voltage.doubleValue * Double(Int64(bitPattern: rawCurrent)) / 1_000_000 }
        if let temperature = number("Temperature") { result.temperatureC = temperature.doubleValue / 100 }
        if let full = int("FullChargeCapacity"), let design, design > 0 { result.percent = Double(full) / Double(design) }
        if let charging = result.charging, let watts = result.watts { result.watts = charging ? abs(watts) : -abs(watts) }
        result.adapterWatts = (dict["AdapterDetails"] as? [String: Any]).flatMap { ($0["Watts"] as? NSNumber)?.doubleValue }
        result.timeRemainingMinutes = int("TimeRemaining").flatMap { $0 > 0 ? $0 : nil }
        return result
    }
    static func health(nominal: Int?, design: Int?) -> Double? {
        guard let nominal, let design, nominal > 0, design > 0 else { return nil }
        return Double(nominal) / Double(design)
    }
}
