import Foundation
import Darwin

/// Pipe capture and field-based lsof parsing adapted from leonsuv/PortPeek (MIT).
final class InspectorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func store(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func read() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
struct InspectorCommand {
    var status: Int32
    var data: Data
    var error: String
    var text: String { String(decoding: data, as: UTF8.self) }
}
enum InspectorFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum InspectorCommands {
    static func run(_ executable: String, _ arguments: [String], timeout: Double = 30, shouldCancel: (() -> Bool)? = nil) throws -> InspectorCommand {
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out; process.standardError = err
        let output = InspectorCapture(), errors = InspectorCapture(), group = DispatchGroup()
        try process.run()
        group.enter(); DispatchQueue.global().async { output.store(out.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter(); DispatchQueue.global().async { errors.store(err.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline && shouldCancel?() != true { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval: 0.05); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit(); group.wait(); if shouldCancel?() == true { throw CancellationError() }; throw InspectorFailure.message("Inspection timed out.") }
        process.waitUntilExit(); group.wait()
        return InspectorCommand(status: process.terminationStatus, data: output.read(), error: String(decoding: errors.read(), as: UTF8.self))
    }
    static func checked(_ executable: String, _ arguments: [String], timeout: Double = 30, shouldCancel: (() -> Bool)? = nil) throws -> InspectorCommand {
        let result = try run(executable, arguments, timeout: timeout, shouldCancel: shouldCancel)
        guard result.status == 0 else { throw InspectorFailure.message(String(result.error.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result
    }
    static func administrator(_ executable: String, _ arguments: [String]) throws {
        func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = ([executable] + arguments).map(quote).joined(separator: " ")
        let script = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"
        _ = try checked("/usr/bin/osascript", ["-e", script], timeout: 300)
    }
}

struct DetailProcessCollector {
    private var previous: [Int32: (UInt64, UInt64?, UInt64?, UInt64)] = [:]
    private var wall: Double?
    mutating func collect() -> [DetailProcess] {
        let count = max(4096, Int(proc_listallpids(nil, 0)) + 128)
        var pids = [pid_t](repeating: 0, count: count)
        let found = proc_listallpids(&pids, Int32(count * MemoryLayout<pid_t>.size))
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = wall.map { now - $0 }
        var next: [Int32: (UInt64, UInt64?, UInt64?, UInt64)] = [:]
        var rows: [DetailProcess] = []
        var userNames: [UInt32: String] = [:]
        var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
        let nanosecondsPerTick = Double(timebase.numer) / Double(max(1, timebase.denom))
        // Darwin task accounting reports mach absolute ticks, unlike rusage CPU nanoseconds.
        for pid in pids.prefix(max(0, min(Int(found), count))) where pid > 0 {
            var b = proc_bsdinfo(), task = proc_taskinfo(), usage = rusage_info_v4()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { continue }
            let readable = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size
            let usageOK = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0 }
            }
            let total = task.pti_total_user &+ task.pti_total_system
            let started = UInt64(b.pbi_start_tvsec) * 1_000_000 + UInt64(b.pbi_start_tvusec)
            let read: UInt64? = usageOK ? usage.ri_diskio_bytesread : nil
            let write: UInt64? = usageOK ? usage.ri_diskio_byteswritten : nil
            if readable { next[pid] = (total, read, write, started) }
            let old = previous[pid]
            let valid = elapsed.map { $0 > 0 && $0 < 10 } == true && old?.3 == started
            let cpu: Double? = valid && readable && total >= (old?.0 ?? 0) ? Double(total - old!.0) * nanosecondsPerTick / (elapsed! * 1_000_000_000) * 100 : nil
            func rate(_ new: UInt64?, _ old: UInt64?) -> Double? { guard valid, let new, let old, new >= old else { return nil }; return Double(new - old) / elapsed! }
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let path = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 ? String(cString: pathBuffer) : ""
            var nameBuffer = [CChar](repeating: 0, count: 256)
            let name = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 ? String(cString: nameBuffer) : "PID \(pid)"
            let user: String
            if let cached = userNames[b.pbi_uid] { user = cached }
            else {
                var record = passwd(), result: UnsafeMutablePointer<passwd>?
                var buffer = [CChar](repeating: 0, count: 16_384)
                user = getpwuid_r(b.pbi_uid, &record, &buffer, buffer.count, &result) == 0 && result != nil ? String(cString: record.pw_name) : String(b.pbi_uid)
                userNames[b.pbi_uid] = user
            }
            var architecture = proc_archinfo()
            let archOK = proc_pidinfo(pid, PROC_PIDARCHINFO, 0, &architecture, Int32(MemoryLayout<proc_archinfo>.size)) == MemoryLayout<proc_archinfo>.size
            let arch: String? = archOK ? architecture.p_cputype == CPU_TYPE_ARM64 ? "arm64" : architecture.p_cputype == CPU_TYPE_X86_64 ? "x86_64 (Rosetta)" : String(architecture.p_cputype) : nil
            let status = b.pbi_status == UInt32(SSTOP) ? "Stopped" : b.pbi_status == UInt32(SZOMB) ? "Zombie" : "Running"
            rows.append(DetailProcess(id: pid, parent: Int32(b.pbi_ppid), uid: b.pbi_uid, name: name, path: path, status: status,
                cpu: cpu, memory: usageOK ? usage.ri_phys_footprint : readable ? task.pti_resident_size : nil,
                threads: readable ? Int(task.pti_threadnum) : nil, faults: readable ? UInt64(task.pti_faults) : nil,
                cpuSeconds: readable ? Double(total) * nanosecondsPerTick / 1_000_000_000 : nil,
                started: Date(timeIntervalSince1970: Double(b.pbi_start_tvsec) + Double(b.pbi_start_tvusec) / 1_000_000), readRate: rate(read, old?.1), writeRate: rate(write, old?.2), architecture: arch, priority: Int(b.pbi_nice), peak: usageOK ? usage.ri_lifetime_max_phys_footprint : nil, resident: readable ? task.pti_resident_size : nil, virtual: readable ? task.pti_virtual_size : nil, user: user))
        }
        previous = next; wall = now
        return rows.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
    }
}

enum SystemInspector {
    static let profilerTypes = ["SPHardwareDataType", "SPMemoryDataType", "SPAudioDataType", "SPBluetoothDataType", "SPCameraDataType", "SPDisplaysDataType", "SPiBridgeDataType", "SPNVMeDataType", "SPSPIDataType", "SPSecureElementDataType", "SPSmartCardsDataType", "SPThunderboltDataType", "SPUSBDataType", "SPPowerDataType"]
    static func profiler(_ type: String) throws -> [InspectorRow] {
        let result = try InspectorCommands.checked("/usr/sbin/system_profiler", [type, "-json", "-detailLevel", "full"], timeout: 60)
        let object = try JSONSerialization.jsonObject(with: result.data)
        var rows: [InspectorRow] = []
        func visit(_ value: Any, _ path: String) {
            if let dictionary = value as? [String: Any] {
                let name = dictionary["_name"] as? String ?? ""
                let group = name.isEmpty ? path : (path.isEmpty ? name : path + " / " + name)
                for key in dictionary.keys.sorted() where key != "_name" {
                    let value = dictionary[key]!
                    if value is [String: Any] || value is [Any] { visit(value, group) }
                    else { rows.append(InspectorRow(id: "\(rows.count)", name: key.replacingOccurrences(of: "_", with: " "), value: String(describing: value), group: group)) }
                }
            } else if let array = value as? [Any] { for item in array { visit(item, path) } }
        }
        visit(object, "")
        return rows
    }
    static func launchItems(startupOnly: Bool) throws -> [InspectorRow] {
        let fm = FileManager.default
        let dirs = startupOnly ? [fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, "/Library/LaunchAgents"] : [fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, "/Library/LaunchAgents", "/Library/LaunchDaemons", "/System/Library/LaunchAgents", "/System/Library/LaunchDaemons"]
        var running: [String: Int32] = [:], loaded = Set<String>()
        let state = try InspectorCommands.checked("/bin/launchctl", ["list"])
        for line in state.text.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 3 { let label = String(fields[2]); loaded.insert(label); if let pid = Int32(fields[0]) { running[label] = pid } }
        }
        var systemLoaded = Set<String>(), systemRunning: [String: Int32] = [:]
        if let system = try? InspectorCommands.checked("/bin/launchctl", ["print", "system"]).text {
            var inServices = false
            for line in system.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "services = {" { inServices = true; continue }
                if inServices && trimmed == "}" { break }
                if inServices { let fields = line.split(whereSeparator: \.isWhitespace); if fields.count >= 3 { let label = String(fields.last!); systemLoaded.insert(label); if let pid = Int32(fields[0]), pid > 0 { systemRunning[label] = pid } } }
            }
        }
        let disabled = try? InspectorCommands.checked("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).text
        var rows: [InspectorRow] = []
        for dir in dirs {
            for url in (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url), let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = dictionary["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = dictionary["Program"] as? String ?? (dictionary["ProgramArguments"] as? [String])?.joined(separator: " ") ?? "n/a"
                let isDisabled = disabled?.contains("\"\(label)\" => true") == true || dictionary["Disabled"] as? Bool == true
                let userDomain = dir == dirs.first || dir == "/Library/LaunchAgents" || dir == "/System/Library/LaunchAgents"
                rows.append(InspectorRow(id: url.path, name: label, value: program, path: url.path, group: userDomain ? "gui/\(getuid())" : "system", enabled: startupOnly ? !isDisabled : (userDomain ? loaded : systemLoaded).contains(label), pid: userDomain ? running[label] : systemRunning[label]))
            }
        }
        return rows.sorted { $0.name < $1.name }
    }
    static func changeLaunchItem(_ row: InspectorRow, enabled: Bool, startup: Bool, allowAdministrator: Bool = true) throws {
        guard !row.path.hasPrefix("/System/") else { throw InspectorFailure.message("macOS protects this system service.") }
        let target = row.group + "/" + row.name
        let arguments = startup ? [enabled ? "enable" : "disable", target] : enabled ? ["bootstrap", row.group, row.path] : ["bootout", target]
        let result = try InspectorCommands.run("/bin/launchctl", arguments)
        if result.status != 0 { guard allowAdministrator else { throw InspectorFailure.message(result.error) }; try InspectorCommands.administrator("/bin/launchctl", arguments) }
        if startup {
            // Apply the enabled preference to the current session as well.
            _ = try? InspectorCommands.run("/bin/launchctl", enabled ? ["bootstrap", row.group, row.path] : ["bootout", target])
        }
    }
    static func sockets() throws -> [SocketReading] {
        let result = try InspectorCommands.run("/usr/sbin/lsof", ["-nP", "-i", "-U", "-FpcuftPnT"], timeout: 15)
        guard result.status == 0 || result.status == 1 else { throw InspectorFailure.message(result.error) }
        var rows: [SocketReading] = [], pid: Int32 = 0, process = "", user = "", fd = "", transport = "", state = "", address = ""
        func flush() {
            guard pid > 0, !fd.isEmpty, !address.isEmpty else { return }
            let endpoints = address.components(separatedBy: "->")
            let kind = transport.isEmpty ? "UNIX" : transport
            rows.append(SocketReading(id: "\(pid)|\(fd)|\(address)", pid: pid, process: process, user: user, descriptor: fd, transport: kind, state: state.isEmpty ? kind == "UDP" ? "BOUND" : kind == "UNIX" ? "LOCAL" : "n/a" : state, local: endpoints[0], remote: endpoints.count > 1 ? endpoints[1] : ""))
        }
        for line in result.text.split(separator: "\n") {
            guard let prefix = line.first else { continue }; let value = String(line.dropFirst())
            switch prefix {
            case "p": flush(); fd = ""; address = ""; pid = Int32(value) ?? 0; user = ""; process = ""
            case "c": process = value
            case "u": user = value
            case "f": flush(); fd = value; address = ""; transport = ""; state = ""
            case "P": transport = value
            case "n": address = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        flush()
        return Array(Set(rows)).sorted { $0.process < $1.process }
    }
    static func applications() -> [InspectorRow] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var rows: [InspectorRow] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url) else { continue }
                let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                rows.append(InspectorRow(id: url.path, name: name, value: bundle.bundleIdentifier ?? "n/a", path: url.path, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "n/a", vendor: bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "n/a", modified: attributes?.contentModificationDate, lastOpened: attributes?.contentAccessDate))
            }
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func relatedFiles(_ app: InspectorRow) -> [InspectorRow] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        guard app.value != "n/a", !app.value.isEmpty else { return [] }
        let dirs = ["Application Support", "Caches", "Preferences", "Saved Application State", "Containers", "HTTPStorages", "WebKit", "Logs"]
        return dirs.flatMap { dir -> [InspectorRow] in
            let folder = home.appendingPathComponent(dir)
            return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter {
                $0.lastPathComponent == app.value || $0.lastPathComponent.hasPrefix(app.value + ".")
            }.map { InspectorRow(id: $0.path, name: $0.lastPathComponent, value: dir, path: $0.path) }
        }
    }
    static func bundleBytes(_ path: String) -> UInt64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var bytes: UInt64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .isRegularFileKey]), values.isRegularFile == true { bytes += UInt64(max(0, values.fileAllocatedSize ?? 0)) }
        }
        return bytes
    }
    static func drivers() throws -> [InspectorRow] {
        let result = try InspectorCommands.checked("/usr/sbin/system_profiler", ["SPExtensionsDataType", "-json"], timeout: 90)
        let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] ?? [:]
        var loadedDetails: [String: String] = [:], wiredBytes: [String: UInt64] = [:]
        if let loaded = try? InspectorCommands.checked("/usr/bin/kmutil", ["showloaded"]).text {
            for line in loaded.split(separator: "\n") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 8, Int(fields[0]) != nil else { continue }
                let identifier = String(fields[5]); loadedDetails[identifier] = String(line).trimmingCharacters(in: .whitespaces)
                if let bytes = UInt64(fields[4].replacingOccurrences(of: "0x", with: ""), radix: 16), bytes > 0 { wiredBytes[identifier] = bytes }
            }
        }
        var rows: [InspectorRow] = []
        func visit(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let name = dict["_name"] as? String, dict["version"] != nil || dict["path"] != nil {
                    let identifier = dict["spext_bundleid"] as? String ?? dict["bundle_id"] as? String ?? dict["id"] as? String ?? name
                    let loaded = ((dict["spext_loaded"] ?? dict["loaded"]) as? String).map { ["spext_yes", "yes", "loaded", "true"].contains($0.lowercased()) }
                    rows.append(InspectorRow(id: identifier, name: name, value: dict.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n") + (loadedDetails[identifier].map { "\nLoaded index / refs / address / size / wired / dependencies: \($0)" } ?? ""), path: (dict["spext_path"] ?? dict["path"]) as? String ?? "", group: "Kernel extension", version: (dict["spext_version"] ?? dict["version"]) as? String ?? "n/a", vendor: (dict["spext_signed_by"] as? String)?.contains("Apple Inc.") == true ? "Apple" : dict["obtained_from"] as? String ?? dict["spext_signed_by"] as? String ?? "n/a", wired: wiredBytes[identifier], enabled: loaded))
                }
                for value in dict.values where value is [Any] || value is [String: Any] { visit(value) }
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(object)
        if let extensions = try? InspectorCommands.checked("/usr/bin/systemextensionsctl", ["list"]) {
            for line in extensions.text.split(separator: "\n") {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 6, fields[0] != "enabled", !line.hasPrefix("---") else { continue }
                let bundle = fields[3].components(separatedBy: " (")
                guard bundle.count == 2 else { continue }
                rows.append(InspectorRow(id: bundle[0], name: fields[4], value: String(line), group: "System extension", version: bundle[1].replacingOccurrences(of: ")", with: ""), vendor: fields[2], enabled: fields[1] == "*"))
            }
        }
        return rows.sorted { $0.name < $1.name }
    }
}
