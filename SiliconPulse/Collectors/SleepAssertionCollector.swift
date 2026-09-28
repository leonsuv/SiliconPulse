import Foundation
import IOKit
import IOKit.pwr_mgt
import Darwin

struct SleepAssertionCollector {
    func collect() -> [SleepBlocker] {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess, let dictionary = assertions?.takeRetainedValue() as NSDictionary? else { return [] }
        let blockers: [SleepBlocker] = dictionary.compactMap { item -> SleepBlocker? in
            guard let pidNumber = item.key as? NSNumber, let values = item.value as? [String: Any] else { return nil }
            let pid = pidNumber.int32Value
            let name = processName(pid)
            var assertionTypes: [String] = []
            if let assertions = values["Assertions"] as? [[String: Any]] {
                for assertion in assertions {
                    if let type = assertion["AssertionType"] as? String, !assertionTypes.contains(type) { assertionTypes.append(type) }
                }
            }
            if assertionTypes.isEmpty, let types = values["AssertionTypes"] as? [String] { assertionTypes = types }
            guard !assertionTypes.isEmpty else { return nil }
            return SleepBlocker(id: pid, name: name.isEmpty ? "Process \(pid)" : name, assertions: assertionTypes)
        }
        return blockers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let count = Darwin.proc_name(pid, &buffer, UInt32(buffer.count))
        return count > 0 ? String(cString: buffer) : ""
    }
}
