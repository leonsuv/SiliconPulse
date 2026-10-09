import SwiftUI
import AppKit
import Observation

private actor MonitorWorker {
    private var cpuPrevious: [UInt32]?, cpuTotal: [UInt32]?
    private var power = PowerCollector(), memory = MemoryCollector(), network = NetworkCollector(), diskIO = DiskIOCollector(), processes = DetailProcessCollector()
    private let sensors = HIDSensors()
    private var residency: ResidencyCollector?
    private let system = SystemCollector().collect()
    private var smart: String?
    private var lastSmart = Date.distantPast
    private var lastProcess = Date.distantPast
    private var cachedProcesses: [DetailProcess] = []
    func sample(detailed: Bool) -> (TelemetrySnapshot, [DetailProcess], ResidencyReading) {
        var snapshot = TelemetrySnapshot()
        snapshot.system = system; snapshot.system.uptime = ProcessInfo.processInfo.systemUptime
        snapshot.battery = BatteryCollector().collect()
        snapshot.cpu = CPUCollector().collect(previous: &cpuPrevious, previousTotal: &cpuTotal)
        snapshot.gpu = GPUCollector().collect(); snapshot.power = power.collect()
        snapshot.memory = memory.collect(); snapshot.network = network.collect(); snapshot.disk = DiskCollector().collect(); snapshot.diskIO = diskIO.collect()
        if Date().timeIntervalSince(lastSmart) > 60 { smart = DiskCollector.smartStatus(); lastSmart = Date() }; snapshot.disk.smartStatus = smart
        let temperatures = sensors.collect(), cpu = temperatures.filter { $0.group == "CPU/SoC" }.map(\.celsius)
        snapshot.temperatures = TemperatureReading(sensors: temperatures, cpuAverage: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count), cpuMaximum: cpu.max())
        if snapshot.battery.temperatureC == nil { snapshot.battery.temperatureC = temperatures.first { $0.group == "Battery" }?.celsius }
        if Date().timeIntervalSince(lastProcess) >= 3 { cachedProcesses = processes.collect(); lastProcess = Date() }
        if detailed && residency == nil { residency = ResidencyCollector() }
        if !detailed { residency = nil }
        return (snapshot, cachedProcesses, residency?.collect() ?? ResidencyReading())
    }
    func pause() { residency = nil }
}

@MainActor @Observable final class MonitorModel {
    var section = "Summary"
    var selection = "CPU"
    var query = ""
    var processes: [DetailProcess] = []
    var processView = "All"
    var processSort = "CPU"
    var processSelection: Int32?
    var pendingTermination: DetailProcess?
    var forceTermination = false
    var expandedUsers: Set<UInt32> = []
    var selectedRelated: Set<String> = []
    var showUninstallConfirmation = false
    var expandedProcesses: Set<Int32> = []
    var snapshot = TelemetrySnapshot()
    var history: [String: [TelemetryPoint]] = [:]
    var sensorValues: [SensorValue] = []
    var rows: [InspectorRow] = []
    var rowSelection: String?
    var sockets: [SocketReading] = []
    var socketSelection: String?
    var socketFilter = "All"
    var driverFilter = "All"
    var hardwareType = "SPHardwareDataType"
    var isLoading = false
    var message: String?
    var related: [InspectorRow] = []
    var appSizes: [String: UInt64] = [:]
    var calculatingAppSizes = false
    var appBytes: UInt64?
    @ObservationIgnored private let pressure = MemoryPressureMonitor()
    let diskScan = DiskScanModel()
    let benchmarks = BenchmarkModel()
    let flight = FlightRecorderModel()
    var windowOpen = false
    @ObservationIgnored private let worker = MonitorWorker()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var extrema: [String: (Double, Double)] = [:]

    var filteredRows: [InspectorRow] {
        rows.filter { (query.isEmpty || ($0.name + $0.value).localizedCaseInsensitiveContains(query)) && (section != "Drivers" || driverFilter == "All" || driverFilter == "Loaded" && $0.enabled == true || driverFilter == "Not loaded" && $0.enabled == false || driverFilter == "Third-party" && $0.vendor.lowercased() != "apple" && !$0.id.hasPrefix("com.apple.") || driverFilter == "Extensions" && $0.group == "System extension") }
    }
    var filteredProcesses: [DetailProcess] {
        let matches = processes.filter { query.isEmpty || "\($0.name) \($0.user) \($0.id)".localizedCaseInsensitiveContains(query) }
        return matches.sorted { processSort == "Memory" ? ($0.memory ?? 0) > ($1.memory ?? 0) : processSort == "Name" ? $0.name < $1.name : ($0.cpu ?? -1) > ($1.cpu ?? -1) }
    }
    var filteredSockets: [SocketReading] {
        sockets.filter { (query.isEmpty || "\($0.process) \($0.pid) \($0.local) \($0.remote)".localizedCaseInsensitiveContains(query)) && (socketFilter == "All" || socketFilter == "Connected" && $0.state == "ESTABLISHED" || socketFilter == "Listening" && $0.state == "LISTEN" || socketFilter == "Public" && $0.exposure == "All interfaces" || socketFilter == "UDP" && $0.transport == "UDP" || socketFilter == "Local IPC" && $0.transport == "UNIX") }
    }
    func setWindowOpen(_ open: Bool) {
        windowOpen = open
        updateSampling()
    }
    func updateSampling() {
        guard windowOpen || flight.isRecording else { timer?.cancel(); timer = nil; Task { await worker.pause() }; return }
        guard timer == nil else { return }
        timer = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let sample = await worker.sample(detailed: ["Performance", "Power & Frequency", "Apple Silicon", "Flight Recorder"].contains(section) || flight.isRecording)
                guard !Task.isCancelled else { break }
                snapshot = sample.0; snapshot.memory.pressure = pressure.state ?? AppModel.shared.snapshot.memory.pressure
                processes = sample.1
                tick += 1
                if section == "Connections", tick % 5 == 0, !isLoading { reload() }
                var values = metrics(snapshot)
                for sensor in sample.2.sensors { if let value = sensor.value { values[sensor.id] = value } }
                for sensor in commonSensors(snapshot) { if let value = sensor.value { values[sensor.id] = value } }
                for (key, value) in values {
                    var points = history[key] ?? []
                    points.append(TelemetryPoint(id: tick, value: value))
                    if points.count > 300 { points.removeFirst(points.count - 300) }
                    history[key] = points
                    let old = extrema[key] ?? (value, value); extrema[key] = (min(old.0, value), max(old.1, value))
                }
                sensorValues = (sample.2.sensors + commonSensors(snapshot)).map { sensor in
                    var item = sensor; item.minimum = extrema[item.id]?.0; item.maximum = extrema[item.id]?.1; return item
                }
                if flight.isRecording { flight.append(FlightFrame(id: tick, date: .now, values: values, cores: snapshot.cpu.cores.map(\.percent), thermal: snapshot.cpu.thermalState)) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func metrics(_ s: TelemetrySnapshot) -> [String: Double] {
        var result: [String: Double] = [:]
        func set(_ key: String, _ value: Double?) { if let value, value.isFinite { result[key] = value } }
        set("CPU", s.cpu.load.map { $0 * 100 }); set("GPU", s.gpu.utilization); set("Memory", s.memory.usedPercent)
        set("User", s.cpu.user); set("Kernel", s.cpu.system); set("E cores", s.cpu.eAverage.map { $0 * 100 }); set("P cores", s.cpu.pAverage.map { $0 * 100 })
        set("CPU power", s.power.cpu); set("GPU power", s.power.gpu); set("ANE power", s.power.ane); set("DRAM power", s.power.dram); set("Power", s.power.combined)
        set("Battery", s.battery.percent.map { $0 * 100 }); set("Battery power", s.battery.watts); set("Temperature", s.temperatures.cpuAverage)
        set("Disk read", s.diskIO.readBytesPerSecond); set("Disk write", s.diskIO.writeBytesPerSecond)
        set("Network down", s.network.downBytesPerSecond); set("Network up", s.network.upBytesPerSecond)
        for core in s.cpu.cores {
            set("Core \(core.kind)\(core.number)", core.percent * 100)
            set("Core \(core.kind)\(core.number) kernel", core.kernel.map { $0 * 100 })
        }
        for kind in ["E", "P"] {
            let values = s.cpu.cores.filter { $0.kind == kind }.compactMap(\.kernel)
            set(kind + " kernel", values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) * 100)
        }
        return result
    }
    func commonSensors(_ s: TelemetrySnapshot) -> [SensorValue] {
        let info: [(String, String, Double?, String)] = [("CPU", "Utilization", s.cpu.load.map { $0 * 100 }, "%"), ("GPU", "Utilization", s.gpu.utilization, "%"), ("Power", "Combined", s.power.combined, "W"), ("CPU power", "CPU", s.power.cpu, "W"), ("GPU power", "GPU", s.power.gpu, "W"), ("ANE power", "ANE", s.power.ane, "W"), ("DRAM power", "DRAM", s.power.dram, "W"), ("Temperature", "CPU/SoC", s.temperatures.cpuAverage, "°C"), ("Battery power", "Battery", s.battery.watts, "W")]
        return info.map { SensorValue(id: $0.0, name: $0.1, domain: $0.3 == "W" ? "Power" : $0.3 == "°C" ? "Temperature" : "Utilization", value: $0.2, unit: $0.3) } + s.temperatures.sensors.map { SensorValue(id: "sensor/\($0.id)", name: $0.name, domain: $0.group, value: $0.celsius, unit: "°C") }
    }
    func selectSection(_ value: String) { section = value; query = ""; rowSelection = nil; socketSelection = nil; message = nil; reload() }
    func reload() {
        generation += 1; let request = generation, section = section, type = hardwareType
        guard ["System Info", "Startup apps", "Services", "Connections", "Installed Apps", "Drivers"].contains(section) else { rows = []; isLoading = false; return }
        isLoading = true
        Task {
            do {
                let result = try await Task.detached(priority: .utility) { () -> ([InspectorRow], [SocketReading]) in
                    switch section {
                    case "System Info": return (try SystemInspector.profiler(type), [])
                    case "Startup apps": return (try SystemInspector.launchItems(startupOnly: true), [])
                    case "Services": return (try SystemInspector.launchItems(startupOnly: false), [])
                    case "Installed Apps": return (SystemInspector.applications(), [])
                    case "Drivers": return (try SystemInspector.drivers(), [])
                    default: return ([], try SystemInspector.sockets())
                    }
                }.value
                guard request == generation else { return }
                rows = result.0; sockets = result.1; isLoading = false
            } catch { if request == generation { isLoading = false; message = error.localizedDescription } }
        }
    }
    func calculateAppSizes() {
        guard !calculatingAppSizes else { return }
        calculatingAppSizes = true
        let applications = rows
        Task {
            for application in applications {
                let bytes = await Task.detached(priority: .utility) { SystemInspector.bundleBytes(application.path) }.value
                if let bytes { appSizes[application.id] = bytes }
            }
            calculatingAppSizes = false
        }
    }
    func inspectApp(_ app: InspectorRow) {
        related = []; appBytes = nil
        Task {
            let data = await Task.detached(priority: .utility) { (SystemInspector.relatedFiles(app), SystemInspector.bundleBytes(app.path)) }.value
            guard rowSelection == app.id else { return }; related = data.0; appBytes = data.1; if let bytes = data.1 { appSizes[app.id] = bytes }
        }
    }
    func toggleLaunch(_ row: InspectorRow, _ enabled: Bool) {
        isLoading = true
        let startup = section == "Startup apps"
        Task { do { try await Task.detached { try SystemInspector.changeLaunchItem(row, enabled: enabled, startup: startup) }.value; reload() } catch { isLoading = false; message = error.localizedDescription } }
    }
    func terminate(_ process: DetailProcess, force: Bool) {
        guard process.uid == getuid(), process.id != getpid(), process.id > 1 else { message = "This process cannot be stopped by SiliconPulse."; return }
        var identity = proc_bsdinfo()
        guard proc_pidinfo(process.id, PROC_PIDTBSDINFO, 0, &identity, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              identity.pbi_uid == process.uid,
              process.started == Date(timeIntervalSince1970: Double(identity.pbi_start_tvsec) + Double(identity.pbi_start_tvusec) / 1_000_000) else { message = "The selected process has exited or changed."; return }
        if kill(process.id, force ? SIGKILL : SIGTERM) != 0 { message = String(cString: strerror(errno)) }
    }
    func exportRows() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "SiliconPulse-\(section).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = section == "Connections" ? sockets.map { ["pid": String($0.pid), "process": $0.process, "protocol": $0.transport, "state": $0.state, "local": $0.local, "remote": $0.remote, "exposure": $0.exposure] } : rows.map { ["name": $0.name, "value": $0.value, "path": $0.path, "group": $0.group] }
        do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: url) } catch { message = error.localizedDescription }
    }
}

@MainActor final class MonitorWindowController: NSObject, NSWindowDelegate {
    static let shared = MonitorWindowController()
    let model = MonitorModel()
    private(set) var window: NSWindow?
    func show(section: String = "Summary") {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SiliconPulse Monitor"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 600); window.setFrameAutosaveName("SiliconPulseMonitor"); window.center()
            window.contentView = NSHostingView(rootView: MonitorView().environment(model).environment(AppModel.shared))
            window.delegate = self; self.window = window
        }
        model.selectSection(section); model.setWindowOpen(true)
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.setWindowOpen(false) }
    func windowDidMiniaturize(_ notification: Notification) { model.setWindowOpen(false) }
    func windowDidDeminiaturize(_ notification: Notification) { model.setWindowOpen(true) }
}
