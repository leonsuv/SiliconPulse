import Foundation
import IOKit

struct BluetoothBattery: Identifiable, Sendable { let id: String; let name: String; let percent: Int }
struct BluetoothBatteryCollector {
    func collect() -> [BluetoothBattery] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [BluetoothBattery] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any],
                  let percent = (values["BatteryPercent"] as? NSNumber)?.intValue else { continue }
            let name = values["Product"] as? String ?? "Bluetooth device"
            devices.append(BluetoothBattery(id: "\(name)-\(devices.count)", name: name, percent: percent))
        }
        return devices
    }
}
