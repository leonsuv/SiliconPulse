import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable final class FlightRecorderModel {
    var isRecording = false
    var isReplaying = false
    var isPlaying = false
    var frames: [FlightFrame] = []
    var position = 0.0
    var recordedChip: String?
    var message: String?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var writer: FileHandle?
    private(set) var recoveryURL: URL?
    var current: FlightFrame? { frames.isEmpty ? nil : frames[min(frames.count - 1, max(0, Int(position)))] }
    func start(chip: String) {
        recordedChip = chip; stopPlayback(); frames = []; position = 0; isReplaying = false
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiliconPulse/Recordings")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(UUID().uuidString).jsonl")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            writer = try FileHandle(forWritingTo: url); recoveryURL = url; isRecording = true
        } catch { message = error.localizedDescription }
    }
    func append(_ frame: FlightFrame) {
        guard isRecording else { return }
        frames.append(frame)
        // Keep UI memory bounded; full recording remains in the append-only recovery file.
        if frames.count > 3600 { frames.removeFirst(frames.count - 3600) }
        position = Double(frames.count - 1)
        do { var data = try JSONEncoder().encode(frame); data.append(0x0a); try writer?.write(contentsOf: data) }
        catch { message = error.localizedDescription; stopRecording() }
    }
    func stopRecording() { isRecording = false; try? writer?.close(); writer = nil }
    func export(chip: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "SiliconPulse-recording.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var all = frames
            if let recoveryURL, let text = try? String(contentsOf: recoveryURL) { all = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(FlightFrame.self, from: Data($0.utf8)) } }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(FlightLog(chip: recordedChip ?? chip, frames: all)).write(to: url)
        } catch { message = error.localizedDescription }
    }
    func load() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let log = try JSONDecoder().decode(FlightLog.self, from: Data(contentsOf: url))
            guard log.version == 1, !log.frames.isEmpty, log.frames.count <= 1_000_000 else { throw InspectorFailure.message("Unsupported or empty recording.") }
            stopRecording(); stopPlayback(); recoveryURL = nil; recordedChip = log.chip; frames = log.frames; position = 0; isReplaying = true
        } catch { message = error.localizedDescription }
    }
    func togglePlayback() {
        if isPlaying { stopPlayback(); return }
        guard frames.count > 1 else { return }
        if Int(position) >= frames.count - 1 { position = 0 }
        isPlaying = true
        playback = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, Int(position) < frames.count - 1 {
                let i = Int(position), delay = min(5, max(0.05, frames[i + 1].date.timeIntervalSince(frames[i].date)))
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }; position += 1
            }
            isPlaying = false
        }
    }
    func stopPlayback() { playback?.cancel(); playback = nil; isPlaying = false }
    func points(_ metric: String) -> [TelemetryPoint] {
        let last = min(frames.count, Int(position) + 1), first = max(0, last - 300)
        guard last > first else { return [] }
        return frames[first..<last].enumerated().map { TelemetryPoint(id: first + $0.offset, value: $0.element.values[metric]) }
    }
}
