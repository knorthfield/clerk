import Foundation
import Testing
@testable import Clerk

private func notes() -> MeetingNotes {
    var components = DateComponents(year: 2026, month: 11, day: 13, hour: 14, minute: 5)
    components.timeZone = .current
    return MeetingNotes(
        startedAt: Calendar.current.date(from: components)!,
        duration: 42 * 60,
        agenda: "1. Q3 budget / forecast\n2. Hiring",
        prepNotes: "",
        talkingPoints: [TalkingPoint(id: 0, text: "Budget", isCovered: true), TalkingPoint(id: 1, text: "Hiring")],
        lines: [
            Line(speaker: "Speaker 1", start: 3, text: "Hello all."),
            Line(speaker: "Me", start: 3725, text: "Morning."),
        ],
        summary: .init(summary: "We agreed the budget.", decisions: ["Cut travel"],
                       actionItems: [.init(owner: "Speaker 1", task: "Send the job descriptions by Friday")])
    )
}

@Test func fileNameHasTheDateAndASafeTitle() {
    #expect(notes().fileName == "2026-11-13 1405 Q3 budget - forecast.md")
}

@Test func markdownHasEverySection() {
    let markdown = notes().markdown
    #expect(markdown.hasPrefix("# Q3 budget / forecast\n\n"))
    #expect(markdown.contains("42 min · Speaker 1, Me"))
    #expect(markdown.contains("## Summary\n\nWe agreed the budget."))
    #expect(markdown.contains("## Decisions\n\n- Cut travel"))
    #expect(markdown.contains("## Action items\n\n- [ ] **Speaker 1** — Send the job descriptions by Friday"))
    #expect(markdown.contains("## Talking points\n\n- [x] Budget\n- [ ] Hiring"))
    #expect(!markdown.contains("## Prep notes"))
    #expect(markdown.hasSuffix("## Transcript\n\n**Speaker 1** [00:00:03]: Hello all.\n\n**Me** [01:02:05]: Morning.\n"))
}

@Test func markdownSaysWhyThereIsNoSummary() {
    var notes = notes()
    notes.summary = nil
    notes.summaryProblem = "turn on Apple Intelligence"
    #expect(notes.markdown.contains("## Summary\n\n_Summary not available: turn on Apple Intelligence._"))
    #expect(!notes.markdown.contains("## Action items"))
}

@Test func renamingReplacesOnlyTheWholeLabel() {
    let markdown = "**Speaker 1** said hi to Speaker 10. Speaker 1 will call."
    let renamed = MeetingNotes.renaming(markdown, names: ["Speaker 1": " Sarah ", "Speaker 10": ""])
    #expect(renamed == "**Sarah** said hi to Speaker 10. Sarah will call.")
}

@Test func partsAreShortAndKeepAllText() {
    let line = String(repeating: "word ", count: 300)  // 1,500 characters
    let text = Array(repeating: line, count: 10).joined(separator: "\n") + "\n" + String(repeating: "x", count: 13_000)
    let parts = MeetingAssistant.parts(of: text)
    #expect(parts.allSatisfy { $0.count <= MeetingAssistant.partLength })
    #expect(parts.joined().filter { $0 != "\n" } == text.filter { $0 != "\n" })
}

@MainActor @Test func aParticipantGivenToOneSpeakerIsNotOfferedToTheOthers() {
    let participants = ["Sarah", "Daniel", "Priya"]
    let names = ["Speaker 1": "Sarah", "Speaker 2": "  ", "Speaker 3": "Someone else"]
    #expect(SpeakerNamesView.available(participants, names: names, for: "Speaker 2") == ["Daniel", "Priya"])
    // A speaker's own choice stays on its own list, so you can see it.
    #expect(SpeakerNamesView.available(participants, names: names, for: "Speaker 1") == ["Sarah", "Daniel", "Priya"])
}
