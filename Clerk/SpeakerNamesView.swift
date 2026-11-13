import SwiftUI

/// After a meeting: give names to "Speaker 1", "Speaker 2"… Pick a participant from Meeting Prep,
/// or type a name. A participant you give to one speaker goes off the lists of the others.
/// The file is already saved; Save puts the names in it.
struct SpeakerNamesView: View {
    struct Speaker: Identifiable {
        let label: String
        let firstWords: String
        var id: String { label }
    }

    let speakers: [Speaker]
    let participants: [String]
    let onDone: ([String: String]) -> Void
    @State private var names: [String: String] = [:]

    /// The participants that no other speaker has.
    static func available(_ participants: [String], names: [String: String], for label: String) -> [String] {
        let taken = Set(names.filter { $0.key != label }.values.map { $0.trimmingCharacters(in: .whitespaces) })
        return participants.filter { !taken.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who spoke?").font(.title2.bold())
            Text(participants.isEmpty
                 ? "Type a name for each speaker, or leave it empty to keep the number."
                 : "Pick a participant for each speaker, or type a name. Leave it empty to keep the number.")
                .foregroundStyle(.secondary)
            ForEach(speakers) { speaker in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField(speaker.label, text: binding(for: speaker.label))
                        if !participants.isEmpty {
                            let choices = Self.available(participants, names: names, for: speaker.label)
                            Menu("Participants") {
                                ForEach(choices, id: \.self) { name in
                                    Button(name) { names[speaker.label] = name }
                                }
                                if names[speaker.label, default: ""].isEmpty == false {
                                    Divider()
                                    Button("Clear") { names[speaker.label] = "" }
                                }
                            }
                            .fixedSize()
                            .disabled(choices.isEmpty && names[speaker.label, default: ""].isEmpty)
                        }
                    }
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
        .frame(width: 460)
    }

    private func binding(for label: String) -> Binding<String> {
        Binding(get: { names[label, default: ""] }, set: { names[label] = $0 })
    }
}

@MainActor
final class SpeakerNamesWindow {
    private var window: NSWindow?

    func show(speakers: [SpeakerNamesView.Speaker], participants: [String], onDone: @escaping ([String: String]) -> Void) {
        window?.close()
        let view = SpeakerNamesView(speakers: speakers, participants: participants) { [weak self] names in
            self?.window?.close()
            self?.window = nil
            onDone(names)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Meeting Notes"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}
