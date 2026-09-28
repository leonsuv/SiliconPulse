import Foundation
import CoreFoundation
import Darwin

/// IOReport is a private, version-sensitive API. All symbol loading and calls live here.
/// Missing symbols/channels/counters produce nil values for the UI rather than estimates.
struct PowerCollector {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (CFTypeRef?, CFDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef?, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, UInt64) -> Unmanaged<CFDictionary>?
    private typealias SimpleInteger = @convention(c) (CFDictionary, CFString?, Int32) -> Int64
    private typealias ChannelName = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias StateCount = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias UnitLabel = @convention(c) (CFDictionary) -> Unmanaged<CFString>?

    private let handle: UnsafeMutableRawPointer?
    private let copyChannels: CopyChannels?
    private let createSubscription: CreateSubscription?
    private let createSamples: CreateSamples?
    private let createDelta: CreateDelta?
    private let simpleInteger: SimpleInteger?
    private let channelName: ChannelName?
    private let stateCount: StateCount?
    private let stateName: StateName?
    private let stateResidency: StateResidency?
    private let unitLabel: UnitLabel?
    private var energySubscription: CFTypeRef?
    private var energyChannels: CFDictionary?
    private var previousEnergy: CFDictionary?
    private var previousTime = Date()

    init() {
        let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL)
        handle = lib
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let lib, let address = dlsym(lib, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        copyChannels = symbol("IOReportCopyChannelsInGroup", as: CopyChannels.self)
        createSubscription = symbol("IOReportCreateSubscription", as: CreateSubscription.self)
        createSamples = symbol("IOReportCreateSamples", as: CreateSamples.self)
        createDelta = symbol("IOReportCreateSamplesDelta", as: CreateDelta.self)
        simpleInteger = symbol("IOReportSimpleGetIntegerValue", as: SimpleInteger.self)
        channelName = symbol("IOReportChannelGetChannelName", as: ChannelName.self)
        stateCount = symbol("IOReportStateGetCount", as: StateCount.self)
        stateName = symbol("IOReportStateGetNameForIndex", as: StateName.self)
        stateResidency = symbol("IOReportStateGetResidency", as: StateResidency.self)
        unitLabel = symbol("IOReportChannelGetUnitLabel", as: UnitLabel.self)
        if let copyChannels, let createSubscription {
            let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
            if let channels {
                var subscribed: Unmanaged<CFMutableDictionary>?
                energySubscription = createSubscription(nil, channels, &subscribed, 0)?.takeRetainedValue()
                energyChannels = subscribed?.takeRetainedValue()
            }
        }
        _ = handle // Keep the dynamic library loaded for the lifetime of this collector.
    }

    mutating func collect() -> PowerReading {
        guard copyChannels != nil, createSubscription != nil, createSamples != nil,
              createDelta != nil, simpleInteger != nil, channelName != nil,
              stateCount != nil, stateName != nil, stateResidency != nil,
              unitLabel != nil, let energySubscription, let energyChannels,
              let createSamples, let createDelta else { return .unavailable }

        let now = Date()
        let current = createSamples(energySubscription, energyChannels, 0)?.takeRetainedValue()
        var reading = PowerReading.unavailable
        if let current, let previousEnergy {
            let delta = createDelta(previousEnergy, current, 0)?.takeRetainedValue()
            let seconds = now.timeIntervalSince(previousTime)
            if let delta, seconds > 0 {
                let values = energyWatts(in: delta, elapsed: seconds)
                reading.cpu = values.cpu; reading.gpu = values.gpu; reading.ane = values.ane
                reading.combined = values.combined
            }
        }
        if let current { previousEnergy = current; previousTime = now }
        readResidency(group: "CPU Stats", into: &reading)
        readResidency(group: "GPU Stats", into: &reading)
        return reading
    }

    private func energyWatts(in sample: CFDictionary, elapsed: TimeInterval) -> (cpu: Double?, gpu: Double?, ane: Double?, combined: Double?) {
        guard let channelName, let simpleInteger, let unitLabel else { return (nil, nil, nil, nil) }
        var result: (Double?, Double?, Double?) = (nil, nil, nil)
        for channel in dictionaries(in: sample) {
            guard let name = channelName(channel)?.takeUnretainedValue() as String? else { continue }
            let key = name.lowercased()
            let unit = (unitLabel(channel)?.takeUnretainedValue() as String? ?? "").lowercased()
            let raw = Double(simpleInteger(channel, nil, 0))
            let millijoules: Double
            if unit.contains("mj") { millijoules = raw }
            else if unit.contains("uj") || unit.contains("µj") { millijoules = raw / 1_000 }
            else if unit.contains("nj") { millijoules = raw / 1_000_000 }
            else if unit.contains("joule") || unit == "j" { millijoules = raw * 1_000 }
            else { continue }
            let watts = millijoules / 1_000 / elapsed
            if key.contains("ane") || key.contains("neural") { result.2 = (result.2 ?? 0) + watts }
            else if key.contains("gpu") { result.1 = (result.1 ?? 0) + watts }
            else if key.contains("cpu") || key.contains("package") { result.0 = (result.0 ?? 0) + watts }
        }
        let total = [result.0, result.1, result.2].compactMap { $0 }.reduce(0, +)
        return (result.0, result.1, result.2, total > 0 ? total : nil)
    }

    private mutating func readResidency(group: String, into reading: inout PowerReading) {
        guard let copyChannels, let stateCount, let stateName, let stateResidency else { return }
        guard let channels = copyChannels(group as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        let entries = dictionaries(in: channels)
        for channel in entries {
            guard let name = channelName?(channel)?.takeUnretainedValue() as String? else { continue }
            let count = stateCount(channel)
            guard count > 0 else { continue }
            var total: Double = 0, weighted: Double = 0
            for i in 0..<count {
                let state = stateName(channel, i)?.takeUnretainedValue() as String? ?? ""
                let value = max(0, Double(stateResidency(channel, i)))
                total += value
                let frequency = Double(String(state.filter(\.isNumber)))
                if let frequency { weighted += frequency * value }
            }
            let residency = total > 0 ? min(1, total / max(total, 1)) : nil
            let key = name.lowercased()
            if group == "GPU Stats" && (key.contains("gpu") || key.contains("freq")) {
                reading.gpuFrequencyMHz = total > 0 && weighted > 0 ? weighted / total : nil
            } else if group == "CPU Stats" && key.contains("ecluster") {
                reading.eFrequencyMHz = total > 0 && weighted > 0 ? weighted / total : nil
                reading.eResidency = residency
            } else if group == "CPU Stats" && key.contains("pcluster") {
                reading.pFrequencyMHz = total > 0 && weighted > 0 ? weighted / total : nil
                reading.pResidency = residency
            }
        }
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
