import AppKit
import AVFoundation

enum Permissions {
    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Shows the system prompt the first time. If you said no before, opens System Settings.
    static func requestMicrophone() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .authorized: break
        default: openSettings("Privacy_Microphone")
        }
    }

    static func openSettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}
