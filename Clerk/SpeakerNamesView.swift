import SwiftUI

/// After a meeting: give names to "Speaker 1", "Speaker 2"… The file is already saved;
/// Save puts the names in it.
struct SpeakerNamesView: View {
    struct Speaker: Identifiable {
        let label: String
        let firstWords: String
        var id: String { label }
    }

    let speakers: [Speaker]
    let onDone: ([String: String]) -> Void
    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who spoke?").font(.title2.bold())
            Text("Type a name for each speaker, or leave it empty to keep the number.")
                .foregroundStyle(.secondary)
            ForEach(speakers) { speaker in
                VStack(alignment: .leading, spacing: 4) {
                    TextField(speaker.label, text: Binding(
                        get: { names[speaker.label, default: ""] },
                        set: { names[speaker.label] = $0 }
                    ))
                    Text("“\(speaker.firstWords)”").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                Spacer()
                Button("Skip") { onDone([:]) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onDone(names) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

@MainActor
final class SpeakerNamesWindow {
    private var window: NSWindow?

    func show(speakers: [SpeakerNamesView.Speaker], onDone: @escaping ([String: String]) -> Void) {
        window?.close()
        let window = NSWindow(contentViewController: NSHostingController(rootView: SpeakerNamesView(speakers: speakers) { [weak self] names in
            self?.window?.close()
            self?.window = nil
            onDone(names)
        }))
        window.title = "Meeting Notes"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}
