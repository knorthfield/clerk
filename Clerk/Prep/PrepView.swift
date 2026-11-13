import SwiftUI

/// The prep is one markdown text in the template's format. Type in it, paste a filled template,
/// or drop a markdown file on it.
struct PrepView: View {
    @Bindable var prep: Prep
    @State private var isConfirmingNewPrep = false
    @State private var didCopy = false

    var body: some View {
        TextEditor(text: $prep.text)
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(.background)
            .dropDestination(for: URL.self) { urls, _ in
                guard let text = urls.first.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else { return false }
                prep.text = text
                return true
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(didCopy ? "Copied" : "Copy for AI", systemImage: didCopy ? "checkmark" : "sparkles") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PrepTemplate.aiPrompt(with: prep.text), forType: .string)
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            didCopy = false
                        }
                    }
                    .help("Copy instructions and your prep for an AI assistant. Paste its answer back here.")
                    Button("New Prep", systemImage: "square.and.pencil") { isConfirmingNewPrep = true }
                        .help("Start again from the blank template")
                }
            }
            .confirmationDialog("Start a new prep from the blank template?", isPresented: $isConfirmingNewPrep) {
                Button("New Prep", role: .destructive) { prep.reset() }
            } message: {
                Text("The text you have now is deleted.")
            }
    }
}
