import SwiftUI
import AppKit

struct WindowDragHandle: NSViewRepresentable {
    var enabled: Bool

    func makeNSView(context: Context) -> WindowDragArea {
        let view = WindowDragArea()
        view.enabled = enabled
        return view
    }

    func updateNSView(_ nsView: WindowDragArea, context: Context) {
        nsView.enabled = enabled
    }
}

final class WindowDragArea: NSView {
    var enabled = false
    override var mouseDownCanMoveWindow: Bool { enabled }

    override func mouseDown(with event: NSEvent) {
        guard enabled, event.clickCount == 1 else { return }
        window?.performDrag(with: event)
    }
}
