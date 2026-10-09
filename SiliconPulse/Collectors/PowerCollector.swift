import Foundation
import CoreFoundation
import Darwin
import IOKit

/// Private IOReport access is isolated here. Missing symbols or usable counters stay unavailable.
struct PowerCollector {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (CFTypeRef?, CFDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef?, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias SimpleInteger = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias ChannelName = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias UnitLabel = @convention(c) (CFDictionary) -> Unmanaged<CFString>?

    private let handle: UnsafeMutableRawPointer?
    private let createSamples: CreateSamples?
    private let createDelta: CreateDelta?
    private let simpleInteger: SimpleInteger?
    private let channelName: ChannelName?
    private let unitLabel: UnitLabel?
    private var subscription: CFTypeRef?
    private var subscribedChannels: CFDictionary?
    private var previousSample: CFDictionary?
    private var previousTime = Date()

    init() {
        let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL)
        handle = library
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        let copyChannels = symbol("IOReportCopyChannelsInGroup", as: CopyChannels.self)
        let createSubscription = symbol("IOReportCreateSubscription", as: CreateSubscription.self)
        createSamples = symbol("IOReportCreateSamples", as: CreateSamples.self)
        createDelta = symbol("IOReportCreateSamplesDelta", as: CreateDelta.self)
        simpleInteger = symbol("IOReportSimpleGetIntegerValue", as: SimpleInteger.self)
        channelName = symbol("IOReportChannelGetChannelName", as: ChannelName.self)
        unitLabel = symbol("IOReportChannelGetUnitLabel", as: UnitLabel.self)
        if let copyChannels, let createSubscription,
           let original = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() {
            let channels = Self.withCLPC(original)
            var subscribed: Unmanaged<CFMutableDictionary>?
            subscription = createSubscription(nil, channels, &subscribed, 0, nil)?.takeRetainedValue()
            subscribedChannels = subscribed?.takeRetainedValue()
        }
        _ = handle // Keep libIOReport loaded while the function pointers are used.
    }

    mutating func collect() -> PowerReading {
        guard let createSamples, let createDelta, let simpleInteger, let channelName, let unitLabel,
              let subscription, let subscribedChannels else { return .unavailable }
        let now = Date()
        guard let sample = createSamples(subscription, subscribedChannels, 0)?.takeRetainedValue() else { return .unavailable }
        guard let previousSample else {
            self.previousSample = sample
            previousTime = now
            return .unavailable
        }
        let elapsed = now.timeIntervalSince(previousTime)
        guard elapsed > 0, elapsed <= 10 else {
            self.previousSample = sample
            previousTime = now
            return .unavailable
        }
        defer { self.previousSample = sample; previousTime = now }
        guard let delta = createDelta(previousSample, sample, 0)?.takeRetainedValue() else { return .unavailable }
        var cpu: Double?, gpu: Double?, ane: Double?, dram: Double?
        var clpcCPU: Double?, clpcGPU: Double?, clpcANE: Double?
        for channel in dictionaries(in: delta) {
            guard let name = channelName(channel)?.takeUnretainedValue() as String? else { continue }
            let unit = (unitLabel(channel)?.takeUnretainedValue() as String? ?? "").lowercased()
            let raw = Double(simpleInteger(channel, 0))
            if ProcessInfo.processInfo.arguments.contains("--dump-ioreport") {
                print("[IOReport] group=Energy Model channel=\(name) unit=\(unit) rawDelta=\(raw)")
            }
            let millijoules: Double
            if unit.contains("mj") { millijoules = raw }
            else if unit.contains("uj") || unit.contains("µj") { millijoules = raw / 1_000 }
            else if unit.contains("nj") { millijoules = raw / 1_000_000 }
            else if unit.contains("joule") || unit == "j" { millijoules = raw * 1_000 }
            else { continue }
            guard raw >= 0 else { continue }
            let watts = millijoules / 1_000 / elapsed
            let normalized = name.lowercased()
            if (channel as NSDictionary)["IOReportGroupName"] as? String == "CLPC" {
                if normalized.contains("cpu") { clpcCPU = watts }
                else if normalized.contains("gpu") { clpcGPU = watts }
                else if normalized.contains("ane") { clpcANE = watts }
                continue
            }
            if normalized.contains("dram") { dram = (dram ?? 0) + watts }
            else if normalized.contains("gpu") { gpu = (gpu ?? 0) + watts }
            else if normalized.contains("ane") || normalized.contains("neural") { ane = (ane ?? 0) + watts }
            else if name.hasPrefix("ECPU") || name.hasPrefix("PCPU") || name.hasPrefix("EACC") || name.hasPrefix("PACC") || name.hasPrefix("CPU Energy") {
                cpu = (cpu ?? 0) + watts
            }
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 { cpu = clpcCPU; ane = clpcANE; dram = nil }
        if let clpcGPU { gpu = clpcGPU }
        let available = [cpu, gpu, ane, dram].compactMap { $0 }
        return PowerReading(cpu: cpu, gpu: gpu, ane: ane, dram: dram, combined: available.isEmpty ? nil : available.reduce(0, +), eFrequencyMHz: nil, pFrequencyMHz: nil, gpuFrequencyMHz: nil, eResidency: nil, pResidency: nil)
    }

    /// macOS 27 may freeze Energy Model CPU/ANE counters. CLPC report IDs are
    /// hardware protocol facts documented by macmon's CLPC discovery, not guessed values.
    /// Unknown drivers/OS versions remain unavailable. No macmon source is incorporated.
    private static func withCLPC(_ original: CFDictionary) -> CFDictionary {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { return original }
        let identifiers: [String: [UInt64]] = [
            "AppleT6000CLPCv3": [0x47479059, 0x4519bf1e, 0x9aaa17f8],
            "AppleT6002CLPC": [0xb501816b, 0x9e2c3e8b, 0x14d5a574],
            "AppleT6020CLPC": [0xe301cd75, 0x8f34cc7a, 0x7415fb0f],
            "AppleT6022CLPC": [0x76f5fd21, 0x90624499, 0x3c097307],
            "AppleT6030CLPC": [0xbe03a01a, 0x472d6c9c, 0xb8990c38],
            "AppleT6031CLPC": [0xd81e0084, 0x1085f98b, 0x313a3be1],
            "AppleT6032CLPC": [0xf4a21308, 0x85e80513, 0x63dc8e25],
            "AppleT6041CLPC": [0x263cf1f0, 0x22e4cf59, 0x7849fb5c],
            "AppleT6050CLPC": [0xd3ab60bb, 0x27cd4ce5, 0x8c0f1c59],
            "AppleT6050dCLPC": [0x18b3010e, 0xedeca11a, 0x188bd883],
            "AppleT8103CLPCv3": [0x2cdd31f2, 0x21becf42, 0x0667fb81],
            "AppleT8112CLPC": [0xb5435137, 0x638d9d52, 0xea089c36],
            "AppleT8122CLPC": [0x54b51c99, 0xce2dd9dc, 0x960afe2f],
            "AppleT8132CLPC": [0x4a854d94, 0x3b3e3b79, 0x1ff4a9ec],
            "AppleT8140CLPC": [0x9bf54436, 0xef70589c, 0x569d941b],
            "AppleT8142CLPC": [0x43708744, 0x6a010933, 0xbc5efdf0],
            "AppleT8152CLPC": [0x485d4bfc, 0x11784654, 0x9380c6bb]
        ]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleCLPC"), &iterator) == KERN_SUCCESS else { return original }
        defer { IOObjectRelease(iterator) }
        let merged = NSMutableDictionary(dictionary: original as NSDictionary)
        let array = NSMutableArray(array: (merged["IOReportChannels"] as? [Any]) ?? [])
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?, driver: UInt64 = 0
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as NSDictionary?,
                  let bundle = props["CFBundleIdentifier"] as? String,
                  let keys = identifiers[bundle.components(separatedBy: ".").last ?? ""],
                  IORegistryEntryGetRegistryEntryID(service, &driver) == KERN_SUCCESS else { continue }
            for (offset, title) in ["CPU Energy", "GPU Energy", "ANE"].enumerated() {
                let counter = (UInt64([16, 25, 24][offset]) << 32) | keys[offset]
                let descriptor = NSMutableDictionary()
                descriptor["DriverID"] = NSNumber(value: driver)
                descriptor["DriverName"] = "AppleCLPC"
                descriptor["IOReportGroupName"] = "CLPC"
                descriptor["IOReportSubGroupName"] = "Energy Counters"
                descriptor["LegendChannel"] = [NSNumber(value: counter), NSNumber(value: UInt64(1) | (2 << 16) | (1 << 32)), title] as [Any]
                descriptor["IOReportChannelInfo"] = NSMutableDictionary(dictionary: ["IOReportChannelUnit": NSNumber(value: (UInt64(3) << 56) | (118 << 32))])
                array.add(descriptor)
            }
        }
        merged["IOReportChannels"] = array
        return merged as CFDictionary
    }

    private func dictionaries(in object: CFDictionary) -> [CFDictionary] {
        var found: [CFDictionary] = []
        func visit(_ value: Any) {
            if let dictionary = value as? NSDictionary {
                if dictionary["LegendChannel"] != nil { found.append((dictionary.mutableCopy() as! NSMutableDictionary) as CFDictionary) }
                dictionary.allValues.forEach(visit)
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(object)
        return found
    }
}

/// Detailed state channels are subscribed only while the monitor is open or recording.
/// This is the same private boundary as power; no guessed frequencies or block counts.
final class ResidencyCollector {
    private typealias Copy = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias Subscribe = @convention(c) (CFTypeRef?, CFDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias Samples = @convention(c) (CFTypeRef?, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias Delta = @convention(c) (CFDictionary, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias Name = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Count = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias Residency = @convention(c) (CFDictionary, Int32) -> Int64
    private struct Group {
        var name: String, subscription: CFTypeRef, channels: CFDictionary
        var previous: CFDictionary?
        var time: Double = 0
    }
    private let library: UnsafeMutableRawPointer?
    private var groups: [Group] = []
    private var frequencyTables: [String: [Double]] = [:]
    private var loggedStates = Set<String>()
    private let samples: Samples?, delta: Delta?, name: Name?, count: Count?, stateName: StateName?, residency: Residency?
    init() {
        frequencyTables = Self.readFrequencyTables()
        let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL)
        library = handle
        func get<T>(_ key: String, _ type: T.Type) -> T? { guard let handle, let pointer = dlsym(handle, key) else { return nil }; return unsafeBitCast(pointer, to: type) }
        let copy = get("IOReportCopyChannelsInGroup", Copy.self), subscribe = get("IOReportCreateSubscription", Subscribe.self)
        samples = get("IOReportCreateSamples", Samples.self); delta = get("IOReportCreateSamplesDelta", Delta.self)
        name = get("IOReportChannelGetChannelName", Name.self); count = get("IOReportStateGetCount", Count.self)
        stateName = get("IOReportStateGetNameForIndex", StateName.self); residency = get("IOReportStateGetResidency", Residency.self)
        guard samples != nil, delta != nil, name != nil, count != nil, stateName != nil, residency != nil, let copy, let subscribe else { return }
        for (key, subgroup) in [("CPU Stats", "CPU Core Performance States"), ("GPU Stats", "GPU Performance States"), ("ANE Stats", ""), ("Neural Engine", ""), ("Media Stats", "")] {
            guard let channels = copy(key as CFString, subgroup.isEmpty ? nil : subgroup as CFString, 0, 0, 0)?.takeRetainedValue() else { continue }
            var subscribed: Unmanaged<CFMutableDictionary>?
            guard let subscription = subscribe(nil, channels, &subscribed, 0, nil)?.takeRetainedValue(), let actual = subscribed?.takeRetainedValue() else { continue }
            groups.append(Group(name: key, subscription: subscription, channels: actual))
        }
    }
    func collect() -> ResidencyReading {
        guard let samples, let delta, let name, let count, let stateName, let residency else { return ResidencyReading() }
        var result: [SensorValue] = []
        let now = ProcessInfo.processInfo.systemUptime
        for index in groups.indices {
            guard let current = samples(groups[index].subscription, groups[index].channels, 0)?.takeRetainedValue() else { continue }
            let previous = groups[index].previous, elapsed = now - groups[index].time
            groups[index].previous = current; groups[index].time = now
            guard let previous, elapsed > 0, elapsed < 10, let difference = delta(previous, current, 0)?.takeRetainedValue() else { continue }
            func visit(_ value: Any) {
                if let dict = value as? NSDictionary {
                    let channel = (dict.mutableCopy() as! NSMutableDictionary) as CFDictionary
                    if dict["LegendChannel"] != nil, let label = name(channel)?.takeUnretainedValue() as String? {
                        let stateCount = count(channel)
                        if stateCount > 0 && stateCount < 512 {
                            var total: Double = 0, active: Double = 0, weighted: Double = 0, weight: Double = 0
                            var foundIdle = false
                            var activeValues: [Double] = []
                            var stateLabels: [String] = []
                            for state in 0..<stateCount {
                                let raw = residency(channel, state)
                                guard raw >= 0 else { continue }
                                let value = Double(raw); total += value
                                let label = (stateName(channel, state)?.takeUnretainedValue() as String? ?? "").lowercased()
                                stateLabels.append(label)
                                let inactive = label.contains("idle") || label.contains("off") || label.contains("down") || label.contains("sleep")
                                if inactive { foundIdle = true }
                                if !inactive { active += value; activeValues.append(value) }
                                if label.contains("mhz") || label.contains("ghz") {
                                    let digits = label.filter { $0.isNumber || $0 == "." }
                                    if let frequency = Double(digits) { weighted += value * frequency * (label.contains("ghz") ? 1000 : 1); weight += value }
                                }
                            }
                            let normalized = label.lowercased()
                            let kind = normalized.contains("gpu") ? "GPU" : normalized.contains("ecpu") || normalized.contains("eacc") ? "E" : normalized.contains("pcpu") || normalized.contains("pacc") ? "P" : ""
                            if weight == 0, let frequencies = frequencyTables[kind], frequencies.count == activeValues.count {
                                for i in frequencies.indices { weighted += frequencies[i] * activeValues[i]; weight += activeValues[i] }
                            }
                            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--monitor-qa=") }), loggedStates.insert(label).inserted {
                                print("STATES \(groups[index].name) \(label): \(stateLabels.joined(separator: ",")) kind=\(kind) table=\(frequencyTables[kind]?.count ?? 0)")
                            }
                            if total > 0 {
                                if foundIdle { result.append(SensorValue(id: groups[index].name + "/" + label, name: label, domain: groups[index].name, value: active / total * 100, unit: "% active residency")) }
                                if weight > 0 { result.append(SensorValue(id: groups[index].name + "/" + label + "/frequency", name: label + " frequency", domain: groups[index].name, value: weighted / weight, unit: "MHz")) }
                            }
                        }
                    }
                    dict.allValues.forEach(visit)
                } else if let array = value as? [Any] { array.forEach(visit) }
            }
            visit(difference)
        }
        return ResidencyReading(sensors: result)
    }
    private static func readFrequencyTables() -> [String: [Double]] {
        let chip = SystemCollector().collect().chip ?? ""
        let cpuScale: Double
        if ["M1", "M2", "M3"].contains(where: { chip.contains($0) }) { cpuScale = 1_000_000 }
        else if ["M4", "M5"].contains(where: { chip.contains($0) }) { cpuScale = 1_000 }
        else { return [:] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: [Double]] = [:]
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS, ["pmgr", "pmgr-child"].contains(String(cString: name)) else { continue }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let dict = props?.takeRetainedValue() as NSDictionary? else { continue }
            for (kind, key) in [("E", "voltage-states1-sram"), ("P", "voltage-states5-sram"), ("GPU", "voltage-states9")] {
                guard let data = dict[key] as? Data, data.count % 8 == 0 else { continue }
                let bytes = [UInt8](data)
                let values = stride(from: 0, to: bytes.count, by: 8).compactMap { offset -> Double? in
                    let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                    return raw > 0 ? Double(raw) / (kind == "GPU" ? 1_000_000 : cpuScale) : nil
                }
                if !values.isEmpty { result[kind] = values }
            }
        }
        return result
    }

}
