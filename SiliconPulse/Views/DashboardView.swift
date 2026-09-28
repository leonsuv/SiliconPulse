import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let panelController: PanelController
    let onSettings: () -> Void
    private var cards: [String] {
        model.sectionOrder.filter { model.visibleSections.contains($0) && (($0 != "Bluetooth" || !model.snapshot.bluetooth.isEmpty) && ($0 != "Fans" || !model.snapshot.fans.isEmpty)) }
    }

    var body: some View {
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(.primary)
                Text("SiliconPulse").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button { panelController.setPinned(!panelController.pinned) } label: {
                    Image(systemName: panelController.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(panelController.pinned ? Color.accentColor : Color.primary)
                }.buttonStyle(.plain).help(panelController.pinned ? Text("Unpin panel") : Text("Pin panel"))
                    .accessibilityLabel(panelController.pinned ? "Unpin panel" : "Pin panel")
                Button { panelController.editMode.toggle() } label: {
                    Image(systemName: panelController.editMode ? "checkmark" : "pencil").foregroundStyle(.primary)
                }.buttonStyle(.plain).help(panelController.editMode ? Text("Done editing") : Text("Edit cards"))
                    .accessibilityLabel(panelController.editMode ? "Done editing" : "Edit cards")
                Button(action: onSettings) {
                    Image(systemName: "gearshape").foregroundStyle(.primary)
                }.buttonStyle(.plain).help(Text("Settings"))
            }.padding(.horizontal, 16).padding(.vertical, 8)

            HStack(spacing: 5) {
                GlanceTile(title: "CPU", value: model.value(for: "CPU %"), points: model.cpuHistory, color: .blue)
                GlanceTile(title: "GPU", value: model.value(for: "GPU %"), points: model.gpuHistory, color: .teal)
                GlanceTile(title: "RAM", value: model.value(for: "RAM %"), points: model.memoryHistory, color: .purple)
                GlanceTile(title: "Battery W", value: model.value(for: "Battery W"), points: model.batteryPowerHistory, color: .orange)
            }.padding(.horizontal, 10).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards, id: \.self) { title in CardView(title: title) }
                }.frame(maxWidth: .infinity, alignment: .top).padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack {
                Text(model.snapshot.system.chip ?? "Apple Silicon")
                Spacer()
                Text("macOS \(model.snapshot.system.macOS)")
                Button("Copy snapshot") { model.copySnapshot() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.caption2).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GlanceTile: View {
    let title: String
    let value: String
    let points: [TelemetryPoint]
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Chart(points) { point in if let sample = point.value { LineMark(x: .value("Time", point.id), y: .value(title, sample)).foregroundStyle(color) } }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 15).transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity).frame(height: 48, alignment: .leading).padding(5)
        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
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
                    if !model.expanded.contains(title) { Text(summary(for: title)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 3)
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
        ["Battery":"battery.100percent", "Power":"bolt.fill", "GPU":"display", "CPU":"cpu", "Memory":"memorychip", "Disk":"internaldrive", "Network":"wifi", "Thermal":"thermometer.medium", "Processes":"list.number", "Sleep blockers":"moon.zzz", "System":"desktopcomputer", "Bluetooth":"headphones", "Fans":"fanblades"][title] ?? "circle"
    }

    @ViewBuilder private var content: some View {
        switch title {
        case "Battery": battery
        case "Power": power
        case "GPU": gpu
        case "CPU": cpu
        case "Memory": memory
        case "Disk": disk
        case "Network": network
        case "Thermal": thermal
        case "Processes": processes
        case "Sleep blockers": sleepBlockers
        case "System": system
        case "Bluetooth": bluetooth
        case "Fans": fans
        default: EmptyView()
        }
    }



    private func summary(for section: String) -> String {
        switch section {
        case "CPU": return model.value(for: "CPU %")
        case "GPU": return model.value(for: "GPU %")
        case "Memory": return model.formatBytes(model.snapshot.memory.used)
        case "Network": return "↓ \(rate(model.snapshot.network.downBytesPerSecond))  ↑ \(rate(model.snapshot.network.upBytesPerSecond))"
        case "Battery": return model.value(for: "Battery %")
        case "Power": return model.value(for: "Power W")
        case "Disk": return model.formatRate(model.snapshot.diskIO.readBytesPerSecond)
        default: return ""
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
            rows([("Renderer", DisplayValue.decimal(g.rendererUtilization, digits: 0, suffix: "%")), ("Tiler", DisplayValue.decimal(g.tilerUtilization, digits: 0, suffix: "%")), ("GPU memory in use", model.formatBytes(g.memoryInUse)), ("GPU cores", DisplayValue.number(g.coreCount)), ("GPU power", powerValue(model.snapshot.power.gpu))])
            Chart(model.gpuHistory) { point in if let value = point.value { LineMark(x: .value("Second", point.id), y: .value("GPU", value)).foregroundStyle(.tint) } }
                .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34).transaction { $0.animation = nil }.accessibilityLabel("GPU utilization history")
        }
    }
    private var cpu: some View {
        VStack(spacing: 6) {
            HStack { Text("Total"); Spacer(); Text(DisplayValue.decimal(model.snapshot.cpu.load.map { $0 * 100 }, suffix: "%")).monospacedDigit() }
            rows([("User", DisplayValue.decimal(model.snapshot.cpu.user, digits: 0, suffix: "%")), ("System", DisplayValue.decimal(model.snapshot.cpu.system, digits: 0, suffix: "%")), ("Idle", DisplayValue.decimal(model.snapshot.cpu.idle, digits: 0, suffix: "%")), ("Load average 1 / 5 / 15", model.snapshot.cpu.loadAverage.map { DisplayValue.decimal($0, digits: 2) }.joined(separator: " / ").isEmpty ? "n/a" : model.snapshot.cpu.loadAverage.map { DisplayValue.decimal($0, digits: 2) }.joined(separator: " / ")), ("Processes", DisplayValue.number(model.snapshot.cpu.processCount))])
            HStack(spacing: 8) { clusterBar("E", value: model.snapshot.cpu.eAverage, tint: .teal); clusterBar("P", value: model.snapshot.cpu.pAverage, tint: .orange) }
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
    private var memory: some View {
        VStack(spacing: 7) {
            usageCapsule(model.snapshot.memory.usedPercent, tint: .blue)
            rows([("Used", model.formatBytes(model.snapshot.memory.used)), ("Free", model.formatBytes(model.snapshot.memory.free)), ("App memory", model.formatBytes(model.snapshot.memory.app)), ("Cached files", model.formatBytes(model.snapshot.memory.cached)), ("Wired", model.formatBytes(model.snapshot.memory.wired)), ("Compressed", model.formatBytes(model.snapshot.memory.compressed)), ("Swap used", model.formatBytes(model.snapshot.memory.swapUsed)), ("Page in / out per sec", "\(DisplayValue.decimal(model.snapshot.memory.pageInPerSecond, digits: 0)) / \(DisplayValue.decimal(model.snapshot.memory.pageOutPerSecond, digits: 0))"), ("Pressure", model.snapshot.memory.pressure ?? "n/a")])
            Chart(model.memoryHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("Used %", v)).foregroundStyle(.blue) } }.chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34).transaction { $0.animation = nil }
        }
    }
    private var disk: some View {
        VStack(spacing: 7) {
            usageCapsule(model.snapshot.disk.total.flatMap { total in model.snapshot.disk.free.map { Double(total - $0) / Double(total) * 100 } }, tint: .purple)
            rows([("Volume", model.snapshot.disk.volumeName ?? "n/a"), ("File system", model.snapshot.disk.fileSystem ?? "n/a"), ("Available incl. purgeable", model.formatBytes(model.snapshot.disk.importantFree)), ("Boot volume used", model.snapshot.disk.total.flatMap { total in model.snapshot.disk.free.map { model.formatBytes(total - $0) } } ?? "n/a"), ("Available", model.formatBytes(model.snapshot.disk.free)), ("Total", model.formatBytes(model.snapshot.disk.total)), ("SMART status", model.snapshot.disk.smartStatus ?? "n/a"), ("Read", rate(model.snapshot.diskIO.readBytesPerSecond)), ("Write", rate(model.snapshot.diskIO.writeBytesPerSecond)), ("Read IOPS", DisplayValue.decimal(model.snapshot.diskIO.readIOPS, digits: 0)), ("Write IOPS", DisplayValue.decimal(model.snapshot.diskIO.writeIOPS, digits: 0))])
            ForEach(model.snapshot.disk.externalVolumes) { volume in rows([(volume.name, "\(model.formatBytes(volume.free)) / \(model.formatBytes(volume.total))")]) }
            Chart { ForEach(model.diskReadHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("Rate", v)).foregroundStyle(by: .value("Series", "Read")) } }; ForEach(model.diskWriteHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("Rate", v)).foregroundStyle(by: .value("Series", "Write")) } } }
                .chartForegroundStyleScale(["Read": Color.blue, "Write": Color.orange]).chartLegend(position: .bottom, alignment: .leading, spacing: 4).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 44).transaction { $0.animation = nil }
        }
    }
    private var bluetooth: some View {
        VStack(spacing: 5) { ForEach(model.snapshot.bluetooth) { device in HStack { Text(device.name); Spacer(); Text("\(device.percent)%").foregroundStyle(device.percent < 20 ? .orange : .secondary) }.font(.caption) } }
    }
    private var fans: some View {
        VStack(spacing: 5) { ForEach(model.snapshot.fans) { fan in HStack { Text("Fan \(fan.id + 1)"); Spacer(); Text(fan.rpm.map { DisplayValue.decimal($0, digits: 0, suffix: " RPM") } ?? "n/a") }.font(.caption) } }
    }
    private func clusterBar(_ title: String, value: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { HStack { Text(title); Spacer(); Text(DisplayValue.decimal(value.map { $0 * 100 }, digits: 0, suffix: "%")) }; ProgressView(value: value ?? 0).tint(tint) }.font(.caption2).frame(maxWidth: .infinity)
    }
    private func usageCapsule(_ percent: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { HStack { Text("Usage"); Spacer(); Text(DisplayValue.decimal(percent, digits: 0, suffix: "%")) }; ProgressView(value: min(1, max(0, (percent ?? 0) / 100))).tint(tint) }.font(.caption2)
    }
    private func stateColor(_ state: Int) -> Color { let colors: [Color] = [.green, .yellow, .orange, .red]; return colors.indices.contains(state) ? colors[state] : .gray }

    private var network: some View {
        VStack(spacing: 7) {
            rows([("Down", rate(model.snapshot.network.downBytesPerSecond)), ("Up", rate(model.snapshot.network.upBytesPerSecond)), ("Interface", model.snapshot.network.interfaceName ?? "n/a"), ("Local IPv4", model.snapshot.network.localIPv4 ?? "n/a"), ("Wi-Fi RSSI", model.snapshot.network.rssi.map { "\($0) dBm" } ?? "n/a"), ("Noise / SNR", "\(model.snapshot.network.noise.map(String.init) ?? "n/a") / \(model.snapshot.network.snr.map(String.init) ?? "n/a") dBm"), ("Channel", model.snapshot.network.channel ?? "n/a"), ("Link rate", DisplayValue.decimal(model.snapshot.network.linkMbps, suffix: " Mbps")), ("PHY mode", model.snapshot.network.phyMode ?? "n/a"), ("Security", model.snapshot.network.security ?? "n/a"), ("TX power", model.snapshot.network.transmitPower.map { "\($0) dBm" } ?? "n/a"), ("Totals since boot", "\(model.formatBytes(model.snapshot.network.totalDown)) / \(model.formatBytes(model.snapshot.network.totalUp))"), ("VPN", model.snapshot.network.vpnActive.map { $0 ? "Active" : "Off" } ?? "n/a"), ("Latency", model.snapshot.network.latencyMs.map { DisplayValue.decimal($0, digits: 0, suffix: " ms") } ?? "n/a")])
            Chart {
                ForEach(model.networkDownHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("Rate", v)).foregroundStyle(by: .value("Direction", "Down")) } }
                ForEach(model.networkUpHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("Rate", v)).foregroundStyle(by: .value("Direction", "Up")) } }
            }.chartForegroundStyleScale(["Down": Color.blue, "Up": Color.orange]).chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34).transaction { $0.animation = nil }
        }
    }
    private var thermal: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Circle().fill(thermalColor).frame(width: 9, height: 9); Text(thermalName).foregroundStyle(.primary); Spacer() }
            if !model.snapshot.temperatures.sensors.isEmpty {
                let groups = ["CPU/SoC", "Battery", "SSD", "Other"]
                ForEach(groups, id: \.self) { group in
                    let values = model.snapshot.temperatures.sensors.filter { $0.group == group }.map(\.celsius)
                    if !values.isEmpty { rows([(group, "avg \(temperature(values.reduce(0, +) / Double(values.count))) · max \(temperature(values.max()))")]) }
                }
                Chart(model.temperatureHistory) { p in if let v = p.value { LineMark(x: .value("Second", p.id), y: .value("°C", v)).foregroundStyle(.red) } }
                    .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 30).transaction { $0.animation = nil }
                HStack(spacing: 1) { ForEach(Array(model.thermalTimeline.enumerated()), id: \.offset) { _, state in Rectangle().fill(stateColor(state)).frame(height: 6) } }.clipShape(Capsule())
            }
        }
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
                    Text(model.processMemorySort ? model.formatBytes(process.memoryBytes) : DisplayValue.decimal(process.cpuPercent, digits: 0, suffix: "%"))
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
        rows([("Model name", model.snapshot.system.chip ?? "n/a"), ("Model identifier", model.snapshot.system.model ?? "n/a"), ("Chip", model.snapshot.system.chip ?? "n/a"), ("E cores", DisplayValue.number(model.snapshot.system.eCores)), ("P cores", DisplayValue.number(model.snapshot.system.pCores)), ("GPU cores", DisplayValue.number(model.snapshot.system.gpuCores)), ("Model name", model.snapshot.system.chip ?? "n/a"), ("RAM", model.snapshot.system.memoryGB.map { model.formatBytes(UInt64($0 * 1_000_000_000)) } ?? "n/a"), ("macOS", model.snapshot.system.macOS), ("Build", model.snapshot.system.build ?? "n/a"), ("Uptime", DisplayValue.duration(model.snapshot.system.uptime)), ("Boot time", model.snapshot.system.bootTime?.formatted(date: .abbreviated, time: .shortened) ?? "n/a")])
    }
    private func rows(_ entries: [(String, String)]) -> some View {
        VStack(spacing: model.compactRows ? 2 : 5) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, row in
                HStack { Text(LocalizedStringKey(row.0)).foregroundStyle(.secondary); Spacer(minLength: 8); Text(row.1).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8) }
                    .font(.caption).frame(minHeight: model.compactRows ? 12 : 17)
            }
        }
    }
    private func powerValue(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "n/a" }
        return abs(watts) < 1 ? DisplayValue.decimal(watts * 1_000, digits: 0, suffix: " mW") : DisplayValue.decimal(watts, suffix: " W")
    }
    private func rate(_ bps: Double?) -> String { model.formatRate(bps) }
    private func temperature(_ c: Double?) -> String {
        guard let c else { return "n/a" }
        return DisplayValue.decimal(model.fahrenheit ? c * 9 / 5 + 32 : c, suffix: model.fahrenheit ? " °F" : " °C")
    }
    private var thermalName: String { ["Nominal", "Fair", "Serious", "Critical"].indices.contains(model.snapshot.cpu.thermalState) ? ["Nominal", "Fair", "Serious", "Critical"][model.snapshot.cpu.thermalState] : "n/a" }
    private var thermalColor: Color { let colors: [Color] = [.green, .yellow, .orange, .red]; return colors.indices.contains(model.snapshot.cpu.thermalState) ? colors[model.snapshot.cpu.thermalState] : .gray }
}
