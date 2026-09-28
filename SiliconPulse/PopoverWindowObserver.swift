import SwiftUI
import AppKit

@MainActor struct PopoverWindowObserver: NSViewRepresentable {
    let visibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.visibilityChanged = visibilityChanged
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        nsView.visibilityChanged = visibilityChanged
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: ()) {
        nsView.detach()
    }
}

@MainActor final class WindowTrackingView: NSView {
    var visibilityChanged: ((Bool) -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else {
            visibilityChanged?(false)
            return
        }
        observedWindow = window
        visibilityChanged?(window.isKeyWindow)
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visibilityChanged?(true) }
        })
        notificationTokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visibilityChanged?(false) }
        })
    }

    func detach() {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        observedWindow = nil
    }
}
