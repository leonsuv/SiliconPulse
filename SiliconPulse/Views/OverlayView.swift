import SwiftUI
import AppKit

struct OverlayView: View {
    let model: AppModel
    let controller: OverlayController
    @Environment(\.locale) private var locale
    private var prefs: OverlayPreferences { controller.preferences }
    private var accent: Color {
        switch prefs.accent { case "Blue": .blue; case "Green": .green; case "Orange": .orange; case "Purple": .purple; default: .accentColor }
    }
    var body: some View {
        let _ = model.overlayTick
        VStack(alignment: .leading, spacing: 0) {
            if prefs.hint && Date.now.timeIntervalSince(controller.enteredAt) < 4 {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                    Text(OverlayL10n.text("Overlay on: press %@ to exit", locale: locale).replacingOccurrences(of: "%@", with: prefs.hotKey))
                }
                .font(.system(size: 11 * prefs.scale, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .padding(.bottom, 3 * prefs.scale)
            }
            if prefs.layout == "Bar" {
                barContent
            } else {
                ForEach(prefs.metrics, id: \.self) { metric in listRow(metric) }
            }
            if prefs.isMoveMode {
                HStack { Text(OverlayL10n.text("Drag to position", locale: locale)); Spacer(); Button(OverlayL10n.text("Done", locale: locale)) { controller.endMoveMode() }.buttonStyle(.plain) }
                    .font(.system(size: 11 * prefs.scale, weight: .medium, design: .rounded)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10 * prefs.scale)
        .padding(.vertical, 8 * prefs.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: prefs.cornerRadius))
        .shadow(color: prefs.background == "None" ? .clear : .black.opacity(0.22), radius: 18, y: 6)
        .opacity(controller.idleDimmed ? 0.15 : prefs.textOpacity)
        .animation(.easeInOut(duration: 0.7), value: controller.idleDimmed)
        .animation(.easeInOut(duration: 0.2), value: prefs.textOpacity)
        .onChange(of: model.overlayTick) { _, _ in
            if (model.snapshot.cpu.load ?? 0) * 100 >= 10 || (model.snapshot.gpu.utilization ?? 0) >= 10 { controller.noteActivity() }
        }
        .onAppear { controller.noteActivity() }
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(3)); controller.updateIdleState() } }
        .onKeyPress(.escape) { if prefs.isMoveMode { controller.endMoveMode(); return .handled }; return .ignored }
        .onKeyPress(.return) { if prefs.isMoveMode { controller.endMoveMode(); return .handled }; return .ignored }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OverlayL10n.text("SiliconPulse system telemetry overlay", locale: locale))
    }

    private var barContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(prefs.metrics.enumerated()), id: \.element) { index, metric in
                HStack(spacing: 6) {
                    Image(systemName: symbol(metric)).frame(width: 18).foregroundStyle(metricColor(metric))
                    valueView(metric, size: 12)
                        .frame(width: 76, alignment: .trailing)
                }
                .frame(width: 104, height: 24)
                if index < prefs.metrics.count - 1 {
                    Rectangle().fill(.white.opacity(0.26)).frame(width: 1, height: 18).padding(.horizontal, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel(prefs.metrics.map { "\(localizedLabel($0)): \(metricValue($0))" }.joined(separator: ", "))
    }

    private func listRow(_ metric: String) -> some View {
        let color = metricColor(metric)
        return HStack(spacing: 5) {
            Image(systemName: symbol(metric))
                .resizable().scaledToFit().frame(width: 14 * prefs.scale, height: 14 * prefs.scale)
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .frame(width: 20 * prefs.scale, height: 20 * prefs.scale)
            if prefs.showLabels && !prefs.compact {
                Text(localizedLabel(metric))
                    .font(.system(size: 12 * prefs.scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            if prefs.showSparklines {
                OverlaySparkline(points: history(for: metric) ?? [], color: color)
                    .frame(width: 56 * prefs.scale, height: 16 * prefs.scale)
            } else {
                Color.clear.frame(width: 56 * prefs.scale, height: 16 * prefs.scale)
            }
            valueView(metric, size: metric == "CPU %" || metric == "GPU %" ? 13 : 12)
                .frame(width: 82 * prefs.scale, alignment: .trailing)
        }
        .frame(height: 22 * prefs.scale)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(localizedLabel(metric)), \(metricValue(metric))")
    }

    @ViewBuilder private var background: some View {
        if prefs.background == "None" {
            Color.clear
        } else if prefs.background == "Subtle dark pill" {
            RoundedRectangle(cornerRadius: prefs.cornerRadius).fill(Color.black.opacity(prefs.opacity))
        } else if prefs.background == "Dark pill" || prefs.background == "Dark" {
            RoundedRectangle(cornerRadius: prefs.cornerRadius).fill(Color.black.opacity(prefs.opacity))
        } else {
            RoundedRectangle(cornerRadius: prefs.cornerRadius).fill(.ultraThinMaterial).overlay(Color.black.opacity(prefs.opacity * 0.22))
        }
    }

    @ViewBuilder private func valueView(_ metric: String, size: CGFloat) -> some View {
        if metric == "Battery W", let watts = model.snapshot.battery.watts {
            HStack(spacing: 2) {
                Text(watts >= 0 ? "+" : "−").font(.system(size: max(9, size - 2) * prefs.scale, weight: .medium, design: .rounded))
                Text(power(abs(watts))).font(.system(size: size * prefs.scale, weight: .semibold, design: .rounded))
            }.monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75).shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        } else {
            Text(metricValue(metric))
                .font(.system(size: size * prefs.scale, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(metricColor(metric)).lineLimit(1).minimumScaleFactor(0.72)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
    }

    private func localizedLabel(_ metric: String) -> String {
        let key: String
        switch metric {
        case "Battery %": key = "Battery"
        case "Battery W": key = "Battery power"
        case "CPU temp": key = "CPU temperature"
        default: key = metric
        }
        return OverlayL10n.text(key, locale: locale)
    }
    private func metricValue(_ metric: String) -> String {
        let s = model.snapshot
        switch metric {
        case "CPU %": return s.cpu.load.map { number($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        case "GPU %": return s.gpu.utilization.map { number($0, digits: 0, suffix: "%") } ?? "n/a"
        case "RAM %": return s.memory.usedPercent.map { number($0, digits: 0, suffix: "%") } ?? "n/a"
        case "CPU power W": return power(s.power.cpu)
        case "GPU power W": return power(s.power.gpu)
        case "Total power W": return power(s.power.combined)
        case "Battery %": return s.battery.percent.map { number($0 * 100, digits: 0, suffix: "%") } ?? "n/a"
        case "Battery W": return s.battery.watts.map { power(abs($0)) } ?? "n/a"
        case "Time remaining": return s.battery.timeRemainingMinutes.map { DisplayValue.duration(Double($0 * 60)) } ?? "n/a"
        case "CPU temp": return temperature(s.temperatures.cpuAverage)
        case "Hottest temp": return temperature(s.temperatures.cpuMaximum)
        case "Network down": return model.formatRate(s.network.downBytesPerSecond)
        case "Network up": return model.formatRate(s.network.upBytesPerSecond)
        case "Disk read": return model.formatRate(s.diskIO.readBytesPerSecond)
        case "Disk write": return model.formatRate(s.diskIO.writeBytesPerSecond)
        case "Thermal state": return ["Nominal", "Fair", "Serious", "Critical"].indices.contains(s.cpu.thermalState) ? OverlayL10n.text(["Nominal", "Fair", "Serious", "Critical"][s.cpu.thermalState], locale: locale) : "n/a"
        case "Top process": return s.processes.first.map { "\($0.name) · \(Int($0.cpuPercent))%" } ?? "n/a"
        case "Clock time": return Date.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        default: return "n/a"
        }
    }
    private func number(_ value: Double?, digits: Int, suffix: String) -> String {
        guard let value, value.isFinite else { return "n/a" }
        return value.formatted(.number.locale(locale).precision(.fractionLength(digits))) + suffix
    }
    private func power(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "n/a" }
        return abs(watts) < 1 ? number(watts * 1000, digits: 0, suffix: " mW") : number(watts, digits: 1, suffix: " W")
    }
    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "n/a" }
        return number(model.fahrenheit ? celsius * 9 / 5 + 32 : celsius, digits: 0, suffix: model.fahrenheit ? "°F" : "°C")
    }
    private func metricColor(_ metric: String) -> Color {
        guard prefs.colorsEnabled else { return .white }
        switch metric {
        case "CPU %":
            let n = (model.snapshot.cpu.load ?? 0) * 100
            return n >= 100 ? .red : n >= prefs.cpuWarning ? .orange : n >= 60 ? .yellow : .green
        case "GPU %":
            let n = model.snapshot.gpu.utilization ?? 0
            return n >= 100 ? .red : n >= prefs.gpuWarning ? .orange : n >= 60 ? .yellow : .green
        case "RAM %":
            let n = model.snapshot.memory.usedPercent ?? 0
            return n >= 100 ? .red : n >= prefs.ramWarning ? .orange : n >= 60 ? .yellow : .green
        case "CPU temp", "Hottest temp":
            let n = metric == "CPU temp" ? model.snapshot.temperatures.cpuAverage : model.snapshot.temperatures.cpuMaximum
            guard let n else { return .white }
            return n >= 95 ? .red : n >= 85 ? .orange : n >= prefs.temperatureWarning ? .yellow : .green
        case "Battery %":
            guard model.snapshot.battery.percent != nil else { return .white }
            if model.snapshot.battery.charging == true { return .green }
            let n = (model.snapshot.battery.percent ?? 0) * 100
            return n < prefs.batteryRed ? .red : n < prefs.batteryOrange ? .orange : .green
        default: return .white
        }
    }
    private func history(for metric: String) -> [TelemetryPoint]? {
        switch metric { case "CPU %": model.cpuHistory; case "GPU %": model.gpuHistory; case "RAM %": model.memoryHistory; case "Battery W": model.batteryPowerHistory; default: nil }
    }
    private func symbol(_ metric: String) -> String {
        switch metric {
        case "CPU %", "CPU power W", "CPU temp", "Hottest temp": "cpu"
        case "GPU %", "GPU power W": "display"
        case "RAM %": "memorychip"
        case "Battery %", "Battery W", "Time remaining": "battery.100percent"
        case "Network down": "arrow.down"
        case "Network up": "arrow.up"
        case "Disk read": "arrow.down.to.line"
        case "Disk write": "arrow.up.to.line"
        case "Clock time": "clock"
        default: "bolt.fill"
        }
    }
}

private struct OverlaySparkline: View {
    let points: [TelemetryPoint]
    let color: Color
    var body: some View {
        Canvas { context, size in
            let values = points.suffix(30).compactMap(\.value)
            guard values.count > 1 else { return }
            let low = values.min() ?? 0
            let high = values.max() ?? low
            let span = max(0.0001, high - low)
            var path = Path()
            for index in values.indices {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height - (CGFloat(values[index] - low) / CGFloat(span)) * (size.height - 2) - 1
                let point = CGPoint(x: x, y: y)
                if index == values.startIndex { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

enum OverlayL10n {
    static func text(_ key: String, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"), let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return key
    }
}
