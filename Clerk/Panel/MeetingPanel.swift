import AppKit
import SwiftUI

/// The floating meeting window. By default it is at the top centre of the screen, just under the
/// camera, so you look at the camera when you read it. You can drag it; it remembers the place.
@MainActor
final class MeetingPanel {
    static let size = NSSize(width: 640, height: 220)

    private let panel: NSPanel

    init(meeting: Meeting) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // Other people do not see the panel when you share your screen.
        panel.sharingType = .none

        let host = NSHostingController(rootView: MeetingView(meeting: meeting))
        // Never `.preferredContentSize`: on macOS 26 it can recurse and crash.
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(Self.size)

        if !panel.setFrameUsingName("MeetingPanel") { placeUnderCamera() }
        panel.setFrameAutosaveName("MeetingPanel")
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Top centre of the main screen (the built-in screen has the camera), just under the menu bar.
    private func placeUnderCamera() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 8))
    }
}
