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

        **Me** (14:05:05)
        Hello.

        **Sarah** (14:05:09)
        Hi.
        """
    #expect(NoteBlock.blocks(of: markdown) == [
        .title("Q3 budget"),
        .paragraph("13 Nov 2026 · 42 min"),
        .heading("Action items"),
        .task(isDone: false, text: "**Sarah** — Send the job descriptions"),
        .task(isDone: true, text: "Budget"),
        .bullet("Cut travel"),
        .paragraph("**Me** (14:05:05)\nHello."),
        .paragraph("**Sarah** (14:05:09)\nHi."),
    ])
}

@Test func frontMatterIsNotShown() {
    #expect(NoteBlock.blocks(of: "---\ntype: meeting\n---\n\n# Q3 budget") == [.title("Q3 budget")])
}
