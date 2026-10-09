import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct MonitorView: View {
    @Environment(MonitorModel.self) private var monitor
    @Environment(AppModel.self) private var app
    @AppStorage("monitorAccent") private var accent = "Blue"
    private static let sections: [(String, String)] = [("Summary", "gauge.with.dots.needle.50percent"), ("Performance", "waveform.path.ecg"), ("Processes", "list.bullet.rectangle"), ("System Info", "info.circle"), ("Startup apps", "power"), ("Users", "person.2"), ("Services", "gearshape.2"), ("Power & Frequency", "bolt"), ("Apple Silicon", "cpu"), ("Flight Recorder", "record.circle"), ("Connections", "network"), ("Installed Apps", "square.grid.2x2"), ("Drivers", "puzzlepiece.extension"), ("Disk Space", "chart.pie"), ("Benchmarks", "speedometer")]
    private var tint: Color { switch accent { case "Teal": .teal; case "Green": .green; case "Orange": .orange; case "Purple": .purple; default: .blue } }

    var body: some View {
        @Bindable var settings = monitor
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Label("SiliconPulse", systemImage: "waveform.path.ecg").font(.headline).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                List(selection: Binding<String?>(get: { monitor.section }, set: { if let value = $0 { monitor.selectSection(value) } })) {
                    Section("Monitor") { navigationRows(["Summary", "Performance", "Processes", "Power & Frequency", "Apple Silicon"]) }
                    Section("Tools") { navigationRows(["Flight Recorder", "Connections", "Disk Space", "Benchmarks"]) }
                    Section("System") { navigationRows(["System Info", "Startup apps", "Users", "Services", "Installed Apps", "Drivers"]) }
                }.listStyle(.sidebar)
                Divider()
                HStack {
                    Button { SettingsWindowController.shared.show(model: app) } label: { Image(systemName: "gearshape"); Text("Settings") }.buttonStyle(.plain)
                    Spacer()
                    Menu {
                        Picker("Appearance", selection: Binding(get: { app.appearance }, set: { app.appearance = $0 })) { ForEach(["System", "Light", "Dark"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }
                        Picker("Accent color", selection: $accent) { ForEach(["Blue", "Teal", "Green", "Orange", "Purple"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }
                    } label: { Image(systemName: "paintpalette") }.menuStyle(.borderlessButton).fixedSize()
                }.font(.caption).padding(16)
            }.frame(width: 215).background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(LocalizedStringKey(monitor.section)).font(.title2.weight(.semibold))
                    Spacer()
                    if monitor.isLoading { ProgressView().controlSize(.small) }
                    if ["Processes", "Users", "Startup apps", "Services", "Connections", "Installed Apps", "Drivers", "System Info"].contains(monitor.section) {
                        TextField(LocalizedStringKey(searchHint), text: $settings.query).textFieldStyle(.roundedBorder).frame(width: 220)
                    }
                    if monitor.section == "Installed Apps" { Button("Calculate sizes") { monitor.calculateAppSizes() }.disabled(monitor.calculatingAppSizes) }
                    if ["System Info", "Startup apps", "Services", "Connections", "Installed Apps", "Drivers"].contains(monitor.section) {
                        Button { monitor.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.help("Refresh")
                        Button { monitor.exportRows() } label: { Label("Export…", systemImage: "square.and.arrow.up") }.help("Export…").disabled(monitor.rows.isEmpty && monitor.sockets.isEmpty)
                    }
                }.padding(18)
                Divider()
                sectionContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 12) {
                    Circle().fill(monitor.flight.isRecording ? .red : .green).frame(width: 7, height: 7)
                    Text(monitor.flight.isRecording ? "Recording" : "Live").font(.caption)
                    Text(monitor.snapshot.system.chip ?? "Apple Silicon").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monitor.processes.count)").monospacedDigit() + Text(" ") + Text("Processes")
                }.font(.caption).padding(.horizontal, 18).padding(.vertical, 10)
            }
        }
        .tint(tint).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, app.locale)
        .alert("SiliconPulse", isPresented: Binding(get: { monitor.message != nil }, set: { if !$0 { monitor.message = nil } })) { Button("OK", role: .cancel) { monitor.message = nil } } message: { Text(monitor.message ?? "") }
    }
    private var searchHint: String {
        switch monitor.section {
        case "Processes", "Users": "Search by name, user or PID"
        case "Connections": "Search connections"
        case "Installed Apps": "Search applications"
        case "Drivers": "Search drivers"
        case "System Info": "Search hardware"
        default: "Search services"
        }
    }
    @ViewBuilder private func navigationRows(_ names: [String]) -> some View {
        ForEach(names, id: \.self) { name in
            HStack(spacing: 9) {
                Image(systemName: Self.sections.first(where: { $0.0 == name })?.1 ?? "circle").foregroundStyle(tint).frame(width: 20)
                Text(LocalizedStringKey(name)).lineLimit(1)
            }.tag(name).padding(.vertical, 3)
        }
    }
    @ViewBuilder private var sectionContent: some View {
        switch monitor.section {
        case "Summary": summary
        case "Performance": PerformanceInspectorView()
        case "Processes": ProcessesInspectorView()
        case "Users": UsersInspectorView()
        case "System Info": HardwareInspectorView()
        case "Startup apps", "Services": LaunchInspectorView()
        case "Power & Frequency": SensorsInspectorView()
        case "Apple Silicon": SiliconInspectorView()
        case "Flight Recorder": FlightInspectorView()
        case "Connections": ConnectionsInspectorView()
        case "Installed Apps": ApplicationsInspectorView()
        case "Drivers": DriversInspectorView()
        case "Disk Space": DiskInspectorView().environment(monitor.diskScan)
        case "Benchmarks": BenchmarksInspectorView().environment(monitor.benchmarks)
        default: EmptyView()
        }
    }
    private var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    summaryTile("CPU", metric: "CPU", value: DisplayValue.decimal(monitor.snapshot.cpu.load.map { $0 * 100 }, digits: 0, suffix: "%"), icon: "cpu", color: .blue)
                    summaryTile("GPU", metric: "GPU", value: DisplayValue.decimal(monitor.snapshot.gpu.utilization, digits: 0, suffix: "%"), icon: "display", color: .teal)
                    summaryTile("Memory", metric: "Memory", value: DisplayValue.decimal(monitor.snapshot.memory.usedPercent, digits: 0, suffix: "%"), icon: "memorychip", color: .purple)
                    summaryTile("Battery", metric: "Battery", value: DisplayValue.decimal(monitor.snapshot.battery.percent.map { $0 * 100 }, digits: 0, suffix: "%"), icon: "battery.100percent", color: .green)
                }
                HStack(alignment: .top, spacing: 16) {
                    MonitorGroup("CPU overview") {
                        MetricHistory(keys: ["CPU", "Kernel"], colors: [.blue, .orange], percent: true).frame(height: 230)
                        InspectorValues(entries: [("Utilization", DisplayValue.decimal(monitor.snapshot.cpu.load.map { $0 * 100 }, suffix: "%")), ("Temperature", monitorTemperature(monitor.snapshot.temperatures.cpuAverage)), ("Combined", monitorPowerValue(monitor.snapshot.power.combined))])
                    }.frame(maxWidth: .infinity)
                    MonitorGroup("Top CPU processes") {
                        ForEach(monitor.processes.prefix(12)) { process in HStack { Text(process.name).lineLimit(1); Spacer(); Text(DisplayValue.decimal(process.cpu, suffix: "%")).monospacedDigit().foregroundStyle(.secondary) }.font(.caption).padding(.vertical, 2) }
                    }.frame(width: 235)
                }
                MonitorGroup("Memory") {
                    MetricHistory(keys: ["Memory"], colors: [.purple], percent: true).frame(height: 90)
                    HStack { Text(DisplayValue.bytes(monitor.snapshot.memory.used)); Spacer(); Text("Cached files") + Text(": \(DisplayValue.bytes(monitor.snapshot.memory.cached))"); Spacer(); Text("Swap used") + Text(": \(DisplayValue.bytes(monitor.snapshot.memory.swapUsed))") }.font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                    MonitorGroup("Network") { InspectorValues(entries: [("Down", app.formatRate(monitor.snapshot.network.downBytesPerSecond)), ("Up", app.formatRate(monitor.snapshot.network.upBytesPerSecond))]) }
                    MonitorGroup("Disk") { InspectorValues(entries: [("Read", app.formatRate(monitor.snapshot.diskIO.readBytesPerSecond)), ("Write", app.formatRate(monitor.snapshot.diskIO.writeBytesPerSecond))]) }
                    MonitorGroup("System Pressure") { InspectorValues(entries: [("Thermal state", thermalName(monitor.snapshot.cpu.thermalState)), ("Pressure", monitor.snapshot.memory.pressure ?? "n/a"), ("Load average", monitor.snapshot.cpu.loadAverage.map { DisplayValue.decimal($0) }.joined(separator: " / "))]) }
                }
            }.padding(18)
        }
    }
    private func summaryTile(_ title: String, metric: String, value: String, icon: String, color: Color) -> some View {
        Button { monitor.selection = title == "Battery" ? "Energy" : title; monitor.selectSection("Performance") } label: {
            MonitorGroup(title, icon: icon) {
                Text(value).font(.title.weight(.semibold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                MetricHistory(keys: [metric], colors: [color], percent: true, axes: false).frame(height: 40)
            }
        }.buttonStyle(.plain)
    }
}

struct MonitorGroup<Content: View>: View {
    let title: String, icon: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, icon: String = "", @ViewBuilder content: @escaping () -> Content) { self.title = title; self.icon = icon; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty { Label(LocalizedStringKey(title), systemImage: icon).labelStyle(.titleOnly).font(.headline) }
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct InspectorValues: View {
    let entries: [(String, String)]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) { Text(LocalizedStringKey(row.0)).foregroundStyle(.secondary); Spacer(minLength: 8); Text(LocalizedStringKey(row.1)).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.callout)
            }
        }
    }
}
struct MetricHistory: View {
    @Environment(MonitorModel.self) private var monitor
    var keys: [String], colors: [Color], percent = false, axes = true
    var body: some View {
        TelemetryChart(lines: keys.enumerated().map { index, key in
            TelemetryChartLine(name: key, points: monitor.history[key] ?? [], color: colors[min(index, colors.count - 1)])
        }, percent: percent, axes: axes, legend: axes, window: 61)
    }
}
private func thermalName(_ state: Int) -> String { let states = ["Nominal", "Fair", "Serious", "Critical"]; return states.indices.contains(state) ? states[state] : "n/a" }

private struct PerformanceInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    @Environment(AppModel.self) private var app
    private let options = ["CPU", "Memory", "GPU", "Neural Engine", "Disk", "Network", "Energy", "Thermals"]
    var body: some View {
        @Bindable var settings = monitor
        HStack(spacing: 0) {
            List(options, id: \.self, selection: $settings.selection) { key in
                VStack(alignment: .leading, spacing: 6) { Text(LocalizedStringKey(key)).font(.headline); MetricHistory(keys: [metric(key)], colors: [.accentColor], axes: false).frame(height: 24) }.padding(.vertical, 5).tag(key)
            }.frame(width: 160)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 16) { Text(LocalizedStringKey(monitor.selection)).font(.title.weight(.semibold)); details }.padding(20) }.id(monitor.selection)
        }
    }
    private func metric(_ selection: String) -> String { switch selection { case "Energy": "Power"; case "Thermals": "Temperature"; case "Disk": "Disk read"; case "Network": "Network down"; case "Neural Engine": "ANE power"; default: selection } }
    @ViewBuilder private var details: some View {
        let s = monitor.snapshot
        switch monitor.selection {
        case "CPU":
            HStack { MonitorGroup("Performance cores") { MetricHistory(keys: ["P cores", "P kernel"], colors: [.orange, .red], percent: true).frame(height: 200) }; MonitorGroup("Efficiency cores") { MetricHistory(keys: ["E cores", "E kernel"], colors: [.teal, .red], percent: true).frame(height: 200) } }
            InspectorValues(entries: [("Utilization", DisplayValue.decimal(s.cpu.load.map { $0 * 100 }, suffix: "%")), ("User", DisplayValue.decimal(s.cpu.user, suffix: "%")), ("System", DisplayValue.decimal(s.cpu.system, suffix: "%")), ("Idle", DisplayValue.decimal(s.cpu.idle, suffix: "%")), ("Processes", String(monitor.processes.count)), ("Threads", String(monitor.processes.compactMap(\.threads).reduce(0, +))), ("Uptime", DisplayValue.duration(s.system.uptime)), ("E cores", DisplayValue.number(s.system.eCores)), ("P cores", DisplayValue.number(s.system.pCores)), ("L1 cache", sysctlBytes("hw.l1dcachesize")), ("L2 cache", sysctlBytes("hw.l2cachesize")), ("L3 cache", sysctlBytes("hw.l3cachesize")), ("Frequency", frequency("CPU"))])
            coreCharts
        case "Memory":
            MetricHistory(keys: ["Memory"], colors: [.purple], percent: true).frame(height: 240)
            InspectorValues(entries: [("Used", DisplayValue.bytes(s.memory.used)), ("Free", DisplayValue.bytes(s.memory.free)), ("App memory", DisplayValue.bytes(s.memory.app)), ("Cached files", DisplayValue.bytes(s.memory.cached)), ("Wired", DisplayValue.bytes(s.memory.wired)), ("Compressed", DisplayValue.bytes(s.memory.compressed)), ("Swap used", DisplayValue.bytes(s.memory.swapUsed)), ("Pressure", s.memory.pressure ?? "n/a")])
        case "GPU":
            MetricHistory(keys: ["GPU"], colors: [.teal], percent: true).frame(height: 240)
            InspectorValues(entries: [("Device utilization", DisplayValue.decimal(s.gpu.utilization, suffix: "%")), ("Renderer", DisplayValue.decimal(s.gpu.rendererUtilization, suffix: "%")), ("Tiler", DisplayValue.decimal(s.gpu.tilerUtilization, suffix: "%")), ("GPU cores", DisplayValue.number(s.gpu.coreCount)), ("GPU memory in use", DisplayValue.bytes(s.gpu.memoryInUse)), ("GPU power", monitorPowerValue(s.power.gpu)), ("Frequency", frequency("GPU"))])
        case "Neural Engine":
            MetricHistory(keys: ["ANE power"], colors: [.yellow]).frame(height: 230)
            InspectorValues(entries: [("Power", monitorPowerValue(s.power.ane)), ("Active residency", monitor.sensorValues.first { $0.domain.contains("ANE") || $0.domain.contains("Neural") }.map { DisplayValue.decimal($0.value, suffix: "%") } ?? "n/a")])
            Text("Availability depends on the sensors exposed by macOS.").font(.caption).foregroundStyle(.secondary)
        case "Disk":
            MetricHistory(keys: ["Disk read", "Disk write"], colors: [.blue, .orange]).frame(height: 230)
            InspectorValues(entries: [("Read", app.formatRate(s.diskIO.readBytesPerSecond)), ("Write", app.formatRate(s.diskIO.writeBytesPerSecond)), ("Read IOPS", DisplayValue.decimal(s.diskIO.readIOPS, digits: 0)), ("Write IOPS", DisplayValue.decimal(s.diskIO.writeIOPS, digits: 0)), ("Volume", s.disk.volumeName ?? "n/a"), ("Total", DisplayValue.bytes(s.disk.total)), ("Available", DisplayValue.bytes(s.disk.free)), ("SMART status", s.disk.smartStatus ?? "n/a")])
        case "Network":
            MetricHistory(keys: ["Network down", "Network up"], colors: [.blue, .orange]).frame(height: 230)
            InspectorValues(entries: [("Down", app.formatRate(s.network.downBytesPerSecond)), ("Up", app.formatRate(s.network.upBytesPerSecond)), ("Interface", s.network.interfaceName ?? "n/a"), ("Total received", DisplayValue.bytes(s.network.totalDown)), ("Total sent", DisplayValue.bytes(s.network.totalUp)), ("Wi-Fi RSSI", s.network.rssi.map { "\($0) dBm" } ?? "n/a"), ("Channel", s.network.channel ?? "n/a"), ("Link rate", DisplayValue.decimal(s.network.linkMbps, suffix: " Mbps")), ("Noise", s.network.noise.map { "\($0) dBm" } ?? "n/a")])
        case "Energy":
            LowPowerModeControl().toggleStyle(.switch)
            MetricHistory(keys: ["Power", "Battery power"], colors: [.orange, .green]).frame(height: 230)
            InspectorValues(entries: [("Battery", DisplayValue.decimal(s.battery.percent.map { $0 * 100 }, suffix: "%")), ("Battery power", monitorPowerValue(s.battery.watts)), ("Combined", monitorPowerValue(s.power.combined)), ("CPU", monitorPowerValue(s.power.cpu)), ("GPU", monitorPowerValue(s.power.gpu)), ("ANE", monitorPowerValue(s.power.ane)), ("DRAM", monitorPowerValue(s.power.dram)), ("Health", DisplayValue.decimal(s.battery.health.map { $0 * 100 }, suffix: "%"))])
        default:
            MetricHistory(keys: ["Temperature"], colors: [.orange]).frame(height: 220)
            Label(LocalizedStringKey(thermalName(s.cpu.thermalState)), systemImage: "thermometer.medium")
            InspectorValues(entries: s.temperatures.sensors.map { ($0.name, monitorTemperature($0.celsius)) })
        }
    }
    private var coreCharts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))]) {
            ForEach(monitor.snapshot.cpu.cores) { core in
                MonitorGroup("\(core.kind)\(core.number)") { Text(DisplayValue.decimal(core.percent * 100, digits: 0, suffix: "%")).monospacedDigit(); MetricHistory(keys: ["Core \(core.kind)\(core.number)", "Core \(core.kind)\(core.number) kernel"], colors: [core.kind == "E" ? .teal : .orange, .red], percent: true, axes: false).frame(height: 45) }
            }
        }
    }
    private func frequency(_ domain: String) -> String {
        let sensors = monitor.sensorValues.filter { $0.domain.contains(domain) && $0.unit == "MHz" }
        if domain == "GPU" { return DisplayValue.decimal(sensors.first { $0.name == "GPUPH frequency" }?.value ?? sensors.first?.value, digits: 0, suffix: " MHz") }
        return ["ECPU", "PCPU"].compactMap { kind in
            let values = sensors.filter { $0.name.hasPrefix(kind) }.compactMap(\.value)
            return values.isEmpty ? nil : String(kind.prefix(1)) + " " + DisplayValue.decimal(values.reduce(0, +) / Double(values.count), digits: 0, suffix: " MHz")
        }.joined(separator: " · ").nonemptyOrNA
    }
    private func sysctlBytes(_ name: String) -> String { var value: UInt64 = 0, size = MemoryLayout<UInt64>.size; return sysctlbyname(name, &value, &size, nil, 0) == 0 && value > 0 ? DisplayValue.bytes(value) : "n/a" }
}

private struct ProcessDisplay: Identifiable { var process: DetailProcess; var depth = 0; var hasChildren = false; var id: Int32 { process.id } }
private struct ProcessesInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    private var displayed: [ProcessDisplay] {
        let processes = monitor.filteredProcesses
        if monitor.processView != "Tree" { return processes.filter { monitor.processView != "Applications" || $0.application }.map { ProcessDisplay(process: $0) } }
        let ids = Set(processes.map(\.id)), grouped = Dictionary(grouping: processes, by: \.parent)
        var result: [ProcessDisplay] = [], seen = Set<Int32>()
        func visit(_ process: DetailProcess, _ depth: Int) {
            guard seen.insert(process.id).inserted, depth < 30 else { return }
            let children = grouped[process.id] ?? []
            result.append(ProcessDisplay(process: process, depth: depth, hasChildren: !children.isEmpty))
            if monitor.expandedProcesses.contains(process.id) { for child in children { visit(child, depth + 1) } }
        }
        for process in processes where !ids.contains(process.parent) { visit(process, 0) }
        return result
    }
    var body: some View {
        @Bindable var settings = monitor
        VStack(spacing: 0) {
            HStack {
                Picker("View", selection: $settings.processView) { Text("All processes").tag("All"); Text("Applications").tag("Applications"); Text("Process tree").tag("Tree") }.frame(width: 240)
                Spacer()
                Picker("Sort", selection: $settings.processSort) { Text("CPU").tag("CPU"); Text("Memory").tag("Memory"); Text("Name").tag("Name") }.frame(width: 180)
            }.padding(14)
            Table(displayed, selection: $settings.processSelection) {
                TableColumn("Name") { row in
                    HStack(spacing: 5) {
                        if row.hasChildren { Button { if monitor.expandedProcesses.contains(row.id) { monitor.expandedProcesses.remove(row.id) } else { monitor.expandedProcesses.insert(row.id) } } label: { Image(systemName: monitor.expandedProcesses.contains(row.id) ? "chevron.down" : "chevron.right") }.buttonStyle(.plain) }
                        Text(row.process.name).lineLimit(1)
                    }.padding(.leading, CGFloat(row.depth) * 12)
                }.width(min: 150, ideal: 220)
                TableColumn("PID") { Text(String($0.id)).monospacedDigit() }.width(55)
                TableColumn("Status") { Text(LocalizedStringKey($0.process.status)) }.width(75)
                TableColumn("User") { Text($0.process.user) }.width(70)
                TableColumn("CPU") { Text(DisplayValue.decimal($0.process.cpu, suffix: "%")).monospacedDigit() }.width(80)
                TableColumn("Memory") { Text(DisplayValue.bytes($0.process.memory)).monospacedDigit() }.width(95)
            }
            if let process = monitor.processes.first(where: { $0.id == monitor.processSelection }) {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(process.name).font(.headline); Text("PID \(process.id)").foregroundStyle(.secondary); Spacer(); Button("Stop process…") { monitor.pendingTermination = process; monitor.forceTermination = false }; Button("Force quit…") { monitor.pendingTermination = process; monitor.forceTermination = true } }.disabled(process.uid != getuid() || process.id == getpid() || process.id <= 1)
                    Text(process.path.nonemptyOrNA).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                    HStack(alignment: .top, spacing: 24) {
                        InspectorValues(entries: [("Parent", String(process.parent)), ("User", process.user), ("Status", process.status), ("Architecture", process.architecture ?? "n/a"), ("Uptime", process.started.map { DisplayValue.duration(Date().timeIntervalSince($0)) } ?? "n/a")])
                        InspectorValues(entries: [("CPU time", DisplayValue.decimal(process.cpuSeconds, suffix: " s")), ("Threads", process.threads.map(String.init) ?? "n/a"), ("Started", process.started?.formatted() ?? "n/a"), ("Priority", process.priority.map(String.init) ?? "n/a"), ("CPU", DisplayValue.decimal(process.cpu, suffix: "%")), ("GPU", "n/a"), ("NPU", "n/a")])
                        InspectorValues(entries: [("Footprint", DisplayValue.bytes(process.memory)), ("Peak", DisplayValue.bytes(process.peak)), ("Resident", DisplayValue.bytes(process.resident)), ("Virtual", DisplayValue.bytes(process.virtual)), ("Private", "n/a"), ("Network", "n/a"), ("Page faults", process.faults.map(String.init) ?? "n/a"), ("Read", DisplayValue.decimal(process.readRate, suffix: " B/s")), ("Write", DisplayValue.decimal(process.writeRate, suffix: " B/s"))])
                    }.font(.caption)
                }.padding(16)
            }
        }.confirmationDialog("Stop selected process?", isPresented: Binding(get: { monitor.pendingTermination != nil }, set: { if !$0 { monitor.pendingTermination = nil } }), titleVisibility: .visible) {
            Button(monitor.forceTermination ? "Force quit" : "Stop", role: .destructive) { if let process = monitor.pendingTermination { monitor.terminate(process, force: monitor.forceTermination) }; monitor.pendingTermination = nil }
        } message: { Text("Unsaved work in this process may be lost.") }
    }
}

private struct UsersInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        let grouped = Dictionary(grouping: monitor.filteredProcesses, by: \.uid)
        List {
            ForEach(grouped.keys.sorted(), id: \.self) { uid in
                let processes = grouped[uid] ?? []
                DisclosureGroup(isExpanded: Binding(get: { monitor.expandedUsers.contains(uid) }, set: { if $0 { monitor.expandedUsers.insert(uid) } else { monitor.expandedUsers.remove(uid) } })) {
                    ForEach(processes) { p in HStack { Text(p.name).frame(maxWidth: .infinity, alignment: .leading); Text("PID \(p.id)").foregroundStyle(.secondary); Text(DisplayValue.decimal(p.cpu, suffix: "%")).monospacedDigit().frame(width: 70); Text(DisplayValue.bytes(p.memory)).monospacedDigit().frame(width: 90) }.font(.callout).padding(.vertical, 3) }
                } label: {
                    HStack { Label(processes.first?.user ?? String(uid), systemImage: "person.circle"); Text(uid == getuid() ? "Current user" : "Background account").font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(processes.count)"); Text(DisplayValue.decimal(processes.compactMap(\.cpu).reduce(0, +), suffix: "%")).monospacedDigit().frame(width: 80); Text(DisplayValue.bytes(processes.compactMap(\.memory).reduce(0, +))).monospacedDigit().frame(width: 100) }.padding(.vertical, 8)
                }
            }
        }
    }
}

private struct HardwareInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    private let labels = ["Hardware Overview", "Memory", "Audio", "Bluetooth", "Camera", "Graphics / Displays", "Controller", "NVMe", "SPI", "Secure Element", "Smart Cards", "Thunderbolt / USB4", "USB", "Power"]
    var body: some View {
        @Bindable var settings = monitor
        HStack(spacing: 0) {
            List(selection: $settings.hardwareType) { ForEach(Array(zip(SystemInspector.profilerTypes, labels)), id: \.0) { type, name in Text(LocalizedStringKey(name)).tag(type) } }.frame(width: 190)
                .onChange(of: monitor.hardwareType) { _, _ in monitor.reload() }
            Divider()
            Table(monitor.filteredRows) {
                TableColumn("Property", value: \.name).width(min: 150, ideal: 230)
                TableColumn("Value") { Text($0.value).textSelection(.enabled) }
                TableColumn("Device", value: \.group).width(min: 100, ideal: 180)
            }
        }
    }
}
private struct LaunchInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        @Bindable var settings = monitor
        VStack(spacing: 0) {
            Table(monitor.filteredRows, selection: $settings.rowSelection) {
                TableColumn("Enabled") { row in Toggle("Enabled", isOn: Binding(get: { row.enabled ?? false }, set: { monitor.toggleLaunch(row, $0) })).labelsHidden().disabled(monitor.isLoading || row.path.hasPrefix("/System/")) }.width(65)
                TableColumn("Name", value: \.name).width(min: 150, ideal: 280)
                TableColumn("PID") { Text($0.pid.map(String.init) ?? "—") }.width(55)
                TableColumn("Command", value: \.value)
                TableColumn("Domain", value: \.group).width(100)
            }
            if let row = monitor.rows.first(where: { $0.id == monitor.rowSelection }) {
                Divider(); VStack(alignment: .leading, spacing: 8) { Text(row.name).font(.headline); Text(row.path).font(.caption).textSelection(.enabled); Text(row.value).font(.caption).textSelection(.enabled); Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)]) } }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
private struct SensorsInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live sensors · minimum and maximum since opening the monitor").font(.caption).foregroundStyle(.secondary).padding(16)
            Table(monitor.sensorValues) {
                TableColumn("Sensor", value: \.name)
                TableColumn("Group", value: \.domain)
                TableColumn("Value") { Text(DisplayValue.decimal($0.value, suffix: " " + $0.unit)).monospacedDigit() }
                TableColumn("Minimum") { Text(DisplayValue.decimal($0.minimum, suffix: " " + $0.unit)).monospacedDigit() }
                TableColumn("Maximum") { Text(DisplayValue.decimal($0.maximum, suffix: " " + $0.unit)).monospacedDigit() }
            }
        }
    }
}
private struct SiliconInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(monitor.snapshot.system.chip ?? "Apple Silicon").font(.largeTitle.weight(.semibold))
                InspectorValues(entries: [("E cores", DisplayValue.number(monitor.snapshot.system.eCores)), ("P cores", DisplayValue.number(monitor.snapshot.system.pCores)), ("GPU cores", DisplayValue.number(monitor.snapshot.gpu.coreCount)), ("RAM", monitor.snapshot.system.memoryGB.map { "\($0.formatted()) GB" } ?? "n/a")])
                HStack { MonitorGroup("Performance cores") { MetricHistory(keys: ["P cores"], colors: [.orange], percent: true).frame(height: 150) }; MonitorGroup("Efficiency cores") { MetricHistory(keys: ["E cores", "E kernel"], colors: [.teal, .red], percent: true).frame(height: 150) } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) { ForEach(monitor.snapshot.cpu.cores) { core in MonitorGroup("\(core.kind)\(core.number)") { MetricHistory(keys: ["Core \(core.kind)\(core.number)", "Core \(core.kind)\(core.number) kernel"], colors: [core.kind == "E" ? .teal : .orange, .red], percent: true, axes: false).frame(height: 55); Text(DisplayValue.decimal(core.percent * 100, suffix: "%")).monospacedDigit() } } }
                MonitorGroup("Media Engine") {
                    let sensors = monitor.sensorValues.filter { $0.domain.contains("Media") }
                    if sensors.isEmpty { Text("n/a").foregroundStyle(.secondary) }
                    ForEach(sensors) { sensor in InspectorValues(entries: [(sensor.name, DisplayValue.decimal(sensor.value, suffix: " " + sensor.unit))]); MetricHistory(keys: [sensor.id], colors: [.orange], percent: true).frame(height: 70) }
                }
                MonitorGroup("Neural Engine") { MetricHistory(keys: ["ANE power"], colors: [.yellow]).frame(height: 90); Text(monitorPowerValue(monitor.snapshot.power.ane)).monospacedDigit() }
            }.padding(20)
        }
    }
}
private struct FlightInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        @Bindable var flight = monitor.flight
        ScrollView {
            VStack(spacing: 16) {
                Text(flight.isReplaying ? flight.recordedChip ?? "n/a" : monitor.snapshot.system.chip ?? "Apple Silicon").font(.title2.weight(.semibold))
                HStack {
                    Label(flight.isRecording ? "Recording" : flight.isReplaying ? "Replay" : "Live", systemImage: flight.isRecording ? "record.circle.fill" : "waveform.path.ecg").foregroundStyle(flight.isRecording ? .red : .green)
                    Spacer()
                    Button(flight.isRecording ? "Stop recording" : "Record") { if flight.isRecording { flight.stopRecording() } else { flight.start(chip: monitor.snapshot.system.chip ?? "Apple Silicon") }; monitor.updateSampling() }.disabled(flight.isReplaying)
                    Button("Save recording…") { flight.export(chip: monitor.snapshot.system.chip ?? "Apple Silicon") }.disabled(flight.frames.isEmpty)
                    Button("Replay…") { flight.load(); monitor.updateSampling() }.disabled(flight.isRecording)
                    if flight.isReplaying { Button("Live") { flight.stopPlayback(); flight.isReplaying = false } }
                }
                if flight.isReplaying {
                    HStack { Button(flight.isPlaying ? "Pause" : "Play") { flight.togglePlayback() }; Slider(value: $flight.position, in: 0...Double(max(1, flight.frames.count - 1))); Text(flight.current?.date.formatted() ?? "n/a").monospacedDigit() }
                }
                if flight.isReplaying, let frame = flight.current {
                    HStack(spacing: 4) { ForEach(Array(frame.cores.enumerated()), id: \.offset) { index, value in RoundedRectangle(cornerRadius: 3).fill(index < (monitor.snapshot.system.eCores ?? 0) ? Color.teal.opacity(max(0.1, min(1, value))) : Color.orange.opacity(max(0.1, min(1, value)))).frame(width: 18, height: 18).help("CPU \(index): \(DisplayValue.decimal(value * 100, suffix: "%"))") } }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(["P cores", "GPU", "ANE power", "Temperature", "Memory", "Power", "Network down", "Disk read"], id: \.self) { key in
                        MonitorGroup(key) {
                            if flight.isReplaying {
                                Text(replayValue(key, flight.current?.values[key])).font(.title2).monospacedDigit()
                                TelemetryChart(lines: [TelemetryChartLine(name: key, points: flight.points(key), color: .accentColor)], axes: true, window: 61, animated: false).frame(height: 125)
                            } else { MetricHistory(keys: [key], colors: [.accentColor]).frame(height: 150) }
                        }
                    }
                }
                if let message = flight.message { Text(message).foregroundStyle(.secondary) }
                Text("Recordings contain telemetry only and are stored locally.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
}

private struct ConnectionsInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        @Bindable var settings = monitor
        VStack(spacing: 0) {
            HStack {
                ForEach([("Connections", monitor.sockets.count), ("Listening", monitor.sockets.filter { $0.state == "LISTEN" }.count), ("Public", monitor.sockets.filter { $0.exposure == "All interfaces" }.count), ("Processes", Set(monitor.sockets.map(\.pid)).count)], id: \.0) { title, count in MonitorGroup(title) { Text(String(count)).font(.title2).monospacedDigit() } }
            }.padding(14)
            Picker("Filter", selection: $settings.socketFilter) { ForEach(["All", "Connected", "Listening", "Public", "UDP", "Local IPC"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 14).padding(.bottom, 12)
            Table(monitor.filteredSockets, selection: $settings.socketSelection) {
                TableColumn("Application") { socket in VStack(alignment: .leading) { Text(socket.process); Text("PID \(socket.pid)").font(.caption2).foregroundStyle(.secondary) } }
                TableColumn("Protocol", value: \.transport).width(65)
                TableColumn("State", value: \.state).width(95)
                TableColumn("Local endpoint", value: \.local)
                TableColumn("Remote / service", value: \.remote)
                TableColumn("Exposure") { Text(LocalizedStringKey($0.exposure)) }.width(100)
            }
            if let socket = monitor.sockets.first(where: { $0.id == monitor.socketSelection }) {
                Divider(); InspectorValues(entries: [("Process", "\(socket.process) (\(socket.pid))"), ("Local endpoint", socket.local), ("Remote / service", socket.remote.nonemptyOrNA), ("Descriptor", socket.descriptor), ("Exposure", socket.exposure)]).padding(16)
            }
            Text("Only sockets visible to your user account are listed.").font(.caption).foregroundStyle(.secondary).padding(10)
        }
    }
}

private struct ApplicationsInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        @Bindable var settings = monitor
        HSplitView {
            List(monitor.filteredRows, selection: $settings.rowSelection) { row in
                HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: row.path)).resizable().frame(width: 24, height: 24); VStack(alignment: .leading) { Text(row.name); Text(row.version).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(DisplayValue.bytes(monitor.appSizes[row.id])).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 4).tag(row.id)
            }.frame(minWidth: 220, idealWidth: 280)
                .onChange(of: monitor.rowSelection) { _, selected in monitor.selectedRelated = []; if let row = monitor.rows.first(where: { $0.id == selected }) { monitor.inspectApp(row) } }
            ScrollView {
                if let app = monitor.rows.first(where: { $0.id == monitor.rowSelection }) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 64, height: 64); VStack(alignment: .leading) { Text(app.name).font(.title); Text(app.version).foregroundStyle(.secondary) } }
                        InspectorValues(entries: [("Bundle identifier", app.value), ("Size", DisplayValue.bytes(monitor.appBytes)), ("Copyright", app.vendor), ("Modified", app.modified?.formatted() ?? "n/a"), ("Last access", app.lastOpened?.formatted() ?? "n/a"), ("Location", app.path)])
                        HStack { Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: app.path)) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }; Button("Uninstall…", role: .destructive) { monitor.showUninstallConfirmation = true }.disabled(app.path.hasPrefix("/System/")) }
                        Divider(); Text("Related Files").font(.headline)
                        ForEach(monitor.related) { row in Toggle(isOn: Binding(get: { monitor.selectedRelated.contains(row.path) }, set: { if $0 { monitor.selectedRelated.insert(row.path) } else { monitor.selectedRelated.remove(row.path) } })) { VStack(alignment: .leading) { Text(row.name); Text(row.value).font(.caption).foregroundStyle(.secondary) } } }
                        if monitor.related.isEmpty { Text("No related files found.").foregroundStyle(.secondary) }
                    }.padding(20)
                } else { ContentUnavailableView("Select an application", systemImage: "app") }
            }.frame(minWidth: 390)
        }.confirmationDialog("Move application to Trash?", isPresented: Binding(get: { monitor.showUninstallConfirmation }, set: { monitor.showUninstallConfirmation = $0 }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                guard let app = monitor.rows.first(where: { $0.id == monitor.rowSelection }), !app.path.hasPrefix("/System/") else { return }
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
                    for file in monitor.related where monitor.selectedRelated.contains(file.path) { try FileManager.default.trashItem(at: URL(fileURLWithPath: file.path), resultingItemURL: nil) }
                    monitor.reload()
                } catch { monitor.message = error.localizedDescription }
            }
        } message: { Text("The application and selected related files will be moved to Trash.") }
    }
}
private struct DriversInspectorView: View {
    @Environment(MonitorModel.self) private var monitor
    var body: some View {
        @Bindable var settings = monitor
        VStack(spacing: 0) {
            HStack {
                MonitorGroup("Drivers") { Text(String(monitor.rows.count)).font(.title2).monospacedDigit() }
                MonitorGroup("Loaded") { Text(String(monitor.rows.filter { $0.enabled == true }.count)).font(.title2).monospacedDigit() }
                MonitorGroup("Third-party") { Text(String(monitor.rows.filter { $0.vendor != "Apple" && !$0.id.hasPrefix("com.apple.") }.count)).font(.title2).monospacedDigit() }
                MonitorGroup("Wired") { Text(monitor.rows.compactMap(\.wired).isEmpty ? "n/a" : DisplayValue.bytes(monitor.rows.compactMap(\.wired).reduce(0, +))).font(.title2).monospacedDigit() }
            }.padding(14)
            Picker("Filter", selection: $settings.driverFilter) { ForEach(["All", "Loaded", "Not loaded", "Third-party", "Extensions"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }.pickerStyle(.segmented).padding(14)
            Table(monitor.filteredRows, selection: $settings.rowSelection) {
                TableColumn("Driver", value: \.name)
                TableColumn("State") { Text(LocalizedStringKey($0.enabled.map { $0 ? "Loaded" : "Not loaded" } ?? "n/a")) }
                TableColumn("Version", value: \.version)
                TableColumn("Wired") { Text(DisplayValue.bytes($0.wired)).monospacedDigit() }.width(80)
                TableColumn("Vendor", value: \.vendor)
                TableColumn("Kind", value: \.group)
            }
            if let row = monitor.rows.first(where: { $0.id == monitor.rowSelection }) {
                Divider(); ScrollView { VStack(alignment: .leading, spacing: 12) { Text(row.name).font(.headline); InspectorValues(entries: [("Bundle identifier", row.id), ("Kind", row.group), ("Version", row.version), ("Vendor", row.vendor), ("Wired", DisplayValue.bytes(row.wired)), ("Location", row.path.nonemptyOrNA)]); DisclosureGroup("Raw details") { Text(row.value).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }; HStack { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)]) }.disabled(row.path.isEmpty); Button("Copy Details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.value, forType: .string) } } }.padding(16).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 210)
            }
        }
    }
}
private struct BenchmarksInspectorView: View {
    @Environment(BenchmarkModel.self) private var benchmark
    var body: some View {
        @Bindable var settings = benchmark
        VStack(spacing: 18) {
            Picker("Benchmark", selection: $settings.kind) { ForEach(["CPU", "GPU", "Disk", "Internet", "SiliconPulse Score"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }.pickerStyle(.segmented).disabled(benchmark.isRunning)
            if let latest = benchmark.results.first(where: { $0.kind == benchmark.kind }) {
                HStack {
                    MonitorGroup("Result") { Text(DisplayValue.decimal(latest.primary)).font(.system(size: 40, weight: .semibold)).monospacedDigit(); Text(latest.unit).foregroundStyle(.secondary) }
                    if let secondary = latest.secondary { MonitorGroup("Secondary result") { Text(DisplayValue.decimal(secondary)).font(.system(size: 40, weight: .semibold)).monospacedDigit(); Text(latest.unit).foregroundStyle(.secondary) } }
                }
                Text(latest.notes).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else { ContentUnavailableView("No results yet", systemImage: "speedometer") }
            HStack { if benchmark.isRunning { ProgressView().controlSize(.small); Text(benchmark.progress); Button("Cancel") { benchmark.cancel() } } else { Button("Start benchmark") { benchmark.start() }.buttonStyle(.borderedProminent) }; Spacer(); Button("Clear History…", role: .destructive) { benchmark.clear() }.disabled(benchmark.isRunning) }
            if benchmark.kind == "Internet" { Text("This test downloads and uploads data using Apple's networkQuality service.").font(.caption).foregroundStyle(.secondary) }
            Table(benchmark.results.filter { $0.kind == benchmark.kind }) {
                TableColumn("Date") { Text($0.date.formatted()) }
                TableColumn("Result") { Text(DisplayValue.decimal($0.primary) + " " + $0.unit).monospacedDigit() }
                TableColumn("Secondary result") { Text(DisplayValue.decimal($0.secondary) + " " + $0.unit).monospacedDigit() }
                TableColumn("Notes", value: \.notes)
            }
            if let message = benchmark.message { Text(message).foregroundStyle(.red) }
        }.padding(20)
    }
}
private extension String { var nonemptyOrNA: String { isEmpty ? "n/a" : self } }

private func monitorPowerValue(_ value: Double?) -> String { guard let value, value.isFinite else { return "n/a" }; return abs(value) < 1 ? DisplayValue.decimal(value * 1000, digits: 0, suffix: " mW") : DisplayValue.decimal(value, suffix: " W") }

@MainActor private func monitorTemperature(_ celsius: Double?) -> String { guard let celsius else { return "n/a" }; let fahrenheit = AppModel.shared.fahrenheit; return DisplayValue.decimal(fahrenheit ? celsius * 9 / 5 + 32 : celsius, suffix: fahrenheit ? " °F" : " °C") }

@MainActor private func replayValue(_ key: String, _ value: Double?) -> String {
    if key.contains("power") || key == "Power" { return monitorPowerValue(value) }
    if key == "Temperature" { return monitorTemperature(value) }
    if key.contains("Network") || key.contains("Disk") { return AppModel.shared.formatRate(value) }
    return DisplayValue.decimal(value, suffix: "%")
}
