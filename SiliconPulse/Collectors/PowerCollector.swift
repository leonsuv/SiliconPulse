import Foundation
import CoreFoundation
import Darwin

/// Private IOReport access is isolated here. Missing symbols or usable counters stay unavailable.
struct PowerCollector {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (CFTypeRef?, CFDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef?, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias SimpleInteger = @convention(c) (CFDictionary, CFString?, Int32) -> Int64
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
           let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() {
            var subscribed: Unmanaged<CFMutableDictionary>?
            subscription = createSubscription(nil, channels, &subscribed, 0)?.takeRetainedValue()
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
        for channel in dictionaries(in: delta) {
            guard let name = channelName(channel)?.takeUnretainedValue() as String? else { continue }
            let unit = (unitLabel(channel)?.takeUnretainedValue() as String? ?? "").lowercased()
            let raw = Double(simpleInteger(channel, nil, 0))
            if ProcessInfo.processInfo.arguments.contains("--dump-ioreport") {
                print("[IOReport] group=Energy Model channel=\(name) unit=\(unit) rawDelta=\(raw)")
            }
            let millijoules: Double
            if unit.contains("mj") { millijoules = raw }
            else if unit.contains("uj") || unit.contains("µj") { millijoules = raw / 1_000 }
            else if unit.contains("nj") { millijoules = raw / 1_000_000 }
            else if unit.contains("joule") || unit == "j" { millijoules = raw * 1_000 }
            else { continue }
            let watts = millijoules / 1_000 / elapsed
            let normalized = name.lowercased()
            if normalized.contains("dram") { dram = (dram ?? 0) + watts }
            else if normalized.contains("gpu") { gpu = (gpu ?? 0) + watts }
            else if normalized.contains("ane") || normalized.contains("neural") { ane = (ane ?? 0) + watts }
            else if name.hasPrefix("ECPU") || name.hasPrefix("PCPU") || name.hasPrefix("EACC") || name.hasPrefix("PACC") || name.hasPrefix("CPU Energy") {
                cpu = (cpu ?? 0) + watts
            }
        }
        let available = [cpu, gpu, ane, dram].compactMap { $0 }
        return PowerReading(cpu: cpu, gpu: gpu, ane: ane, dram: dram, combined: available.isEmpty ? nil : available.reduce(0, +), eFrequencyMHz: nil, pFrequencyMHz: nil, gpuFrequencyMHz: nil, eResidency: nil, pResidency: nil)
    }

    private func dictionaries(in object: CFDictionary) -> [CFDictionary] {
        var found: [CFDictionary] = []
        func visit(_ value: Any) {
            if let dictionary = value as? NSDictionary {
                found.append(dictionary as CFDictionary)
                dictionary.allValues.forEach(visit)
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(object)
        return found
    }
}
