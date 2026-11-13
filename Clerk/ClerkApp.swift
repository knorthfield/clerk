import ServiceManagement
import SwiftUI

@main
struct ClerkApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            SettingsView(meeting: appDelegate.meeting)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prep = Prep()
    lazy var meeting = Meeting(prep: prep)
    private var window: MainWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: do not load the model or show the window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // Version 1.0 was a menu bar app that opened at login. A window app must not.
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        let window = MainWindow(meeting: meeting, prep: prep)
        window.show()
        self.window = window
        meeting.loadModel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
