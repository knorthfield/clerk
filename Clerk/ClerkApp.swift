import ServiceManagement
import SwiftUI

@main
struct ClerkApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Clerk", systemImage: "person.2.wave.2") {
            MenuContent(meeting: appDelegate.meeting)
        }
        Window("Meeting Prep", id: "prep") {
            PrepView(prep: appDelegate.prep)
        }
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prep = Prep()
    lazy var meeting = Meeting(prep: prep)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: do not add a login item or show a window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        LoginItem.enableOnFirstLaunch()
        meeting.loadModel()
    }
}

private struct MenuContent: View {
    let meeting: Meeting
    @State private var opensAtLogin = LoginItem.isEnabled
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(meeting.status)
        if meeting.isRecording {
            Button("Stop Meeting") { meeting.stop() }
        } else {
            Button("Start Meeting") { meeting.start() }
                .disabled(!meeting.canStart)
        }
        if meeting.modelFailed {
            Button("Try Again") { meeting.loadModel() }
        }
        Button("Meeting Prep…") {
            openWindow(id: "prep")
            NSApp.activate()
        }
        if let lastError = meeting.lastError {
            Text(lastError)
        }
        if !Permissions.hasMicrophone {
            Button("Allow Microphone…") { Task { await Permissions.requestMicrophone() } }
        }
        Divider()
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
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
