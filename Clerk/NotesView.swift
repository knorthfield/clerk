import SwiftUI

/// The finished meeting notes, formatted: the summary, then the transcript. The files in the
/// meeting's folder are the record; this reads them.
struct NotesView: View {
    /// The meeting's folder.
    let url: URL
    let newMeeting: () -> Void
    @State private var blocks: [NoteBlock] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks.indices, id: \.self) { index in
                        BlockView(block: blocks[index])
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
                .textSelection(.enabled)
            }
            Divider()
            HStack(spacing: 12) {
                Button("Open Summary") { NSWorkspace.shared.open(url.appending(path: MeetingNotes.summaryFile)) }
                Button("Show in Finder") { NSWorkspace.shared.open(url) }
                Spacer()
                Button("New Meeting", action: newMeeting)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .task(id: url) {
            blocks = [MeetingNotes.summaryFile, MeetingNotes.transcriptFile].flatMap { file in
                NoteBlock.blocks(of: (try? String(contentsOf: url.appending(path: file), encoding: .utf8)) ?? "")
            }
        }
    }
}

private struct BlockView: View {
    let block: NoteBlock

    var body: some View {
        switch block {
        case .title(let text):
            Text(inline(text)).font(.largeTitle.bold())
        case .heading(let text):
            Text(inline(text)).font(.title2.bold()).padding(.top, 12)
        case .task(let isDone, let text):
            Label { Text(inline(text)) } icon: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? .green : .secondary)
            }
        case .bullet(let text):
            Label { Text(inline(text)) } icon: { Text("•") }
        case .paragraph(let text):
            Text(inline(text))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// The parts of Clerk's own markdown: no more is needed to show its notes.
enum NoteBlock: Equatable {
    case title(String)
    case heading(String)
    case task(isDone: Bool, text: String)
    case bullet(String)
    case paragraph(String)

    static func blocks(of markdown: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var paragraph: [String] = []
        func endParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Front matter: not shown.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            lines.removeSubrange(...end)
        }
        for line in lines {
            let block: NoteBlock? =
                if line.hasPrefix("# ") { .title(String(line.dropFirst(2))) }
                else if line.hasPrefix("## ") { .heading(String(line.dropFirst(3))) }
                else if line.hasPrefix("- [ ] ") { .task(isDone: false, text: String(line.dropFirst(6))) }
                else if line.lowercased().hasPrefix("- [x] ") { .task(isDone: true, text: String(line.dropFirst(6))) }
                else if line.hasPrefix("- ") { .bullet(String(line.dropFirst(2))) }
                else { nil }
            if let block {
                endParagraph()
                blocks.append(block)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                endParagraph()
            } else {
                paragraph.append(line)
            }
        }
        endParagraph()
        return blocks
    }
}
