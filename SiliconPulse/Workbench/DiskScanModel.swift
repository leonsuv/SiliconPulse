import Foundation
import Observation
import AppKit
import FastTreeCore

struct ScannedNode: Identifiable, Hashable {
    var id: UInt32
    var parent: UInt32
    var name: String
    var bytes: UInt64
    var logical: UInt64
    var directory: Bool
    var files: UInt32
    var modified: Date?
    var category: String {
        if directory { return "Folders" }
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "mov", "mp4", "mp3", "wav", "m4a": return "Media"
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "numbers": return "Documents"
        case "swift", "c", "h", "cpp", "js", "ts", "tsx", "py", "rs", "java", "html", "css": return "Code"
        case "zip", "gz", "tar", "7z", "dmg", "pkg": return "Archives"
        case "app": return "Applications"
        default: return "Other"
        }
    }
}
private final class ScanIndex: @unchecked Sendable {
    let pointer: OpaquePointer
    init?(url: URL) { guard let value = ft_index_open(url.path) else { return nil }; pointer = value }
    deinit { ft_index_close(pointer) }
    func node(_ id: UInt32) -> ScannedNode? {
        guard let record = ft_index_node(pointer, id)?.pointee else { return nil }
        var length: UInt16 = 0
        guard let name = ft_index_name(pointer, id, &length) else { return nil }
        let data = Data(bytes: name, count: Int(length))
        return ScannedNode(id: id, parent: record.parent, name: String(decoding: data, as: UTF8.self), bytes: record.allocated_bytes, logical: record.logical_bytes, directory: record.kind == 1, files: record.files, modified: record.modified_seconds > 0 ? Date(timeIntervalSince1970: Double(record.modified_seconds)) : nil)
    }
    func children(_ id: UInt32) -> [ScannedNode] { (0..<ft_index_child_count(pointer, id)).compactMap { node(ft_index_child_at(pointer, id, $0)) }.sorted { $0.bytes > $1.bytes } }
    func largest() -> [ScannedNode] { var ids = [UInt32](repeating: 0, count: 100); let count = ft_index_largest_files(pointer, &ids, 100); return ids.prefix(Int(count)).compactMap(node) }
    func search(_ query: String) -> [ScannedNode] { var ids = [UInt32](repeating: 0, count: 500); let count = ft_index_search(pointer, query, &ids, 500); return ids.prefix(Int(count)).compactMap(node) }
    func types() -> [String: UInt64] {
        var totals: [String: UInt64] = [:]
        for id in 0..<ft_index_count(pointer) {
            guard let file = node(id), !file.directory else { continue }
            var category = file.category, ancestor = file.parent, visited = Set<UInt32>()
            while ancestor > 0, visited.insert(ancestor).inserted, let parent = node(ancestor) {
                if parent.name.lowercased().hasSuffix(".app") { category = "Applications"; break }
                ancestor = parent.parent
            }
            totals[category, default: 0] += file.bytes
        }
        return totals
    }
}
struct DiskScanHistory: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var root: String
    var indexPath: String
    var bytes: UInt64
}
@MainActor @Observable final class DiskScanModel {
    var volumeTotal: UInt64?
    var volumeFree: UInt64?
    var scannedBytes: UInt64?
    var root: URL?
    var nodes: [ScannedNode] = []
    var largest: [ScannedNode] = []
    var fileTypes: [String: UInt64] = [:]
    var focus: UInt32 = 0
    var selected: UInt32?
    var query = ""
    var layout = "Treemap"
    var group = "File size"
    var isScanning = false
    var files: UInt64 = 0
    var skipped: UInt64 = 0
    var message = ""
    var history: [DiskScanHistory] = []
    @ObservationIgnored private var index: ScanIndex?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var generation = 0
    private var folder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiliconPulse/DiskScans") }
    init() { if let data = try? Data(contentsOf: folder.appendingPathComponent("history.json")), let saved = try? JSONDecoder().decode([DiskScanHistory].self, from: data) { history = saved } }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }; start(url)
    }
    func start(_ url: URL) {
        cancel(); generation += 1; let request = generation
        root = url; updateVolume(); scannedBytes = nil; index = nil; selected = nil; focus = 0; files = 0; skipped = 0; nodes = []; largest = []; fileTypes = [:]; query = ""; message = ""
        guard let executable = Bundle.main.resourceURL?.appendingPathComponent("siliconpulse-scan"), FileManager.default.isExecutableFile(atPath: executable.path) else { message = "Build the app bundle to enable the disk scanner."; return }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { message = error.localizedDescription; return }
        let indexURL = folder.appendingPathComponent(UUID().uuidString + ".ftidx")
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = executable; process.arguments = [url.path, "--threads", "4", "--index", indexURL.path, "--progress"]
        process.standardOutput = output; process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                guard let self, request == self.generation else { return }
                for line in text.split(separator: "\n") {
                    if line.hasPrefix("FTPROGRESS "), let data = String(line.dropFirst(11)).data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.files = (object["files"] as? NSNumber)?.uint64Value ?? self.files
                        self.skipped = (object["skipped"] as? NSNumber)?.uint64Value ?? self.skipped
                    } else if line.hasPrefix("FTERROR") { self.message = "Some paths could not be read; the scan is partial." }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, request == self.generation else { return }
                self.isScanning = false; self.process = nil
                let loaded = await Task.detached(priority: .utility) { ScanIndex(url: indexURL) }.value
                guard request == self.generation else { return }
                guard let loaded else { self.message = "The scanner could not create an index."; return }
                self.index = loaded; self.focus = 0; self.nodes = loaded.children(0); self.largest = loaded.largest()
                let types = await Task.detached(priority: .utility) { loaded.types() }.value
                guard request == self.generation else { return }
                self.fileTypes = types
                self.scannedBytes = loaded.node(0)?.bytes
                self.files = UInt64(loaded.node(0)?.files ?? 0)
                self.history.insert(DiskScanHistory(root: url.path, indexPath: indexURL.path, bytes: loaded.node(0)?.bytes ?? 0), at: 0)
                if self.history.count > 20 { self.history.removeLast(self.history.count - 20) }
                if let data = try? JSONEncoder().encode(self.history) { try? data.write(to: self.folder.appendingPathComponent("history.json"), options: .atomic) }
                if finished.terminationStatus != 0 { self.message = "Some paths could not be read; the scan is partial." }
            }
        }
        do { try process.run(); self.process = process; isScanning = true; DispatchQueue.global().async { _ = output.fileHandleForReading.readDataToEndOfFile() } }
        catch { errors.fileHandleForReading.readabilityHandler = nil; message = error.localizedDescription }
    }
    func cancel() { generation += 1; process?.terminate(); process = nil; isScanning = false }
    func drill(_ node: ScannedNode) { selected = node.id; guard node.directory else { return }; focus = node.id; query = ""; nodes = index?.children(focus) ?? [] }
    func up() { guard focus != 0, let node = index?.node(focus) else { return }; focus = node.parent; query = ""; nodes = index?.children(focus) ?? [] }
    func search() { nodes = query.isEmpty ? index?.children(focus) ?? [] : index?.search(query) ?? [] }
    func selectedNode() -> ScannedNode? { selected.flatMap { index?.node($0) } }
    func path(_ id: UInt32) -> URL? {
        guard let root, let index else { return nil }
        var pieces: [String] = []
        var current = id
        while current > 0, let node = index.node(current) { pieces.append(node.name); current = node.parent }
        return pieces.reversed().reduce(root) { $0.appendingPathComponent($1) }
    }
    private func updateVolume() {
        let values = try? root?.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        volumeTotal = values?.volumeTotalCapacity.map { UInt64(max(0, $0)) }
        volumeFree = values?.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
    }
    func restore(_ entry: DiskScanHistory) {
        guard let loaded = ScanIndex(url: URL(fileURLWithPath: entry.indexPath)) else { message = "The saved scan is unavailable."; return }
        cancel(); selected = nil; files = UInt64(loaded.node(0)?.files ?? 0); skipped = 0; message = ""
        root = URL(fileURLWithPath: entry.root); updateVolume(); scannedBytes = loaded.node(0)?.bytes; index = loaded; focus = 0; nodes = loaded.children(0); largest = loaded.largest(); fileTypes = loaded.types()
    }
}
