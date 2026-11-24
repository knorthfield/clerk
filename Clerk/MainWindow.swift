import AppKit
import SwiftUI

/// Clerk's one window. For a meeting it becomes a small panel: on top of other windows, under the
/// camera (so you look at the camera when you read it), and hidden from screen sharing. After the
/// meeting it is a normal window again. The normal window and the panel each keep their own place.
@MainActor
final class MainWindow {
    static let panelSize = NSSize(width: 360, height: 300)

    private static let normalStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    private static let autosaveName = "MainWindow"
    private static let panelFrameKey = "MeetingPanelFrame"

    private let window: NSWindow
    private var normalFrame: NSRect?

    init(meeting: Meeting, prep: Prep) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: Self.normalStyle,
            backing: .buffered,
            defer: false
        )
        window.title = "Clerk"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 400)
        let root = ContentView(meeting: meeting, prep: prep) { [weak self] isMeeting in self?.setMeetingMode(isMeeting) }
        let host = NSHostingController(rootView: root)
        // Never `.preferredContentSize`: on macOS 26 it can recurse and crash.
        host.sizingOptions = []
        window.contentViewController = host
        // Setting the view controller sizes the window to its smallest size: set the first size again.
        window.setContentSize(NSSize(width: 760, height: 620))
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func setMeetingMode(_ isMeeting: Bool) {
        if isMeeting {
            normalFrame = window.frame
            // While it is a panel, the window must not save its place as the normal window's place.
            window.setFrameAutosaveName("")
            window.styleMask = [.borderless]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.sharingType = .none
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.setFrame(savedPanelFrame ?? Self.frameUnderCamera, display: true)
            window.orderFrontRegardless()
        } else {
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.panelFrameKey)
            window.styleMask = Self.normalStyle
            window.level = .normal
            window.collectionBehavior = []
            window.sharingType = .readOnly
            window.isMovableByWindowBackground = false
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.title = "Clerk"
            if let normalFrame { window.setFrame(normalFrame, display: true) }
            window.setFrameAutosaveName(Self.autosaveName)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    /// The panel's last place, if it is still on a screen.
    private var savedPanelFrame: NSRect? {
        guard let string = UserDefaults.standard.string(forKey: Self.panelFrameKey) else { return nil }
        let frame = NSRectFromString(string)
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return nil }
        return NSRect(origin: frame.origin, size: Self.panelSize)
    }

    /// Top centre of the main screen (the built-in screen has the camera), just under the menu bar.
    private static var frameUnderCamera: NSRect {
        let visible = NSScreen.screens.first?.visibleFrame ?? .zero
        return NSRect(x: visible.midX - panelSize.width / 2, y: visible.maxY - panelSize.height - 8,
                      width: panelSize.width, height: panelSize.height)
    }
}
