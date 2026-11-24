import SwiftUI

/// After a meeting: give names to "Speaker 1", "Speaker 2"… Pick a participant from Meeting Prep,
/// or type a name. A participant you give to one speaker goes off the lists of the others.
/// The file is already saved; Save puts the names in it.
struct SpeakerNamesView: View {
    struct Speaker: Identifiable, Equatable {
        let label: String
        let firstWords: String
        /// The meeting window while this speaker talks, if Clerk recorded it.
        var picture: NSImage?
        var id: String { label }
    }

    let speakers: [Speaker]
    let participants: [String]
    let suggestedNames: [String: String]
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
            if !suggestedNames.isEmpty {
                Text("The names that you tapped, or that Clerk read in the meeting window, are filled in. Check them.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    HStack(alignment: .top) {
                        if let picture = speaker.picture {
                            Image(nsImage: picture)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 160)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                        Text("“\(speaker.firstWords)”").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(speaker.picture == nil ? 2 : 6)
                    }
                }
            }
            }
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: speakers.allSatisfy { $0.picture == nil })
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
        .onAppear { names = suggestedNames }
    }

    private func binding(for label: String) -> Binding<String> {
        Binding(get: { names[label, default: ""] }, set: { names[label] = $0 })
    }
}
