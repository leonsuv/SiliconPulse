import AppKit
import SwiftUI
import Observation

@MainActor final class ManagedPanel: NSPanel, NSWindowDelegate {
    var isPinned = false
    var visibilityChanged: ((Bool) -> Void)?
    var frameChanged: ((NSRect) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !isPinned { orderOut(nil); return }
        super.keyDown(with: event)
    }

    override func becomeKey() { super.becomeKey(); notifyVisibility() }
    override func resignKey() { super.resignKey(); notifyVisibility() }
    func observeOcclusion() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.notifyVisibility() }
        })
    }
    func notifyVisibility() { visibilityChanged?(isVisible && occlusionState.contains(.visible)) }
    func windowDidMove(_ notification: Notification) { frameChanged?(frame) }
    func windowDidResize(_ notification: Notification) { frameChanged?(frame) }
    func windowDidResignKey(_ notification: Notification) { if !isPinned { orderOut(nil) }; notifyVisibility() }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

@MainActor @Observable final class PanelController {
    static weak var active: PanelController?
    static var sharedPinned: Bool { active?.pinned ?? false }
    let model: AppModel
    private(set) var pinned = UserDefaults.standard.bool(forKey: "panelPinned")
    var editMode = false
    var resizeStartSize: CGSize?
    var showLayoutResetConfirmation = false
    var panel: ManagedPanel!
    private weak var statusButton: NSStatusBarButton?

    init(model: AppModel) {
        self.model = model
        Self.active = self
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = max(300, UserDefaults.standard.double(forKey: "panelWidth").nonzeroOr(380))
        let height = min(screen.visibleFrame.height * 0.8, 640)
        let initial = NSRect(x: screen.visibleFrame.maxX - width - 20, y: screen.visibleFrame.maxY - height - 40, width: width, height: height)
        panel = ManagedPanel(contentRect: initial, styleMask: [.borderless, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.delegate = panel
        panel.minSize = NSSize(width: 300, height: 260)
        panel.maxSize = NSSize(width: 700, height: screen.visibleFrame.height)
        panel.isPinned = pinned
        let root = DashboardView(panelController: self, onSettings: { [weak self] in self?.openSettings() })
            .environment(model).environment(\.locale, model.locale)
        panel.contentView = NSHostingView(rootView: root)
        panel.observeOcclusion()
        panel.visibilityChanged = { [weak model] visible in model?.setPopoverOpen(visible) }
        panel.frameChanged = { [weak self] frame in self?.saveFrame(frame) }
        applyMode(restoreFrame: true)
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        else { show() }
    }
    func setStatusButton(_ button: NSStatusBarButton) { statusButton = button }
    func show() {
        if !pinned { anchorBelowStatusItem() }
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.notifyVisibility()
    }
    func close() { panel.orderOut(nil) }

    func setPinned(_ value: Bool) {
        guard pinned != value else { return }
        let wasVisible = panel.isVisible
        pinned = value
        panelPinnedSave(value)
        panel.isPinned = value
        applyMode(restoreFrame: false)
        if !value { anchorBelowStatusItem() }
        if wasVisible { panel.makeKeyAndOrderFront(nil) }
        saveFrame(panel.frame)
    }

    func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func setWidth(_ width: CGFloat) {
        guard !pinned else { return }
        var frame = panel.frame
        frame.size.width = min(700, max(300, width))
        panel.setFrame(frame, display: true)
        UserDefaults.standard.set(Double(frame.width), forKey: "panelWidth")
    }
    func resizePanel(width: CGFloat, height: CGFloat) {
        guard pinned else { return }
        var frame = panel.frame
        frame.size.width = min(700, max(300, width))
        frame.size.height = min((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 1000, max(260, height))
        panel.setFrame(frame, display: true)
    }

    private func panelPinnedSave(_ value: Bool) { UserDefaults.standard.set(value, forKey: "panelPinned") }
    private func applyMode(restoreFrame: Bool) {
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        if pinned {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.styleMask.insert(.resizable)
            panel.minSize = NSSize(width: 300, height: 260)
            panel.maxSize = NSSize(width: 700, height: visible.visibleFrame.height)
            if restoreFrame, let raw = UserDefaults.standard.string(forKey: "pinnedFrame") {
                let saved = NSRectFromString(raw)
                if visible.visibleFrame.contains(saved) { panel.setFrame(saved, display: false) }
                else { panel.setFrame(visible.visibleFrame.insetBy(dx: 20, dy: 20), display: false) }
            }
        } else {
            panel.level = .statusBar
            panel.collectionBehavior = [.transient, .moveToActiveSpace]
            panel.isMovableByWindowBackground = false
            panel.styleMask.remove(.resizable)
            let width = max(300, UserDefaults.standard.double(forKey: "panelWidth").nonzeroOr(380))
            panel.setContentSize(NSSize(width: width, height: min(visible.visibleFrame.height * 0.8, 640)))
        }
    }

    private func saveFrame(_ frame: NSRect) {
        guard pinned else { UserDefaults.standard.set(Double(frame.width), forKey: "panelWidth"); return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "pinnedFrame")
    }
    private func anchorBelowStatusItem() {
        let screen = statusButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = statusButton?.bounds ?? .zero
        let anchor = statusButton.flatMap { button in button.window?.convertToScreen(button.convert(bounds, to: nil)) }
        var frame = panel.frame
        let visible = screen.visibleFrame
        frame.size.height = min(visible.height * 0.8, max(440, frame.height))
        if let anchor {
            frame.origin.x = min(max(visible.minX, anchor.midX - frame.width / 2), visible.maxX - frame.width)
            frame.origin.y = max(visible.minY, anchor.minY - frame.height)
        } else {
            frame.origin.x = min(max(visible.minX, frame.minX), visible.maxX - frame.width)
            frame.origin.y = visible.maxY - frame.height
        }
        panel.setFrame(frame, display: false)
    }
}

private extension Double {
    func nonzeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
