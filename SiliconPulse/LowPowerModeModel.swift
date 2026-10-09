import Foundation
import Observation

/// Owns the system state; nothing is persisted as an app preference.
@MainActor @Observable final class LowPowerModeModel {
    private(set) var isEnabled: Bool?
    private(set) var isChanging = false
    var errorMessageKey: String?

    @ObservationIgnored private let service = LowPowerModeService()
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var revision = 0

    init() {
        Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        guard !isChanging, !isRefreshing else { return }
        isRefreshing = true
        let currentRevision = revision
        let status = await service.readStatus()
        if currentRevision == revision, !isChanging { isEnabled = status }
        isRefreshing = false
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging, let current = isEnabled, current != enabled else { return }
        revision += 1
        isChanging = true
        errorMessageKey = nil
        isEnabled = enabled

        Task {
            let result = await service.setEnabled(enabled)
            // Reconcile with pmset, including when authorization was cancelled.
            isEnabled = await service.readStatus()
            isChanging = false
            switch result {
            case .success:
                if isEnabled != enabled { errorMessageKey = "Low Power Mode change could not be confirmed." }
            case .failure(.cancelled):
                errorMessageKey = "Authorization was cancelled. Low Power Mode was not changed."
            case .failure(.commandFailed):
                errorMessageKey = "Low Power Mode could not be changed. Please try again."
            }
        }
    }
}

private enum LowPowerModeFailure: Error {
    case cancelled
    case commandFailed
}

/// Serializes reads and writes off the main actor, so a password dialog never
/// blocks SwiftUI and a polling read cannot overlap a system change.
private actor LowPowerModeService {
    func readStatus() -> Bool? {
        guard let result = run("/bin/sh", arguments: ["-c", "/usr/bin/pmset -g | /usr/bin/grep lowpowermode"]), result.status == 0 else { return nil }
        let values = result.output.split(whereSeparator: \.isNewline).compactMap { line -> Bool? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0] == "lowpowermode" else { return nil }
            switch fields[1] { case "0": return false; case "1": return true; default: return nil }
        }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    func setEnabled(_ enabled: Bool) -> Result<Void, LowPowerModeFailure> {
        // Use existing permissions first; only request authorization if needed.
        let value = enabled ? "1" : "0"
        if let result = run("/usr/bin/pmset", arguments: ["-a", "lowpowermode", value]), result.status == 0 {
            return .success(())
        }
        // The only interpolated input is a Bool converted to the literal 0 or 1.
        let script = "do shell script \"/usr/bin/pmset -a lowpowermode \(enabled ? 1 : 0)\" with administrator privileges"
        guard let result = run("/usr/bin/osascript", arguments: ["-e", script]) else { return .failure(.commandFailed) }
        if result.status == 0 { return .success(()) }
        return .failure(result.output.contains("(-128)") ? .cancelled : .commandFailed)
    }

    private func run(_ executable: String, arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return nil
        }
    }
}
