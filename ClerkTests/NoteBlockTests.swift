import Testing
@testable import Clerk

@Test func notesMarkdownBecomesBlocks() {
    let markdown = """
        # Q3 budget

        13 Nov 2026 · 42 min

        ## Action items

        - [ ] **Sarah** — Send the job descriptions
        - [x] Budget
        - Cut travel

        **Me** [00:00:05]: Hello.
        Second line.

        **Sarah** [00:00:09]: Hi.
        """
    #expect(NoteBlock.blocks(of: markdown) == [
        .title("Q3 budget"),
        .paragraph("13 Nov 2026 · 42 min"),
        .heading("Action items"),
        .task(isDone: false, text: "**Sarah** — Send the job descriptions"),
        .task(isDone: true, text: "Budget"),
        .bullet("Cut travel"),
        .line(speaker: "Me", time: 5, text: "Hello.\nSecond line."),
        .line(speaker: "Sarah", time: 9, text: "Hi."),
    ])
}

@Test func transcriptLinesHaveTheirTime() {
    #expect(NoteBlock.blocks(of: "**Speaker 2** [01:02:05]: Morning.") == [
        .line(speaker: "Speaker 2", time: 3725, text: "Morning."),
    ])
    // Bold text without a time stays a paragraph.
    #expect(NoteBlock.blocks(of: "**Me** said [hi]: yes") == [.paragraph("**Me** said [hi]: yes")])
}
