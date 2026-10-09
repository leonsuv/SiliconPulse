import Foundation
import Dispatch
import Darwin

@MainActor final class MemoryPressureMonitor {
    private var eventState: String?
    var state: String? {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        // XNU exports dispatch levels here, not its internal pressure enum.
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            switch level { case 1: return "Normal"; case 2: return "Warning"; case 4: return "Critical"; default: break }
        }
        return eventState
    }
    private var source: DispatchSourceMemoryPressure?

    init() {
        let monitor = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source = monitor
        monitor.setEventHandler { [weak self] in
            let events = monitor.data
            Task { @MainActor in
                if events.contains(.critical) { self?.eventState = "Critical" }
                else if events.contains(.warning) { self?.eventState = "Warning" }
                else if events.contains(.normal) { self?.eventState = "Normal" }
            }
        }
        monitor.resume()
    }
}
