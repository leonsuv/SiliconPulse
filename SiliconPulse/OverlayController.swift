import AppKit
import SwiftUI
import Observation

@MainActor @Observable final class OverlayPreferences {
    static let shared = OverlayPreferences()
    static let allMetrics = ["CPU %", "GPU %", "RAM %", "CPU power W", "GPU power W", "Total power W", "Battery %", "Battery W", "Time remaining", "CPU temp", "Hottest temp", "Network down", "Network up", "Disk read", "Disk write", "Thermal state", "Top process", "Clock time"]
    var metrics = UserDefaults.standard.stringArray(forKey: "overlay.metrics") ?? ["CPU %", "GPU %", "RAM %", "Battery %", "Battery W", "CPU temp"] { didSet { UserDefaults.standard.set(metrics, forKey: "overlay.metrics") } }
    var draggedMetric: String?
    var layout = UserDefaults.standard.string(forKey: "overlay.layout") ?? "List" { didSet { UserDefaults.standard.set(layout, forKey: "overlay.layout") } }
    var refresh = UserDefaults.standard.double(forKey: "overlay.refresh") == 0 ? 2.0 : UserDefaults.standard.double(forKey: "overlay.refresh") { didSet { UserDefaults.standard.set(refresh, forKey: "overlay.refresh") } }
    var opacity = UserDefaults.standard.object(forKey: "overlay.opacity") as? Double ?? 0.92 { didSet { UserDefaults.standard.set(opacity, forKey: "overlay.opacity") } }
    var scale = UserDefaults.standard.object(forKey: "overlay.scale") as? Double ?? 1.0 { didSet { UserDefaults.standard.set(scale, forKey: "overlay.scale") } }
    var background = UserDefaults.standard.string(forKey: "overlay.background") ?? "Subtle dark pill" { didSet { UserDefaults.standard.set(background, forKey: "overlay.background") } }
    var textOpacity = UserDefaults.standard.object(forKey: "overlay.textOpacity") as? Double ?? 1 { didSet { UserDefaults.standard.set(textOpacity, forKey: "overlay.textOpacity") } }
    var cornerRadius = UserDefaults.standard.object(forKey: "overlay.cornerRadius") as? Double ?? 10 { didSet { UserDefaults.standard.set(cornerRadius, forKey: "overlay.cornerRadius") } }
    var colorsEnabled = UserDefaults.standard.object(forKey: "overlay.colorsEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(colorsEnabled, forKey: "overlay.colorsEnabled") } }
    var temperatureWarning = UserDefaults.standard.object(forKey: "overlay.temperatureWarning") as? Double ?? 70 { didSet { UserDefaults.standard.set(temperatureWarning, forKey: "overlay.temperatureWarning") } }
    var ramWarning = UserDefaults.standard.object(forKey: "overlay.ramWarning") as? Double ?? 85 { didSet { UserDefaults.standard.set(ramWarning, forKey: "overlay.ramWarning") } }
    var batteryRed = UserDefaults.standard.object(forKey: "overlay.batteryRed") as? Double ?? 20 { didSet { UserDefaults.standard.set(batteryRed, forKey: "overlay.batteryRed") } }
    var batteryOrange = UserDefaults.standard.object(forKey: "overlay.batteryOrange") as? Double ?? 35 { didSet { UserDefaults.standard.set(batteryOrange, forKey: "overlay.batteryOrange") } }
    var accent = UserDefaults.standard.string(forKey: "overlay.accent") ?? "System" { didSet { UserDefaults.standard.set(accent, forKey: "overlay.accent") } }
    var showLabels = UserDefaults.standard.object(forKey: "overlay.labels") as? Bool ?? true { didSet { UserDefaults.standard.set(showLabels, forKey: "overlay.labels") } }
    var showSparklines = UserDefaults.standard.object(forKey: "overlay.sparklines") as? Bool ?? false { didSet { UserDefaults.standard.set(showSparklines, forKey: "overlay.sparklines") } }
    var compact = UserDefaults.standard.object(forKey: "overlay.compact") as? Bool ?? false { didSet { UserDefaults.standard.set(compact, forKey: "overlay.compact") } }
    var cpuWarning = UserDefaults.standard.object(forKey: "overlay.cpuWarning") as? Double ?? 85 { didSet { UserDefaults.standard.set(cpuWarning, forKey: "overlay.cpuWarning") } }
    var gpuWarning = UserDefaults.standard.object(forKey: "overlay.gpuWarning") as? Double ?? 85 { didSet { UserDefaults.standard.set(gpuWarning, forKey: "overlay.gpuWarning") } }
    var followActiveDisplay = UserDefaults.standard.object(forKey: "overlay.followDisplay") as? Bool ?? false { didSet { UserDefaults.standard.set(followActiveDisplay, forKey: "overlay.followDisplay") } }
    var displayName = UserDefaults.standard.string(forKey: "overlay.displayName") ?? "Main" { didSet { UserDefaults.standard.set(displayName, forKey: "overlay.displayName") } }
    var anchor = UserDefaults.standard.string(forKey: "overlay.anchor") ?? "Top left" { didSet { UserDefaults.standard.set(anchor, forKey: "overlay.anchor") } }
    var offsetX = UserDefaults.standard.double(forKey: "overlay.offsetX") { didSet { UserDefaults.standard.set(offsetX, forKey: "overlay.offsetX") } }
    var offsetY = UserDefaults.standard.double(forKey: "overlay.offsetY") { didSet { UserDefaults.standard.set(offsetY, forKey: "overlay.offsetY") } }
    var autoHide = UserDefaults.standard.object(forKey: "overlay.autoHide") as? Bool ?? false { didSet { UserDefaults.standard.set(autoHide, forKey: "overlay.autoHide") } }
    var screenshotMode = UserDefaults.standard.object(forKey: "overlay.screenshotMode") as? Bool ?? false { didSet { UserDefaults.standard.set(screenshotMode, forKey: "overlay.screenshotMode") } }
    var hint = UserDefaults.standard.object(forKey: "overlay.hint") as? Bool ?? true { didSet { UserDefaults.standard.set(hint, forKey: "overlay.hint") } }
    var hotKey = UserDefaults.standard.string(forKey: "overlay.hotKey") ?? "⌃⌥O" { didSet { UserDefaults.standard.set(hotKey, forKey: "overlay.hotKey") } }
    var isMoveMode = false
}

@MainActor final class OverlayPanel: NSPanel, NSWindowDelegate {
    var moveMode: () -> Bool = { false }
    weak var overlayController: OverlayController?
    override var canBecomeKey: Bool { moveMode() }
    override var canBecomeMain: Bool { false }
    override func mouseDragged(with event: NSEvent) { super.mouseDragged(with: event); overlayController?.resetMoveTimeout() }
    func windowDidMove(_ notification: Notification) { overlayController?.resetMoveTimeout() }
    override func keyDown(with event: NSEvent) {
        if overlayController?.moveFinishedByKey(event.keyCode) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor @Observable final class OverlayController {
    static weak var active: OverlayController?
    let preferences = OverlayPreferences.shared
    let model: AppModel
    let panelController: PanelController
    let panel: OverlayPanel
    private(set) var isActive = UserDefaults.standard.bool(forKey: "overlay.active") {
        didSet { UserDefaults.standard.set(isActive, forKey: "overlay.active") }
    }
    private var hotKey: OverlayHotKey?
    private var previousPanelVisible = false
    private var previousPinned = false
    private var previousFrame = NSRect.zero
    private var moveTimeout: Task<Void, Never>?
    private var previewTimeout: Task<Void, Never>?
    var lastActivity = Date()
    var enteredAt = Date()
    var idleDimmed = false

    init(model: AppModel, panelController: PanelController) {
        self.model = model
        self.panelController = panelController
        let initial = NSRect(x: 0, y: 0, width: 320, height: 200)
        panel = OverlayPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.active = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.delegate = panel
        panel.moveMode = { [weak preferences] in preferences?.isMoveMode ?? false }
        panel.overlayController = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.sharingType = preferences.screenshotMode ? .none : .readOnly
        if let capture = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--release-screenshot-overlay=") }) {
            let variant = String(capture.split(separator: "=", maxSplits: 1).last ?? "list-bright")
            preferences.layout = variant.contains("bar") ? "Bar" : "List"
            preferences.metrics = ["CPU %", "GPU %", "RAM %", "Battery %"]
            preferences.showLabels = true
            preferences.showSparklines = true
            preferences.compact = false
            preferences.hint = false
            preferences.background = "Subtle dark pill"
            preferences.opacity = 0.92
            preferences.textOpacity = 1
            preferences.scale = 1
            let backdrop: Color = variant.contains("bright") ? .white : .black
            let width: CGFloat = preferences.layout == "Bar" ? 112 * CGFloat(preferences.metrics.count) + 24 : 360
            let rowHeight: CGFloat = preferences.layout == "Bar" ? 24 : 22 * CGFloat(preferences.metrics.count)
            let margin: CGFloat = 36
            let content = OverlayView(model: model, controller: self)
                .environment(\.locale, model.locale)
                .frame(width: width, height: rowHeight)
                .padding(margin)
            let root = ZStack {
                backdrop.ignoresSafeArea()
                content
            }.frame(width: width + margin * 2, height: rowHeight + 16 + margin * 2)
            panel.contentView = NSHostingView(rootView: root)
        } else {
            panel.contentView = NSHostingView(rootView: OverlayView(model: model, controller: self).environment(\.locale, model.locale))
        }
        placePanel()
        hotKey = OverlayHotKey(key: preferences.hotKey) { [weak self] in self?.toggle() }
    }

    func toggle() { isActive ? deactivate() : activate() }
    func restoreOnLaunch() {
        guard isActive else { return }
        previousPanelVisible = UserDefaults.standard.bool(forKey: "overlay.previousVisible")
        previousPinned = UserDefaults.standard.bool(forKey: "overlay.previousPinned")
        previousFrame = NSRectFromString(UserDefaults.standard.string(forKey: "overlay.previousFrame") ?? "{{0, 0}, {0, 0}}")
        placePanel()
        panel.orderFrontRegardless()
        model.beginOverlaySampling(metrics: preferences.metrics, interval: preferences.refresh)
    }
    func preview() {
        let wasActive = isActive
        if !wasActive { activate() }
        previewTimeout?.cancel()
        previewTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !wasActive else { return }
            self.deactivate()
        }
    }
    private func refreshOcclusionSampling() {
        guard isActive else { return }
        if panel.isVisible && panel.occlusionState.contains(.visible) {
            model.beginOverlaySampling(metrics: preferences.metrics, interval: preferences.refresh)
        } else {
            model.pauseOverlaySampling()
        }
    }
    func activate() {
        guard !isActive else { return }
        previousPanelVisible = panelController.panel.isVisible
        previousPinned = panelController.isPinned
        previousFrame = panelController.panel.frame
        UserDefaults.standard.set(previousPanelVisible, forKey: "overlay.previousVisible")
        UserDefaults.standard.set(previousPinned, forKey: "overlay.previousPinned")
        UserDefaults.standard.set(NSStringFromRect(previousFrame), forKey: "overlay.previousFrame")
        isActive = true
        enteredAt = .now
        noteActivity()
        preferences.isMoveMode = false
        panel.ignoresMouseEvents = true
        panel.sharingType = preferences.screenshotMode ? .none : .readOnly
        placePanel()
        panel.orderFrontRegardless()
        model.beginOverlaySampling(metrics: preferences.metrics, interval: preferences.refresh)
        if panelController.panel.isVisible { panelController.close() }
    }
    func deactivate(restoreDashboard: Bool = true) {
        guard isActive else { return }
        moveTimeout?.cancel(); previewTimeout?.cancel()
        preferences.isMoveMode = false
        isActive = false
        panel.orderOut(nil)
        model.endOverlaySampling(reopen: restoreDashboard && previousPanelVisible)
        if restoreDashboard {
            panelController.setPinned(previousPinned)
            if previousPinned, !previousFrame.isEmpty { panelController.panel.setFrame(previousFrame, display: false) }
            if previousPanelVisible { panelController.show() }
        }
    }
    func beginMoveMode() {
        if !isActive { activate() }
        preferences.isMoveMode = true
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.styleMask.insert(.titled)
        panel.title = "Move Overlay · Return or Escape to finish"
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        resetMoveTimeout()
    }
    func resetMoveTimeout() {
        guard preferences.isMoveMode else { return }
        moveTimeout?.cancel()
        moveTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.endMoveMode()
        }
    }
    func endMoveMode() {
        guard preferences.isMoveMode else { return }
        moveTimeout?.cancel(); moveTimeout = nil
        var frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame
            let inset: CGFloat = 16
            let width = frame.width, height = frame.height
            let anchors: [(String, NSPoint)] = [
                ("Top left", NSPoint(x: bounds.minX + inset, y: bounds.maxY - height - inset)),
                ("Top right", NSPoint(x: bounds.maxX - width - inset, y: bounds.maxY - height - inset)),
                ("Bottom left", NSPoint(x: bounds.minX + inset, y: bounds.minY + inset)),
                ("Bottom right", NSPoint(x: bounds.maxX - width - inset, y: bounds.minY + inset)),
                ("Top center", NSPoint(x: bounds.midX - width / 2, y: bounds.maxY - height - inset)),
                ("Bottom center", NSPoint(x: bounds.midX - width / 2, y: bounds.minY + inset)),
                ("Left center", NSPoint(x: bounds.minX + inset, y: bounds.midY - height / 2)),
                ("Right center", NSPoint(x: bounds.maxX - width - inset, y: bounds.midY - height / 2))
            ]
            if let close = anchors.min(by: { hypot($0.1.x - frame.minX, $0.1.y - frame.minY) < hypot($1.1.x - frame.minX, $1.1.y - frame.minY) }),
               hypot(close.1.x - frame.minX, close.1.y - frame.minY) <= 8 {
                preferences.anchor = close.0
                frame.origin = close.1
            }
            frame.origin.x = min(max(bounds.minX, frame.minX), bounds.maxX - width)
            frame.origin.y = min(max(bounds.minY, frame.minY), bounds.maxY - height)
            let base = anchorOrigin(anchor: preferences.anchor, visible: bounds, size: frame.size, inset: inset)
            preferences.offsetX = Double(frame.origin.x - base.x)
            preferences.offsetY = Double(frame.origin.y - base.y)
            preferences.displayName = screen.localizedName
            panel.setFrame(frame, display: true)
        }
        preferences.isMoveMode = false
        panel.styleMask.remove(.titled)
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.orderFrontRegardless()
        placePanel()
    }
    func moveFinishedByKey(_ keyCode: UInt16) -> Bool {
        guard preferences.isMoveMode, keyCode == 36 || keyCode == 53 else { return false }
        endMoveMode(); return true
    }
    func noteActivity() { lastActivity = .now; idleDimmed = false }
    func updateIdleState() {
        let busy = (model.snapshot.cpu.load ?? 0) * 100 >= 10 || (model.snapshot.gpu.utilization ?? 0) >= 10
        idleDimmed = preferences.autoHide && !busy && Date.now.timeIntervalSince(lastActivity) > 5
        if busy { lastActivity = .now }
    }
    func preferencesChanged() {
        if isActive { panel.sharingType = preferences.screenshotMode ? .none : .readOnly; placePanel(); model.beginOverlaySampling(metrics: preferences.metrics, interval: preferences.refresh) }
        hotKey?.update(key: preferences.hotKey)
    }
    func setMetrics(_ metrics: [String]) { preferences.metrics = metrics; preferencesChanged() }
    func placePanel() {
        guard let screen = targetScreen else { return }
        let width: CGFloat = preferences.layout == "Bar" ? min(1600, max(180, CGFloat(preferences.metrics.count) * 112 + 24)) : 360
        let rowHeight: CGFloat = preferences.layout == "Bar" ? 24 : 22 * CGFloat(preferences.metrics.count)
        let headerHeight: CGFloat = preferences.hint ? 26 : 0
        let height = max(64, rowHeight + headerHeight + 16) * preferences.scale
        let size = NSSize(width: width * preferences.scale, height: min(height, 760))
        let visible = screen.visibleFrame
        let gap: CGFloat = 16
        var origin: NSPoint
        switch preferences.anchor {
        case "Top left": origin = NSPoint(x: visible.minX + gap, y: visible.maxY - size.height - gap)
        case "Bottom left": origin = NSPoint(x: visible.minX + gap, y: visible.minY + gap)
        case "Bottom right": origin = NSPoint(x: visible.maxX - size.width - gap, y: visible.minY + gap)
        case "Top center": origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - gap)
        case "Bottom center": origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + gap)
        case "Left center": origin = NSPoint(x: visible.minX + gap, y: visible.midY - size.height / 2)
        case "Right center": origin = NSPoint(x: visible.maxX - size.width - gap, y: visible.midY - size.height / 2)
        default: origin = NSPoint(x: visible.maxX - size.width - gap, y: visible.maxY - size.height - gap)
        }
        origin.x += preferences.offsetX
        origin.y += preferences.offsetY
        origin.x = min(max(visible.minX, origin.x), visible.maxX - size.width)
        origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    private func anchorOrigin(anchor: String, visible: NSRect, size: NSSize, inset: CGFloat) -> NSPoint {
        switch anchor {
        case "Top left": NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case "Bottom left": NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case "Bottom right": NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        case "Top center": NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - inset)
        case "Bottom center": NSPoint(x: visible.midX - size.width / 2, y: visible.minY + inset)
        case "Left center": NSPoint(x: visible.minX + inset, y: visible.midY - size.height / 2)
        case "Right center": NSPoint(x: visible.maxX - size.width - inset, y: visible.midY - size.height / 2)
        default: NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        }
    }
    private var targetScreen: NSScreen? {
        if preferences.followActiveDisplay {
            let point = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        }
        if preferences.displayName != "Main", let named = NSScreen.screens.first(where: { $0.localizedName == preferences.displayName }) { return named }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
