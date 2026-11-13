import SwiftUI

/// Type or paste your prep, or drop a text or markdown file on a box.
struct PrepView: View {
    @Bindable var prep: Prep

    var body: some View {
        HSplitView {
            PrepBox(title: "Prep notes", prompt: "Background, people, numbers to remember…", text: $prep.notes)
            VStack(spacing: 0) {
                PrepBox(title: "Agenda", prompt: "One item per line", text: $prep.agenda)
                PrepBox(title: "Talking points", prompt: "One point per line. Clerk ticks them off as you cover them.",
                        text: $prep.talkingPoints)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

private struct PrepBox: View {
    let title: String
    let prompt: String
    @Binding var text: String
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if !text.isEmpty {
                    Button("Clear") { text = "" }.buttonStyle(.link)
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(prompt).foregroundStyle(.tertiary).padding(11).allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2).opacity(isTargeted ? 1 : 0)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    let texts = urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                    guard !texts.isEmpty else { return false }
                    text = ([text] + texts).filter { !$0.isEmpty }.joined(separator: "\n")
                    return true
                } isTargeted: { isTargeted = $0 }
        }
        .padding(12)
    }
}
