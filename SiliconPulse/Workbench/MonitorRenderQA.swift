import Foundation
import AppKit
import Darwin

/// Explicit local QA mode. Captures remain outside the repository.
@MainActor enum MonitorRenderQA {
    static func run(to directory: String) async {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let controller = MonitorWindowController.shared, model = controller.model
        let domain = Bundle.main.bundleIdentifier ?? "io.github.leonsuv.SiliconPulse"
        let preferences = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        var log: [String] = []
        func report(_ message: String) { print(message); fflush(stdout); log.append(message) }
        func settle() async { try? await Task.sleep(for: .milliseconds(450)) }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            controller.show()
            try? await Task.sleep(for: .seconds(5))
            report("LIVE cores=\(model.snapshot.cpu.cores.count) processes=\(model.processes.count) cpu=\(model.snapshot.cpu.load.map(String.init(describing:)) ?? "nil") sensors=\(model.sensorValues.count) ownCPU=\(model.processes.first { $0.id == getpid() }?.cpu ?? -1)")
            guard let window = controller.window else { throw InspectorFailure.message("Monitor window missing") }
            for section in ["Summary", "Performance", "Processes", "System Info", "Startup apps", "Users", "Services", "Power & Frequency", "Apple Silicon", "Flight Recorder", "Connections", "Installed Apps", "Drivers", "Disk Space", "Benchmarks"] {
                model.selectSection(section)
                let deadline = Date(timeIntervalSinceNow: 100)
                while model.isLoading && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
                report("SECTION \(section) rows=\(model.rows.count) sockets=\(model.sockets.count) error=\(model.message ?? "none")")
                // Do not dismiss errors invisibly: record them before clearing for the screenshot.
                model.message = nil
                if section == "Processes" { model.processSelection = model.processes.first { $0.id == getpid() }?.id }
                if section == "Users" { model.expandedUsers.insert(getuid()) }
                if section == "Installed Apps", let app = model.rows.first { $0.name == "SiliconPulse" } ?? model.rows.first { $0.name == "Calculator" } { model.rowSelection = app.id; model.inspectApp(app) }
                if section == "Drivers" { model.rowSelection = model.rows.first { $0.id == "com.apple.filesystems.apfs" }?.id }
                if ["Performance", "Power & Frequency", "Apple Silicon"].contains(section) { try? await Task.sleep(for: .seconds(2.5)) }
                await settle()
                try InterfaceRenderQA.capture(window, to: output.appendingPathComponent(section.replacingOccurrences(of: " ", with: "-") + ".png"))
            }
            model.selectSection("Performance")
            try? await Task.sleep(for: .seconds(3))
            report("POWER cpu=\(model.snapshot.power.cpu ?? -1) gpu=\(model.snapshot.power.gpu ?? -1) ane=\(model.snapshot.power.ane ?? -1) dram=\(model.snapshot.power.dram ?? -1) frequencySensors=\(model.sensorValues.filter { $0.unit == "MHz" }.count) pressure=\(model.snapshot.memory.pressure ?? "nil")")
            for metric in ["CPU", "Memory", "GPU", "Neural Engine", "Disk", "Network", "Energy", "Thermals"] {
                model.selection = metric; await settle()
                try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("performance-\(metric).png"))
            }
            model.selectSection("System Info")
            for type in SystemInspector.profilerTypes {
                model.hardwareType = type; model.reload()
                let deadline = Date(timeIntervalSinceNow: 95)
                while model.isLoading && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
                report("HARDWARE \(type) rows=\(model.rows.count) error=\(model.message ?? "none")"); model.message = nil
            }
            model.selectSection("Disk Space")
            let fixture = output.appendingPathComponent("scan-fixture")
            try FileManager.default.createDirectory(at: fixture.appendingPathComponent("Folder"), withIntermediateDirectories: true)
            try Data(repeating: 42, count: 16384).write(to: fixture.appendingPathComponent("Folder/example.swift"))
            try Data(repeating: 21, count: 8192).write(to: fixture.appendingPathComponent("example.pdf"))
            let historyBefore = model.diskScan.history
            model.diskScan.start(fixture)
            let deadline = Date(timeIntervalSinceNow: 20)
            while model.diskScan.isScanning && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
            report("SCAN files=\(model.diskScan.files) children=\(model.diskScan.nodes.count) largest=\(model.diskScan.largest.count) types=\(model.diskScan.fileTypes.count) error=\(model.diskScan.message)")
            await settle(); try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("scan-treemap.png"))
            model.diskScan.layout = "Balls"; await settle(); try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("scan-balls.png"))
            if let folder = model.diskScan.nodes.first(where: { $0.directory }) { model.diskScan.drill(folder); report("SCAN_DRILL children=\(model.diskScan.nodes.count) pathOK=\(model.diskScan.path(model.diskScan.nodes.first?.id ?? 0)?.lastPathComponent == "example.swift")"); model.diskScan.up() }
            model.diskScan.query = "example.swift"; model.diskScan.search(); report("SCAN_SEARCH matches=\(model.diskScan.nodes.count)")
            if let saved = model.diskScan.history.first { model.diskScan.restore(saved); report("SCAN_RESTORE children=\(model.diskScan.nodes.count)") }
            // QA artifacts are kept in /tmp; remove only the index created by this run.
            for entry in model.diskScan.history where !historyBefore.contains(where: { $0.id == entry.id }) { try? FileManager.default.removeItem(atPath: entry.indexPath) }
            model.diskScan.history = historyBefore
            let scanHistory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiliconPulse/DiskScans/history.json")
            try JSONEncoder().encode(historyBefore).write(to: scanHistory, options: .atomic)
            model.selectSection("Flight Recorder")
            model.flight.start(chip: model.snapshot.system.chip ?? "n/a"); model.updateSampling()
            try? await Task.sleep(for: .seconds(4)); model.flight.stopRecording()
            let flight = FlightLog(chip: model.snapshot.system.chip ?? "n/a", frames: model.flight.frames)
            let recording = try JSONEncoder().encode(flight)
            try recording.write(to: output.appendingPathComponent("recording.json"))
            let restored = try JSONDecoder().decode(FlightLog.self, from: recording)
            model.flight.isReplaying = true; model.flight.position = 0; model.flight.togglePlayback()
            try? await Task.sleep(for: .seconds(2)); model.flight.stopPlayback()
            report("FLIGHT frames=\(restored.frames.count) replayPosition=\(model.flight.position) values=\(restored.frames.first?.values.count ?? 0)")
            await settle(); try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("flight-replay.png"))
            if let recovery = model.flight.recoveryURL { try? FileManager.default.removeItem(at: recovery) }
            model.selectSection("Benchmarks")
            let benchmarkBefore = model.benchmarks.results
            for kind in ["CPU", "GPU", "Disk"] {
                model.benchmarks.kind = kind; model.benchmarks.start()
                let deadline = Date(timeIntervalSinceNow: 35)
                while model.benchmarks.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
                if model.benchmarks.isRunning { model.benchmarks.cancel() }
                let result = model.benchmarks.results.first
                report("BENCH \(kind) primary=\(result?.primary ?? -1) secondary=\(result?.secondary ?? -1) unit=\(result?.unit ?? "n/a") error=\(model.benchmarks.message ?? "none")")
                await settle(); try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("benchmark-\(kind).png"))
            }
            model.benchmarks.results = benchmarkBefore
            let benchmarkHistory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiliconPulse/benchmarks.json")
            try JSONEncoder().encode(benchmarkBefore).write(to: benchmarkHistory, options: .atomic)
            for language in ["en", "de"] {
                AppModel.shared.language = language
                for dark in [false, true] {
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    model.selectSection("Summary"); window.setContentSize(NSSize(width: 1000, height: 700)); await settle()
                    try InterfaceRenderQA.capture(window, to: output.appendingPathComponent("summary-\(language)-\(dark ? "dark" : "light").png"))
                }
            }
            // Exercise actions only on temporary objects created by this QA run.
            let label = "io.github.leonsuv.SiliconPulse.QA." + UUID().uuidString
            let agentURL = output.appendingPathComponent("qa-agent.plist")
            let agent = ["Label": label, "ProgramArguments": ["/bin/sleep", "60"], "RunAtLoad": true] as [String: Any]
            try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0).write(to: agentURL)
            let item = InspectorRow(id: agentURL.path, name: label, value: "/bin/sleep 60", path: agentURL.path, group: "gui/\(getuid())")
            do {
                try await Task.detached { try SystemInspector.changeLaunchItem(item, enabled: true, startup: false, allowAdministrator: false) }.value
                let launched = try await Task.detached { try InspectorCommands.checked("/bin/launchctl", ["print", item.group + "/" + label]).text }.value
                report("SERVICE bootstrap=\(launched.contains(label))")
                try await Task.detached { try SystemInspector.changeLaunchItem(item, enabled: false, startup: true, allowAdministrator: false); try SystemInspector.changeLaunchItem(item, enabled: true, startup: true, allowAdministrator: false); try SystemInspector.changeLaunchItem(item, enabled: false, startup: false, allowAdministrator: false) }.value
                report("STARTUP enable-disable=true SERVICE bootout=true")
            } catch { report("ACTION_ERROR \(error.localizedDescription)"); _ = try? await Task.detached { try InspectorCommands.run("/bin/launchctl", ["bootout", item.group + "/" + label]) }.value }
            try? FileManager.default.removeItem(at: agentURL)
            let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["60"]; try child.run()
            let childPID = child.processIdentifier
            let childRow = await Task.detached { var collector = DetailProcessCollector(); return collector.collect().first { $0.id == childPID } }.value
            if let childRow { model.terminate(childRow, force: false); try? await Task.sleep(for: .milliseconds(200)); report("PROCESS stopOwnFixture=\(!child.isRunning)") }
            if child.isRunning { child.terminate() }
            let trashFixture = output.appendingPathComponent("SiliconPulse-QA-" + UUID().uuidString + ".app")
            try FileManager.default.createDirectory(at: trashFixture, withIntermediateDirectories: true)
            var trashed: NSURL?
            try FileManager.default.trashItem(at: trashFixture, resultingItemURL: &trashed)
            report("APP trashOwnFixture=\(!FileManager.default.fileExists(atPath: trashFixture.path))")
            if let trashed { try? FileManager.default.removeItem(at: trashed as URL) }
            SettingsWindowController.shared.show(model: AppModel.shared)
            await settle(); report("SETTINGS visible=\(SettingsWindowController.shared.currentWindow?.isVisible == true) monitorVisible=\(window.isVisible)")
            SettingsWindowController.shared.currentWindow?.close()
            func cpuTime() -> Double { var value = rusage(); getrusage(RUSAGE_SELF, &value); return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000 }
            model.selectSection("Summary"); window.makeKeyAndOrderFront(nil)
            let openCPU = cpuTime(), openTime = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .seconds(10))
            report("CPU_OPEN percent=\((cpuTime() - openCPU) / (ProcessInfo.processInfo.systemUptime - openTime) * 100)")
            window.close(); report("CLOSE samplingWindow=\(model.windowOpen) recording=\(model.flight.isRecording)")
            let closedCPU = cpuTime(), closedTime = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .seconds(10))
            report("CPU_CLOSED percent=\((cpuTime() - closedCPU) / (ProcessInfo.processInfo.systemUptime - closedTime) * 100)")
        } catch { report("QA_ERROR \(error.localizedDescription)") }
        UserDefaults.standard.setPersistentDomain(preferences, forName: domain); UserDefaults.standard.synchronize()
        try? log.joined(separator: "\n").write(to: output.appendingPathComponent("QA.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
