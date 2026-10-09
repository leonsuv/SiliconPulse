import SwiftUI
import Charts

/// Animate only chart geometry when a sample arrives. No display timer or extra sampling.
private struct SmoothTelemetryChart: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let latest: Int
    let window: Int
    let duration: Double

    func body(content: Content) -> some View {
        // A fixed span prevents every new point from stretching the entire history.
        let end = Double(max(window - 1, latest))
        content
            .chartXScale(domain: (end - Double(max(1, window - 1)))...end)
            .animation(reduceMotion ? nil : .linear(duration: duration), value: latest)
    }
}

extension View {
    func smoothTelemetryChart(latest: Int, window: Int = 60, duration: Double = 0.85) -> some View {
        modifier(SmoothTelemetryChart(latest: latest, window: max(2, window), duration: duration))
    }
}
