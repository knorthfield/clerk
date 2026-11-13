import SwiftUI

/// Type or paste your prep, or drop a text or markdown file on a box.
struct PrepView: View {
    @Bindable var prep: Prep

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                PrepBox(title: "Prep notes", prompt: "Background, numbers to remember…", text: $prep.notes)
                PrepBox(title: "Participants", prompt: "One name per line. After the meeting, you pick who each speaker was.",
                        text: $prep.participants)
            }
            VStack(spacing: 0) {
                PrepBox(title: "Agenda", prompt: "One item per line", text: $prep.agenda)
                PrepBox(title: "Talking points", prompt: "One point per line. Clerk ticks them off as you cover them.",
                        text: $prep.talkingPoints)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .toolbar {
            Menu("Template", systemImage: "doc.on.clipboard") {
                Button("Copy Blank Template") { copy(PrepTemplate.blank) }
                Button("Copy Template with AI Prompt") { copy(PrepTemplate.aiPrompt) }
                Button("Paste Filled Template") { pasteTemplate() }
                Divider()
                Button("Clear All") { prep.clear() }
            }
        }
        .alert("The clipboard has no filled template", isPresented: $isPasteFailed) {
        } message: {
            Text("Copy the filled template, with its headings (## Participants, ## Agenda, ## Talking points, ## Prep notes), then try again.")
        }
        // A filled template dropped on the window (not on a box) fills all the boxes.
        .dropDestination(for: URL.self) { urls, _ in
            guard let text = urls.first.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else { return false }
            return prep.fill(fromTemplate: text)
        }
    }

    @State private var isPasteFailed = false

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteTemplate() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        isPasteFailed = !prep.fill(fromTemplate: text)
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
