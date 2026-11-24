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
        .paragraph("**Me** [00:00:05]: Hello.\nSecond line."),
        .paragraph("**Sarah** [00:00:09]: Hi."),
    ])
}
