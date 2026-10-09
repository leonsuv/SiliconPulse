import SwiftUI
import AppKit
import QuartzCore

struct TelemetryChartLine {
    let name: String
    let points: [TelemetryPoint]
    let color: Color
}

/// Geometry is built once per sample. Core Animation scrolls the cached paths;
/// SwiftUI does not rebuild hundreds of marks on every animation frame.
struct TelemetryChart: View {
    let lines: [TelemetryChartLine]
    var percent = false
    var axes = false
    var legend = false
    var window = 60
    var interval: Double = 1
    var fill = true
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TelemetryPlot(lines: lines, percent: percent, axes: axes, window: window,
                          interval: interval, fill: fill, animated: animated && !reduceMotion,
                          dark: colorScheme == .dark)
            if legend && lines.count > 1 {
                HStack(spacing: 14) {
                    ForEach(lines.indices, id: \.self) { index in
                        HStack(spacing: 5) {
                            Capsule().fill(lines[index].color).frame(width: 12, height: 3)
                            Text(LocalizedStringKey(lines[index].name)).foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lines.map(\.name).joined(separator: ", ")))
        .accessibilityValue(Text(lines.map { "\($0.name): \($0.points.last?.value.map { String(format: "%.1f", $0) } ?? "n/a")" }.joined(separator: ", ")))
    }
}

private struct TelemetryPlot: NSViewRepresentable {
    let lines: [TelemetryChartLine]
    let percent: Bool
    let axes: Bool
    let window: Int
    let interval: Double
    let fill: Bool
    let animated: Bool
    let dark: Bool

    func makeNSView(context: Context) -> TelemetryPlotView { TelemetryPlotView() }
    func updateNSView(_ view: TelemetryPlotView, context: Context) {
        view.update(lines: lines, percent: percent, axes: axes, window: window,
                    interval: interval, fill: fill, animated: animated, dark: dark)
    }
}

private final class TelemetryPlotView: NSView {
    private let clip = CALayer()
    private let grid = CAShapeLayer()
    private var strokes: [CAShapeLayer] = []
    private var fills: [CAShapeLayer] = []
    private var labels: [CATextLayer] = []
    private var data: [TelemetryChartLine] = []
    private var percent = false, axes = false, filled = true, animated = true, dark = true
    private var span = 60, interval = 1.0
    private var latest: Int?
    private var lastArrival = CACurrentMediaTime()
    private var lastSize = CGSize.zero
    private var upper = 1.0, lower = 0.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(grid)
        clip.masksToBounds = true
        layer?.addSublayer(clip)
        grid.fillColor = nil
        grid.lineWidth = 0.5
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; render(scroll: false, duration: interval) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { (strokes + fills).forEach { $0.removeAllAnimations() } }
    }

    func update(lines: [TelemetryChartLine], percent: Bool, axes: Bool, window: Int,
                interval: Double, fill: Bool, animated: Bool, dark: Bool) {
        let trimmed = lines.map { TelemetryChartLine(name: $0.name, points: Array($0.points.suffix(max(3, window + 3))), color: $0.color) }
        let changed = trimmed.count != data.count || zip(trimmed, data).contains {
            $0.name != $1.name || $0.color != $1.color || $0.points != $1.points
        }
        let optionsChanged = self.percent != percent || self.axes != axes || span != window || self.dark != dark || filled != fill || self.animated != animated
        guard changed || optionsChanged else { return }
        let newLatest = trimmed.compactMap { $0.points.last?.id }.max()
        let now = CACurrentMediaTime()
        let scroll = animated && !optionsChanged && latest != nil && newLatest == latest! + 1 && now - lastArrival < max(10, interval * 3)
        let duration = min(max(0.2, now - lastArrival), max(1, interval * 1.5))
        if newLatest != latest { lastArrival = now }
        data = trimmed; self.percent = percent; self.axes = axes; span = max(3, window)
        self.interval = interval; filled = fill; self.animated = animated; self.dark = dark; latest = newLatest
        render(scroll: scroll, duration: duration)
    }

    private func render(scroll: Bool, duration: Double) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let scale = window?.backingScaleFactor ?? 2
        let plot = CGRect(x: 0, y: axes ? 19 : 2,
                          width: max(1, bounds.width - (axes ? 42 : 0)),
                          height: max(1, bounds.height - (axes ? 25 : 4)))
        clip.frame = plot
        let values = data.flatMap { $0.points.compactMap(\.value).filter(\.isFinite) }
        if percent { lower = 0; upper = 100 }
        else {
            let minimum = min(0, values.min() ?? 0)
            let maximum = max(0, values.max() ?? 0)
            func nice(_ value: Double) -> Double {
                guard value > 0 else { return 1 }
                let order = pow(10.0, floor(log10(value)))
                return ceil(value / order * 2) / 2 * order
            }
            let desiredTop = nice(maximum * 1.15)
            let desiredBottom = minimum < 0 ? -nice(-minimum * 1.15) : 0
            // Keep a quiet scale while data fluctuates. Shrink only after a substantial drop.
            if !scroll || desiredTop > upper || desiredTop < upper * 0.45 { upper = desiredTop }
            if !scroll || desiredBottom < lower || desiredBottom > lower * 0.45 { lower = desiredBottom }
        }
        let range = max(0.0001, upper - lower)
        let gridPath = CGMutablePath()
        if axes {
            for index in 0...4 {
                let y = plot.minY + plot.height * CGFloat(index) / 4
                gridPath.move(to: CGPoint(x: plot.minX, y: y)); gridPath.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            for index in 0...6 {
                let x = plot.width * CGFloat(index) / 6
                gridPath.move(to: CGPoint(x: x, y: plot.minY)); gridPath.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
        }
        grid.path = gridPath
        grid.strokeColor = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.075).cgColor
        labels.forEach { $0.removeFromSuperlayer() }; labels.removeAll(keepingCapacity: true)
        func label(_ text: String, rect: CGRect, alignment: CATextLayerAlignmentMode) {
            let l = CATextLayer(); l.string = text; l.fontSize = 9; l.contentsScale = scale
            l.foregroundColor = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.48).cgColor
            l.alignmentMode = alignment; l.frame = rect; layer?.addSublayer(l); labels.append(l)
        }
        if axes {
            for index in 0...2 {
                let value = lower + range * Double(index) / 2
                let text = percent ? String(format: "%.0f%%", value) : ByteCountOrNumber(value)
                label(text, rect: CGRect(x: plot.maxX + 6, y: plot.minY + plot.height * CGFloat(index) / 2 - 5, width: 36, height: 12), alignment: .left)
            }
            let seconds = Double(span - 1) * interval
            label(String(format: "−%.0f s", seconds), rect: CGRect(x: 0, y: 0, width: 55, height: 12), alignment: .left)
            label(String(format: "−%.0f s", seconds / 2), rect: CGRect(x: plot.midX - 28, y: 0, width: 56, height: 12), alignment: .center)
            label("0 s", rect: CGRect(x: plot.maxX - 35, y: 0, width: 35, height: 12), alignment: .right)
        }
        while strokes.count < data.count {
            let area = CAShapeLayer(), stroke = CAShapeLayer()
            stroke.fillColor = nil; stroke.lineWidth = axes ? 1.8 : 1.5
            stroke.lineCap = .round; stroke.lineJoin = .round
            clip.addSublayer(area); clip.addSublayer(stroke)
            fills.append(area); strokes.append(stroke)
        }
        while strokes.count > data.count { strokes.removeLast().removeFromSuperlayer(); fills.removeLast().removeFromSuperlayer() }
        let step = plot.width / CGFloat(span - 1)
        let end = (latest ?? 0) - (scroll ? 1 : 0)
        for index in data.indices {
            let path = CGMutablePath(), area = CGMutablePath()
            var run: [CGPoint] = []
            var previous: Int?
            func flush() {
                guard !run.isEmpty else { return }
                let line = curve(run); path.addPath(line)
                let region = line.mutableCopy()!
                region.addLine(to: CGPoint(x: run.last!.x, y: 0)); region.addLine(to: CGPoint(x: run.first!.x, y: 0)); region.closeSubpath(); area.addPath(region)
                run.removeAll(keepingCapacity: true)
            }
            for point in data[index].points {
                guard let value = point.value, value.isFinite else { flush(); previous = nil; continue }
                if let previous, point.id != previous + 1 { flush() }
                let x = CGFloat(point.id - end + span - 1) * step
                let y = CGFloat(min(1, max(0, (value - lower) / range))) * plot.height
                run.append(CGPoint(x: x, y: y)); previous = point.id
            }
            flush()
            let color = NSColor(data[index].color).cgColor
            strokes[index].path = path; strokes[index].strokeColor = color
            fills[index].path = filled ? area : nil; fills[index].fillColor = color.copy(alpha: dark ? 0.10 : 0.07)
            for l in [strokes[index], fills[index]] {
                l.removeAllAnimations(); l.transform = CATransform3DMakeTranslation(scroll ? -step : 0, 0, 0)
                if scroll && self.window != nil && !isHiddenOrHasHiddenAncestor {
                    let movement = CABasicAnimation(keyPath: "transform.translation.x")
                    movement.fromValue = 0; movement.toValue = -step; movement.duration = duration
                    movement.timingFunction = CAMediaTimingFunction(name: .linear)
                    l.add(movement, forKey: "telemetryScroll")
                }
            }
        }
    }

    /// Shape-preserving cubic Hermite interpolation. Every measured point remains
    /// on the curve; local extrema are not exaggerated and missing samples split it.
    private func curve(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        let slopes = zip(points, points.dropFirst()).map { ($1.y - $0.y) / max(0.0001, $1.x - $0.x) }
        var tangents = [CGFloat](repeating: 0, count: points.count)
        tangents[0] = slopes[0]; tangents[points.count - 1] = slopes.last!
        if points.count > 2 {
            for i in 1..<(points.count - 1) {
                let a = slopes[i - 1], b = slopes[i]
                tangents[i] = a * b > 0 ? 2 * a * b / (a + b) : 0
            }
        }
        for i in 0..<slopes.count {
            let a = points[i], b = points[i + 1], dx = (b.x - a.x) / 3
            path.addCurve(to: b, control1: CGPoint(x: a.x + dx, y: a.y + tangents[i] * dx), control2: CGPoint(x: b.x - dx, y: b.y - tangents[i + 1] * dx))
        }
        return path
    }
    private func ByteCountOrNumber(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if abs(value) >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: abs(value) < 10 && value != 0 ? "%.1f" : "%.0f", value)
    }
}
