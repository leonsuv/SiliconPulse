import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let panelController: PanelController

    private var category: String { panelController.category }

    private var cards: [String] {
        let screenshotRun = ProcessInfo.processInfo.arguments.contains("--release-screenshot")
        let selectedCard = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--release-screenshot-card=") })?.split(separator: "=", maxSplits: 1).last.map(String.init)
        if screenshotRun {
            if let selectedCard { return AppModel.allSections.contains(selectedCard) ? [selectedCard] : [] }
            return AppModel.allSections
        }
        let ordered = model.sectionOrder.filter { section in
            (selectedCard == nil || selectedCard == section) &&
            (panelController.editMode || section != "Bluetooth" || !model.snapshot.bluetooth.isEmpty) &&
            (panelController.editMode || section != "Fans" || !model.snapshot.fans.isEmpty)
        }
        guard panelController.editMode else { return ordered.filter { model.visibleSections.contains($0) && (category == "Overview" || sectionsForCategory.contains($0)) } }
        return ordered.filter { model.visibleSections.contains($0) } + ordered.filter { !model.visibleSections.contains($0) }
    }

    private var sectionsForCategory: Set<String> {
        switch category {
        case "Performance": ["CPU", "GPU", "Memory", "Processes"]
        case "Energy": ["Battery", "Power", "Thermal", "Fans"]
        case "System": ["Disk", "Network", "System", "Bluetooth", "Sleep blockers"]
        default: Set(AppModel.allSections)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if !panelController.editMode {
                    Picker("Category", selection: Binding(get: { category }, set: { panelController.category = $0 })) {
                        ForEach(["Overview", "Performance", "Energy", "System"], id: \.self) {
                            Text(LocalizedStringKey($0)).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .padding(.horizontal, 14).padding(.bottom, 12)
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if category == "Overview", !panelController.editMode {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: geometry.size.width >= 650 ? 4 : 2), spacing: 8) {
                                GlanceTile(title: "CPU", value: model.value(for: "CPU %"), points: model.cpuHistory, color: .blue)
                                GlanceTile(title: "GPU", value: model.value(for: "GPU %"), points: model.gpuHistory, color: .teal)
                                GlanceTile(title: "Memory", value: model.value(for: "RAM %"), points: model.memoryHistory, color: .purple)
                                GlanceTile(title: "Battery power", value: model.value(for: "Battery W"), points: model.batteryPowerHistory, color: .orange)
                            }
                            .padding(.bottom, 4)
                            .background { WindowDragHandle(enabled: panelController.isPinned) }
                        }
                        if category == "Energy", !panelController.editMode {
                            LowPowerModeControl().toggleStyle(.switch)
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                        // One continuous column keeps related measurements together.
                        ForEach(cards, id: \.self) { title in
                            CardView(title: title, isHidden: !model.visibleSections.contains(title), editMode: panelController.editMode, expansion: Binding(get: {
                                category == "Overview" ? panelController.overviewExpanded.contains(title) : model.expanded.contains(title)
                            }, set: { value in
                                if category == "Overview" {
                                    if value { panelController.overviewExpanded.insert(title) } else { panelController.overviewExpanded.remove(title) }
                                } else {
                                    if value { model.expanded.insert(title) } else { model.expanded.remove(title) }
                                }
                            }))
                            .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(section: title, model: model, enabled: panelController.editMode))
                        }
                        if cards.isEmpty {
                            ContentUnavailableView("No visible sections", systemImage: "rectangle.3.group", description: Text("Use Edit cards to choose what appears here."))
                        }
                        if panelController.editMode {
                            Button("Reset layout…") { panelController.showLayoutResetConfirmation = true }
                                .padding(.vertical, 8)
                                .confirmationDialog("Reset card layout?", isPresented: Binding(get: { panelController.showLayoutResetConfirmation }, set: { panelController.showLayoutResetConfirmation = $0 }), titleVisibility: .visible) {
                                    Button("Reset Layout", role: .destructive) { model.resetLayout(); panelController.overviewExpanded.removeAll() }
                                } message: { Text("Restore the default card order, visibility, and expanded state.") }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .id(category + (panelController.editMode ? "-editing" : "-reading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                Divider()
                HStack(spacing: 12) {
                    Label("Live", systemImage: "circle.fill").foregroundStyle(.green)
                    Spacer(minLength: 0)
                    Button("Details") { MonitorWindowController.shared.show() }
                        .help("Open monitor")
                    Button { model.copySnapshot() } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy snapshot").accessibilityLabel("Copy snapshot")
                    Menu {
                        Button("Overlay mode") { OverlayController.active?.toggle() }
                        Button("Edit cards") { panelController.editMode.toggle() }
                        Divider()
                        Button("Quit SiliconPulse") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions")
                    if panelController.isPinned {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.tertiary)
                            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                if panelController.resizeStartSize == nil { panelController.resizeStartSize = panelController.panel.frame.size }
                                if let start = panelController.resizeStartSize { panelController.resizePanel(width: start.width + value.translation.width, height: start.height - value.translation.height) }
                            }.onEnded { _ in panelController.resizeStartSize = nil })
                            .accessibilityLabel("Resize panel")
                    }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background { ZStack { Rectangle().fill(.regularMaterial); Color(nsColor: .windowBackgroundColor).opacity(0.88) } }
        .opacity(panelController.isPinned ? model.panelOpacity : 1)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.locale, model.locale)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                .frame(width: 30, height: 30).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("SiliconPulse").font(.system(size: 14, weight: .semibold))
                Text(model.snapshot.system.chip ?? "Apple Silicon").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { OverlayController.active?.toggle() } label: { Image(systemName: "rectangle.dashed") }
                .help(Text(OverlayL10n.text("Overlay mode", locale: model.locale))).accessibilityLabel(OverlayL10n.text("Overlay mode", locale: model.locale))
            Button { panelController.setPinned(!panelController.isPinned) } label: {
                Image(systemName: panelController.isPinned ? "pin.fill" : "pin").foregroundStyle(panelController.isPinned ? Color.blue : Color.secondary)
            }.help(panelController.isPinned ? Text("Unpin panel") : Text("Pin panel"))
                .accessibilityLabel(panelController.isPinned ? "Unpin panel" : "Pin panel")
            Button { panelController.editMode.toggle() } label: { Image(systemName: panelController.editMode ? "checkmark.circle.fill" : "slider.horizontal.3") }
                .help(panelController.editMode ? Text("Done editing") : Text("Edit cards"))
                .accessibilityLabel(panelController.editMode ? "Done editing" : "Edit cards")
            Button { SettingsWindowController.shared.show(model: model) } label: { Image(systemName: "gearshape") }
                .keyboardShortcut(",", modifiers: .command).help("Settings").accessibilityLabel("Settings")
            if panelController.isPinned {
                Button { panelController.close() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close panel")
            }
        }.buttonStyle(PanelToolStyle()).padding(.horizontal, 16).padding(.vertical, 12)
            .background { WindowDragHandle(enabled: panelController.isPinned) }
    }
}

private struct PanelToolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            .frame(width: 22, height: 28)
            .background(configuration.isPressed ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

}

private struct SectionDropDelegate: DropDelegate {
    let section: String
    let model: AppModel
    let enabled: Bool
    func dropEntered(info: DropInfo) {
        guard enabled, let provider = info.itemProviders(for: [UTType.plainText]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let value = value as? String else { return }
            Task { @MainActor in model.moveSection(value, before: section) }
        }
    }
    func performDrop(info: DropInfo) -> Bool { enabled }
}

private struct GlanceTile: View {
    let title: String
    let value: String
    let points: [TelemetryPoint]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TelemetryChart(lines: [TelemetryChartLine(name: title, points: points, color: color)], window: 31)
                    .frame(width: 64, height: 24)
                    .accessibilityLabel(Text("\(title) history"))
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CardView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let isHidden: Bool
    let editMode: Bool
    let expansion: Binding<Bool>
    private var isExpanded: Bool { expansion.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if editMode {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        .contentShape(Rectangle()).onDrag { NSItemProvider(object: title as NSString) }
                        .accessibilityLabel("Drag to reorder \(title)")
                    Button { model.moveSection(title, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain).font(.caption2).accessibilityLabel("Move \(title) up")
                    Button { model.moveSection(title, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).font(.caption2).accessibilityLabel("Move \(title) down")
                }
                Button {
                    guard !editMode else { return }
                    expansion.wrappedValue.toggle()
                } label: {
                    HStack {
                        Image(systemName: icon).foregroundStyle(tint).frame(width: 28, height: 28).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)

                        Spacer(minLength: 8)
                        if !editMode && !isExpanded {
                            Text(summary(for: title)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        if !editMode { Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(.isButton)
                if editMode {
                    Button { model.setVisibleSection(title, visible: isHidden) } label: {
                        Image(systemName: isHidden ? "eye.slash" : "eye").foregroundStyle(isHidden ? .secondary : .primary)
                    }.buttonStyle(.plain).help(isHidden ? Text("Show card") : Text("Hide card"))
                        .accessibilityLabel(isHidden ? "Show \(title)" : "Hide \(title)")
                }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
            if !editMode && isExpanded {
                Divider().padding(.horizontal, 10)
                content.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isHidden ? 0.48 : 1)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 0.5))
    }
    private var tint: Color {
        switch title { case "CPU", "Processes": .blue; case "GPU", "Network": .teal; case "Memory", "Disk": .purple; case "Battery": .green; case "Power", "Thermal", "Fans": .orange; default: .secondary }
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
        case "Thermal": return OverlayL10n.text(thermalName, locale: model.locale)
        case "Processes": return DisplayValue.number(model.snapshot.cpu.processCount)
        case "System": return model.snapshot.system.chip ?? "Apple Silicon"
        case "Sleep blockers": return String(model.snapshot.sleepBlockers.count)
        case "Bluetooth": return String(model.snapshot.bluetooth.count)
        case "Fans": return String(model.snapshot.fans.count)
        default: return "n/a"
        }
    }

    private var previewCaption: String {
        switch title {
        case "CPU", "GPU": "Utilization"
        case "Memory": "Used"
        case "Battery": batteryStatus
        case "Power": "Combined"
        case "Disk": "Read"
        case "Network": "Transfer"
        case "Thermal": "Thermal state"
        case "Processes": "Processes"
        case "Sleep blockers": "Active"
        default: ""
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
            TelemetryChart(lines: [TelemetryChartLine(name: "batteryPowerHistory", points: model.batteryPowerHistory, color: .orange)], percent: false, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 32)
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
            TelemetryChart(lines: [TelemetryChartLine(name: "powerHistory", points: model.powerHistory, color: .yellow)], percent: false, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 34)
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
            TelemetryChart(lines: [TelemetryChartLine(name: "gpuHistory", points: model.gpuHistory, color: .accentColor)], percent: true, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 34)
        }
    }
    private var cpu: some View {
        VStack(spacing: 6) {
            HStack { Text("Total").foregroundStyle(.secondary); Spacer(); Text(DisplayValue.decimal(model.snapshot.cpu.load.map { $0 * 100 }, suffix: "%")).font(.system(size: 27, weight: .semibold)).monospacedDigit() }
            rows([("User", DisplayValue.decimal(model.snapshot.cpu.user, digits: 0, suffix: "%")), ("System", DisplayValue.decimal(model.snapshot.cpu.system, digits: 0, suffix: "%")), ("Idle", DisplayValue.decimal(model.snapshot.cpu.idle, digits: 0, suffix: "%")), ("Load average 1 / 5 / 15", model.snapshot.cpu.loadAverage.map { DisplayValue.decimal($0, digits: 2) }.joined(separator: " / ").isEmpty ? "n/a" : model.snapshot.cpu.loadAverage.map { DisplayValue.decimal($0, digits: 2) }.joined(separator: " / ")), ("Processes", DisplayValue.number(model.snapshot.cpu.processCount))])
            HStack(spacing: 8) { clusterBar("E", value: model.snapshot.cpu.eAverage, tint: .teal); clusterBar("P", value: model.snapshot.cpu.pAverage, tint: .orange) }
            TelemetryChart(lines: [TelemetryChartLine(name: "cpuHistory", points: model.cpuHistory, color: .accentColor)], percent: true, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 36)
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
            TelemetryChart(lines: [TelemetryChartLine(name: "memoryHistory", points: model.memoryHistory, color: .blue)], percent: true, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 34)
        }
    }
    private var disk: some View {
        VStack(spacing: 7) {
            usageCapsule(model.snapshot.disk.total.flatMap { total in model.snapshot.disk.free.map { Double(total - $0) / Double(total) * 100 } }, tint: .purple)
            rows([("Volume", model.snapshot.disk.volumeName ?? "n/a"), ("File system", model.snapshot.disk.fileSystem ?? "n/a"), ("Available incl. purgeable", model.formatBytes(model.snapshot.disk.importantFree)), ("Boot volume used", model.snapshot.disk.total.flatMap { total in model.snapshot.disk.free.map { model.formatBytes(total - $0) } } ?? "n/a"), ("Available", model.formatBytes(model.snapshot.disk.free)), ("Total", model.formatBytes(model.snapshot.disk.total)), ("SMART status", model.snapshot.disk.smartStatus ?? "n/a"), ("Read", rate(model.snapshot.diskIO.readBytesPerSecond)), ("Write", rate(model.snapshot.diskIO.writeBytesPerSecond)), ("Read IOPS", DisplayValue.decimal(model.snapshot.diskIO.readIOPS, digits: 0)), ("Write IOPS", DisplayValue.decimal(model.snapshot.diskIO.writeIOPS, digits: 0))])
            ForEach(model.snapshot.disk.externalVolumes) { volume in rows([(volume.name, "\(model.formatBytes(volume.free)) / \(model.formatBytes(volume.total))")]) }
            TelemetryChart(lines: [TelemetryChartLine(name: "Read", points: model.diskReadHistory, color: .blue), TelemetryChartLine(name: "Write", points: model.diskWriteHistory, color: .orange)], legend: true, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 48)
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
            rows([("Down", rate(model.snapshot.network.downBytesPerSecond)), ("Up", rate(model.snapshot.network.upBytesPerSecond)), ("Wi-Fi RSSI", model.snapshot.network.rssi.map { "\($0) dBm" } ?? "n/a"), ("Channel", model.snapshot.network.channel ?? "n/a"), ("Link rate", DisplayValue.decimal(model.snapshot.network.linkMbps, digits: 0, suffix: " Mbps")), ("Latency", model.snapshot.network.latencyMs.map { DisplayValue.decimal($0, digits: 0, suffix: " ms") } ?? "n/a")])
            TelemetryChart(lines: [TelemetryChartLine(name: "Down", points: model.networkDownHistory, color: .blue), TelemetryChartLine(name: "Up", points: model.networkUpHistory, color: .orange)], window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 34)
        }
    }
    private var thermal: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Circle().fill(thermalColor).frame(width: 9, height: 9); Text(LocalizedStringKey(thermalName)).foregroundStyle(.primary); Spacer() }
            if !model.snapshot.temperatures.sensors.isEmpty {
                let groups = ["CPU/SoC", "Battery", "SSD", "Other"]
                ForEach(groups, id: \.self) { group in
                    let values = model.snapshot.temperatures.sensors.filter { $0.group == group }.map(\.celsius)
                    if !values.isEmpty { rows([(group, "avg \(temperature(values.reduce(0, +) / Double(values.count))) · max \(temperature(values.max()))")]) }
                }
                TelemetryChart(lines: [TelemetryChartLine(name: "temperatureHistory", points: model.temperatureHistory, color: .red)], percent: false, window: model.historyMinutes * 60 + 1, interval: model.refreshSeconds).frame(height: 30)
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
        rows([("Model name", model.snapshot.system.chip ?? "n/a"), ("Model identifier", model.snapshot.system.model ?? "n/a"), ("Chip", model.snapshot.system.chip ?? "n/a"), ("E cores", DisplayValue.number(model.snapshot.system.eCores)), ("P cores", DisplayValue.number(model.snapshot.system.pCores)), ("GPU cores", DisplayValue.number(model.snapshot.system.gpuCores)), ("RAM", model.snapshot.system.memoryGB.map { model.formatBytes(UInt64($0 * 1_000_000_000)) } ?? "n/a"), ("macOS", model.snapshot.system.macOS), ("Build", model.snapshot.system.build ?? "n/a"), ("Uptime", DisplayValue.duration(model.snapshot.system.uptime)), ("Boot time", model.snapshot.system.bootTime?.formatted(date: .abbreviated, time: .shortened) ?? "n/a")])
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
