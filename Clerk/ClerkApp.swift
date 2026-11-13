import ServiceManagement
import SwiftUI

@main
struct ClerkApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Clerk", systemImage: "person.2.wave.2") {
            MenuContent()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: do not add a login item or show a window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        LoginItem.enableOnFirstLaunch()
    }
}

private struct MenuContent: View {
    @State private var opensAtLogin = LoginItem.isEnabled

    var body: some View {
        Toggle("Open at Login", isOn: $opensAtLogin)
            .onChange(of: opensAtLogin) { _, isOn in LoginItem.set(isOn) }
        Button("Quit Clerk") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ isEnabled: Bool) {
        try? isEnabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    static func enableOnFirstLaunch() {
        let key = "didEnableLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}
