import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    private let cards = ["Battery", "Power", "CPU", "Memory", "Disk", "Network", "Thermal", "Processes"]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "waveform.path.ecg").foregroundStyle(.tint); Text("SiliconPulse").font(.headline); Spacer(); Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings") }
                .padding(.horizontal, 16).padding(.vertical, 12)
            ScrollView { VStack(spacing: 8) { ForEach(cards, id: \.self) { CardView(title: $0) } }.padding(10) }
            HStack { Text(model.snapshot.system.chip ?? "Apple Silicon"); Spacer(); Text("macOS \(model.snapshot.system.macOS)") }.font(.caption2).foregroundStyle(.secondary).padding(12)
        }.background(.regularMaterial)
    }
}
private struct CardView: View {
    @Environment(AppModel.self) private var model
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy(duration: 0.2)) { if model.expanded.contains(title) { model.expanded.remove(title) } else { model.expanded.insert(title) } } } label: {
                HStack { Image(systemName: icon).foregroundStyle(.tint).frame(width: 20); Text(title).font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: model.expanded.contains(title) ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary) }.contentShape(Rectangle()).padding(10)
            }.buttonStyle(.plain).accessibilityLabel("\(title), \(model.expanded.contains(title) ? "expanded" : "collapsed")")
            if model.expanded.contains(title) { Divider().padding(.horizontal, 10); content.padding(10) }
        }.background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 0.5))
    }
    private var icon: String { ["Battery":"battery.100percent", "Power":"bolt.fill", "CPU":"cpu", "Memory":"memorychip", "Disk":"internaldrive", "Network":"wifi", "Thermal":"thermometer.medium", "Processes":"list.number" ][title] ?? "circle" }
    @ViewBuilder private var content: some View {
        switch title {
        case "Battery": battery
        case "Power": rows([("CPU", DisplayValue.decimal(model.snapshot.power.cpu, suffix: " W")), ("GPU", DisplayValue.decimal(model.snapshot.power.gpu, suffix: " W")), ("ANE", DisplayValue.decimal(model.snapshot.power.ane, suffix: " W")), ("Combined", DisplayValue.decimal(model.snapshot.power.combined, suffix: " W")), ("E / P frequency", "n/a"), ("GPU frequency", DisplayValue.decimal(model.snapshot.power.gpuFrequencyMHz, suffix: " MHz"))])
        case "CPU": cpu
        case "Memory": rows([("Used", DisplayValue.bytes(model.snapshot.memory.used)), ("Wired", DisplayValue.bytes(model.snapshot.memory.wired)), ("Compressed", DisplayValue.bytes(model.snapshot.memory.compressed)), ("Pressure", model.snapshot.memory.pressure ?? "n/a"), ("Physical RAM", DisplayValue.decimal(model.snapshot.system.memoryGB, suffix: " GB"))])
        case "Disk": rows([("Boot volume used", model.snapshot.disk.total.flatMap { t in model.snapshot.disk.free.map { DisplayValue.bytes(t - $0) } } ?? "n/a"), ("Available", DisplayValue.bytes(model.snapshot.disk.free)), ("Total", DisplayValue.bytes(model.snapshot.disk.total))])
        case "Network": rows([("Down", DisplayValue.decimal(model.snapshot.network.downBytesPerSecond.map { $0 / 1_000_000 }, suffix: " MB/s")), ("Up", DisplayValue.decimal(model.snapshot.network.upBytesPerSecond.map { $0 / 1_000_000 }, suffix: " MB/s")), ("Wi-Fi RSSI", model.snapshot.network.rssi.map { "\($0) dBm" } ?? "n/a"), ("Channel", model.snapshot.network.channel ?? "n/a"), ("Link rate", DisplayValue.decimal(model.snapshot.network.linkMbps, suffix: " Mbps"))])
        case "Thermal": HStack { Circle().fill(thermalColor).frame(width: 9, height: 9); Text(thermalName).font(.subheadline); Spacer(); Text("\(model.snapshot.cpu.thermalState)").foregroundStyle(.secondary) }.accessibilityElement(children: .combine)
        default: VStack(alignment: .leading, spacing: 5) { if model.snapshot.processes.isEmpty { Text("n/a").foregroundStyle(.secondary) } else { ForEach(model.snapshot.processes) { p in HStack { Text(p.name).lineLimit(1); Spacer(); Text(DisplayValue.decimal(p.cpuPercent, digits: 0, suffix: "%")).monospacedDigit() }.font(.caption) } } }
        }
    }
    private var battery: some View {
        let b = model.snapshot.battery
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) { Text(b.percent.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a").font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit(); Text((b.charging ?? false) ? "Charging" : "Battery").foregroundStyle(.secondary); Spacer(); Gauge(value: b.health ?? 0, in: 0...1) { Text("Health") } currentValueLabel: { Text(b.health.map { DisplayValue.decimal($0 * 100, digits: 0, suffix: "%") } ?? "n/a") }.gaugeStyle(.accessoryCircular).tint(.green).frame(width: 65, height: 65).accessibilityLabel("Battery health") }
            rows([("Cycles / design 1000", "\(DisplayValue.number(b.cycles)) / 1000"), ("Capacity", "\(DisplayValue.number(b.nominalCapacity)) / \(DisplayValue.number(b.designCapacity)) mAh"), ("Voltage / current", "\(DisplayValue.decimal(b.voltage, suffix: " V")) / \(DisplayValue.decimal(b.amperage, suffix: " A"))"), ("Live power", DisplayValue.decimal(b.watts, suffix: " W")), ("Temperature", temperature(b.temperatureC)), ("Time remaining", b.timeRemainingMinutes.map { "\($0 / 60)h \($0 % 60)m" } ?? "n/a"), ("Adapter", DisplayValue.decimal(b.adapterWatts, suffix: " W"))])
        }.accessibilityElement(children: .contain)
    }
    private var cpu: some View {
        VStack(spacing: 6) {
            HStack { Text("Total"); Spacer(); Text(DisplayValue.decimal(model.snapshot.cpu.load.map { $0 * 100 }, suffix: "%")).monospacedDigit() }
            Chart(Array(model.history.enumerated()), id: \.offset) { i, v in AreaMark(x: .value("Second", i), y: .value("CPU", v)).foregroundStyle(.tint.opacity(0.18)); LineMark(x: .value("Second", i), y: .value("CPU", v)).foregroundStyle(.tint) }.chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 42).accessibilityLabel("CPU usage history")
            HStack(spacing: 4) { ForEach(model.snapshot.cpu.cores) { core in VStack(spacing: 3) { Gauge(value: core.percent) {}.gaugeStyle(.accessoryCircular).tint(core.kind == "E" ? .teal : .orange); Text("\(core.kind)\(core.id + 1)").font(.system(size: 8)).foregroundStyle(.secondary) }.accessibilityLabel("\(core.kind) core \(core.id + 1): \(Int(core.percent * 100)) percent") } }.frame(maxWidth: .infinity).padding(.top, 3)
            HStack { Text("E \(DisplayValue.number(model.snapshot.system.eCores))"); Spacer(); Text("P \(DisplayValue.number(model.snapshot.system.pCores))"); Spacer(); Text("\(model.snapshot.system.cpuCores) cores") }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func rows(_ entries: [(String, String)]) -> some View { VStack(spacing: 5) { ForEach(Array(entries.enumerated()), id: \.offset) { _, row in HStack { Text(row.0).foregroundStyle(.secondary); Spacer(minLength: 10); Text(row.1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }.font(.caption) } } }
    private func temperature(_ c: Double?) -> String { guard let c else { return "n/a" }; let v = model.fahrenheit ? c * 9 / 5 + 32 : c; return DisplayValue.decimal(v, suffix: model.fahrenheit ? " °F" : " °C") }
    private var thermalName: String { ["Nominal", "Fair", "Serious", "Critical"].indices.contains(model.snapshot.cpu.thermalState) ? ["Nominal", "Fair", "Serious", "Critical"][model.snapshot.cpu.thermalState] : "n/a" }
    private var thermalColor: Color { let colors: [Color] = [.green, .yellow, .orange, .red]; return colors.indices.contains(model.snapshot.cpu.thermalState) ? colors[model.snapshot.cpu.thermalState] : .gray }
}
