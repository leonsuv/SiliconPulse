import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    private let cards = ["Battery", "Power", "GPU", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes", "Sleep blockers", "System"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(.primary)
                Text("SiliconPulse").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: {
                    Image(systemName: "gearshape").foregroundStyle(.primary)
                }.buttonStyle(.plain).help(Text("Settings"))
            }.padding(.horizontal, 16).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards, id: \.self) { title in CardView(title: title) }
                }.frame(width: 340, alignment: .top).padding(10)
            }.clipped()

            HStack {
                Text(model.snapshot.system.chip ?? "Apple Silicon")
                Spacer()
                Text("macOS \(model.snapshot.system.macOS)")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.caption2).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: 360).frame(minHeight: 400, maxHeight: 640)
        .background(.regularMaterial)
        .overlay { PopoverWindowObserver { model.setPopoverOpen($0) }.frame(width: 0, height: 0) }
    }
}

private struct CardView: View {
    @Environment(AppModel.self) private var model
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if model.expanded.contains(title) { model.expanded.remove(title) } else { model.expanded.insert(title) }
            } label: {
                HStack {
                    Image(systemName: icon).foregroundStyle(.primary).frame(width: 20)
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: model.expanded.contains(title) ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle()).padding(.horizontal, 10)
            }.buttonStyle(.plain)
            if model.expanded.contains(title) {
                Divider().padding(.horizontal, 10)
                content.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 0.5))
    }
    private var icon: String {
        ["Battery":"battery.100percent", "Power":"bolt.fill", "GPU":"display", "CPU":"cpu", "Memory":"memorychip", "Disk":"internaldrive", "Network":"wifi", "Thermal":"thermometer.medium", "Processes":"list.number", "Sleep blockers":"moon.zzz", "System":"desktopcomputer"][title] ?? "circle"
    }

    @ViewBuilder private var content: some View {
        switch title {
        case "Battery": battery
        case "Power": power
        case "GPU": gpu
        case "CPU": cpu
        case "Memory": rows([("Used", DisplayValue.bytes(model.snapshot.memory.used)), ("Wired", DisplayValue.bytes(model.snapshot.memory.wired)), ("Compressed", DisplayValue.bytes(model.snapshot.memory.compressed)), ("Pressure", model.snapshot.memory.pressure ?? "n/a"), ("Physical RAM", DisplayValue.decimal(model.snapshot.system.memoryGB, suffix: " GB"))])
        case "Disk": rows([("Boot volume used", model.snapshot.disk.total.flatMap { total in model.snapshot.disk.free.map { DisplayValue.bytes(total - $0) } } ?? "n/a"), ("Available", DisplayValue.bytes(model.snapshot.disk.free)), ("Total", DisplayValue.bytes(model.snapshot.disk.total))])
        case "Network": network
        case "Thermal": thermal
        case "Processes": processes
        case "Sleep blockers": sleepBlockers
        case "System": system
        default: EmptyView()
        }
    }

    private var battery: some View {
        let b = model.snapshot.battery
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Text(b.percent.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a")
                    .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(batteryStatus)).font(.subheadline).foregroundStyle(.primary)
                    Text(b.charging == true ? "Time to full" : "Time remaining").font(.caption).foregroundStyle(.secondary)
                    Text(timeString(b.charging == true ? b.timeToFullMinutes : b.timeRemainingMinutes)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 5)
                        Circle().trim(from: 0, to: min(1, max(0, b.health ?? 0)))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text(b.health.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a")
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.primary).minimumScaleFactor(0.7)
                    }.frame(width: 56, height: 56).accessibilityLabel("Battery health")
                    Text("Health").font(.caption2).foregroundStyle(.secondary)
                }
            }
            rows([("Cycles / design 1000", "\(DisplayValue.number(b.cycles)) / 1000"), ("Capacity", "\(DisplayValue.number(b.nominalCapacity)) / \(DisplayValue.number(b.designCapacity)) mAh"), ("Remaining capacity", "\(DisplayValue.number(b.remainingCapacity)) mAh"), ("Last full charge", "\(DisplayValue.number(b.fullChargeCapacity)) mAh"), ("Capacity loss", b.health.map { DisplayValue.decimal((1 - $0) * 100, suffix: "%") } ?? "n/a"), ("Voltage / current", "\(DisplayValue.decimal(b.voltage, suffix: " V")) / \(DisplayValue.decimal(b.amperage, suffix: " A"))"), ("Live power", DisplayValue.decimal(b.watts, suffix: " W")), ("Temperature", temperature(b.temperatureC)), ("Adapter", b.externalConnected == true ? DisplayValue.decimal(b.adapterWatts, suffix: " W") : "-")])
            Chart(model.batteryPowerHistory) { point in if let value = point.value { LineMark(x: .value("Second", point.id), y: .value("Watts", value)).foregroundStyle(.orange) } }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 32).transaction { $0.animation = nil }.accessibilityLabel("Battery power history")
        }
    }
    private var batteryStatus: String {
        if model.snapshot.battery.fullyCharged == true { return "Fully charged" }
        if model.snapshot.battery.charging == true { return "Charging" }
        if model.snapshot.battery.externalConnected == true { return "Plugged in, not charging" }
        return "On battery"
    }
    private func timeString(_ minutes: Int?) -> String { guard let minutes, minutes > 0 else { return "n/a" }; return "\(minutes / 60)h \(minutes % 60)m" }

    private var power: some View {
        VStack(spacing: 6) {
            rows([("CPU", powerValue(model.snapshot.power.cpu)), ("GPU", powerValue(model.snapshot.power.gpu)), ("ANE", powerValue(model.snapshot.power.ane)), ("DRAM", powerValue(model.snapshot.power.dram)), ("Combined", powerValue(model.snapshot.power.combined))])
            Chart(model.powerHistory) { point in if let value = point.value { LineMark(x: .value("Second", point.id), y: .value("Power", value)).foregroundStyle(.yellow) } }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34).transaction { $0.animation = nil }.accessibilityLabel("System power history")
        }
    }
    private var gpu: some View {
        let g = model.snapshot.gpu
        let progress = min(1, max(0, (g.utilization ?? 0) / 100))
        return VStack(spacing: 7) {
            HStack(spacing: 10) {
                ZStack { Circle().stroke(.quaternary, lineWidth: 4); Circle().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)) }
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading) { Text(g.utilization.map { DisplayValue.decimal($0, digits: 0, suffix: "%") } ?? "n/a").font(.title2).monospacedDigit(); Text("Device utilization").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            rows([("Renderer", DisplayValue.decimal(g.rendererUtilization, digits: 0, suffix: "%")), ("Tiler", DisplayValue.decimal(g.tilerUtilization, digits: 0, suffix: "%")), ("GPU memory in use", DisplayValue.bytes(g.memoryInUse)), ("GPU cores", DisplayValue.number(g.coreCount)), ("GPU power", powerValue(model.snapshot.power.gpu))])
            Chart(model.gpuHistory) { point in if let value = point.value { LineMark(x: .value("Second", point.id), y: .value("GPU", value)).foregroundStyle(.tint) } }
                .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34).transaction { $0.animation = nil }.accessibilityLabel("GPU utilization history")
        }
    }
    private var cpu: some View {
        VStack(spacing: 6) {
            HStack { Text("Total"); Spacer(); Text(DisplayValue.decimal(model.snapshot.cpu.load.map { $0 * 100 }, suffix: "%")).monospacedDigit() }
            Chart(model.cpuHistory) { point in if let value = point.value { LineMark(x: .value("Second", point.id), y: .value("CPU", value)).foregroundStyle(.tint) } }
                .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 36).transaction { $0.animation = nil }.accessibilityLabel("CPU usage history")
            HStack(spacing: 5) {
                ForEach(model.snapshot.cpu.cores) { core in
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) { RoundedRectangle(cornerRadius: 3).fill(.quaternary); RoundedRectangle(cornerRadius: 3).fill(core.kind == "E" ? Color.teal : Color.orange).frame(height: 36 * core.percent) }
                            .frame(width: 18, height: 36)
                        Text("\(core.kind)\(core.number)").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack { Text("E \(DisplayValue.number(model.snapshot.system.eCores))"); Spacer(); Text("P \(DisplayValue.number(model.snapshot.system.pCores))"); Spacer(); Text("\(model.snapshot.system.cpuCores) cores") }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var network: some View {
        rows([("Down", rate(model.snapshot.network.downBytesPerSecond)), ("Up", rate(model.snapshot.network.upBytesPerSecond)), ("Wi-Fi RSSI", model.snapshot.network.rssi.map { "\($0) dBm" } ?? "n/a"), ("Channel", model.snapshot.network.channel ?? "n/a"), ("Link rate", DisplayValue.decimal(model.snapshot.network.linkMbps, suffix: " Mbps"))])
    }
    private var thermal: some View {
        HStack { Circle().fill(thermalColor).frame(width: 9, height: 9); Text(thermalName).foregroundStyle(.primary); Spacer() }.accessibilityElement(children: .combine)
    }
    private var processes: some View {
        VStack(spacing: 7) {
            Picker("Ranking", selection: Binding(get: { model.processMemorySort ? "Memory" : "CPU" }, set: { model.setProcessMemorySort($0 == "Memory") })) {
                Text("CPU").tag("CPU"); Text("Memory").tag("Memory")
            }.pickerStyle(.segmented)
            if model.snapshot.processes.isEmpty { Text("n/a").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(model.snapshot.processes) { process in
                HStack(spacing: 6) {
                    if let icon = NSRunningApplication(processIdentifier: pid_t(process.id))?.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    else { Image(systemName: "app").frame(width: 18, height: 18).foregroundStyle(.secondary) }
                    Text(process.name).lineLimit(1).foregroundStyle(.primary)
                    Text("PID \(process.id)").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text(model.processMemorySort ? DisplayValue.bytes(process.memoryBytes) : DisplayValue.decimal(process.cpuPercent, digits: 0, suffix: "%"))
                        .monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }.font(.caption)
            }
        }
    }
    @ViewBuilder private var sleepBlockers: some View {
        if model.snapshot.sleepBlockers.isEmpty { Text("None").foregroundStyle(.secondary) }
        else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.snapshot.sleepBlockers) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blocker.name).font(.caption.weight(.medium))
                        ForEach(blocker.assertions, id: \.self) { assertion in Text(LocalizedStringKey(assertion)).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private var system: some View {
        rows([("Model", model.snapshot.system.model ?? "n/a"), ("Chip", model.snapshot.system.chip ?? "n/a"), ("E cores", DisplayValue.number(model.snapshot.system.eCores)), ("P cores", DisplayValue.number(model.snapshot.system.pCores)), ("GPU cores", DisplayValue.number(model.snapshot.system.gpuCores)), ("RAM", DisplayValue.decimal(model.snapshot.system.memoryGB, suffix: " GB")), ("macOS", model.snapshot.system.macOS), ("Build", model.snapshot.system.build ?? "n/a"), ("Uptime", DisplayValue.duration(model.snapshot.system.uptime)), ("Boot time", model.snapshot.system.bootTime?.formatted(date: .abbreviated, time: .shortened) ?? "n/a")])
    }
    private func rows(_ entries: [(String, String)]) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, row in
                HStack { Text(LocalizedStringKey(row.0)).foregroundStyle(.secondary); Spacer(minLength: 8); Text(row.1).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8) }.font(.caption).frame(minHeight: 15)
            }
        }
    }
    private func powerValue(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "n/a" }
        return abs(watts) < 1 ? DisplayValue.decimal(watts * 1_000, digits: 0, suffix: " mW") : DisplayValue.decimal(watts, suffix: " W")
    }
    private func rate(_ bps: Double?) -> String {
        guard let bps, bps.isFinite else { return "n/a" }
        return bps < 1_000_000 ? DisplayValue.decimal(bps / 1_000, suffix: " KB/s") : DisplayValue.decimal(bps / 1_000_000, suffix: " MB/s")
    }
    private func temperature(_ c: Double?) -> String {
        guard let c else { return "n/a" }
        return DisplayValue.decimal(model.fahrenheit ? c * 9 / 5 + 32 : c, suffix: model.fahrenheit ? " °F" : " °C")
    }
    private var thermalName: String { ["Nominal", "Fair", "Serious", "Critical"].indices.contains(model.snapshot.cpu.thermalState) ? ["Nominal", "Fair", "Serious", "Critical"][model.snapshot.cpu.thermalState] : "n/a" }
    private var thermalColor: Color { let colors: [Color] = [.green, .yellow, .orange, .red]; return colors.indices.contains(model.snapshot.cpu.thermalState) ? colors[model.snapshot.cpu.thermalState] : .gray }
}
