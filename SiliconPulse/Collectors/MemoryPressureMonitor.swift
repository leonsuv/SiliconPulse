import Foundation
import Dispatch

@MainActor final class MemoryPressureMonitor {
    private(set) var state: String?
    private var source: DispatchSourceMemoryPressure?

    init() {
        let monitor = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source = monitor
        monitor.setEventHandler { [weak self] in
            let events = monitor.data
            Task { @MainActor in
                if events.contains(.critical) { self?.state = "Critical" }
                else if events.contains(.warning) { self?.state = "Warning" }
                else if events.contains(.normal) { self?.state = "Normal" }
            }
        }
        monitor.resume()
    }
}
