import Foundation
import CoreFoundation
import Darwin

struct TemperatureSensor: Identifiable, Sendable {
    let id: String
    let name: String
    let celsius: Double
    let group: String
}

/// IOHIDEventSystem is private and version-dependent; unavailable symbols yield an empty reading.
struct HIDSensors {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int64, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventValue = @convention(c) (CFTypeRef, Int64) -> Double
    private let handle: UnsafeMutableRawPointer?
    private let client: CFTypeRef?
    private let copyServices: CopyServices?
    private let copyProperty: CopyProperty?
    private let copyEvent: CopyEvent?
    private let eventValue: EventValue?

    init() {
        let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL)
        handle = library
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let ptr = dlsym(library, name) else { return nil }
            return unsafeBitCast(ptr, to: type)
        }
        let create = symbol("IOHIDEventSystemClientCreate", as: ClientCreate.self)
        let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self)
        copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
        copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
        copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self)
        eventValue = symbol("IOHIDEventGetFloatValue", as: EventValue.self)
        if let create, let setMatching {
            client = create(kCFAllocatorDefault)?.takeRetainedValue()
            if let client {
                let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
                setMatching(client, matching as CFDictionary)
            }
        } else { client = nil }
        _ = handle
    }

    func collect() -> [TemperatureSensor] {
        guard let client, let copyServices, let copyProperty, let copyEvent, let eventValue,
              let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return services.compactMap { service in
            guard let product = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, 15, 0, 0)?.takeRetainedValue() else { return nil }
            let value = eventValue(event, Int64(15 << 16))
            guard value.isFinite, (-20...150).contains(value) else { return nil }
            let lower = product.lowercased()
            let group: String
            if lower.contains("tdie") || lower.contains("pmu") { group = "CPU/SoC" }
            else if lower.contains("gas gauge") || lower.contains("battery") { group = "Battery" }
            else if lower.contains("nand") { group = "SSD" }
            else { group = "Other" }
            return TemperatureSensor(id: product, name: product, celsius: value, group: group)
        }
    }

    func batteryTemperature() -> Double? {
        collect().first(where: { $0.group == "Battery" })?.celsius
    }
}
