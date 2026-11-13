import Foundation
import Testing
@testable import Clerk

@Test(arguments: [
    ("Budget", "Budget"),
    ("- Budget", "Budget"),
    ("* Budget", "Budget"),
    ("• Budget", "Budget"),
    ("  1. Budget", "Budget"),
    ("12) Budget", "Budget"),
    ("- [ ] Budget", "Budget"),
    ("- [x] Budget", "Budget"),
    ("Q3 budget - first draft", "Q3 budget - first draft"),
    ("2026 targets", "2026 targets"),
])
func listMarkersAreRemoved(line: String, expected: String) {
    #expect(Prep.lines(of: line) == [expected])
}

@Test func emptyLinesAreRemoved() {
    #expect(Prep.lines(of: "- One\n\n   \n- Two\r\n- Three") == ["One", "Two", "Three"])
}

@MainActor @Test func listsComeFromTheSectionsOfTheText() {
    let prep = Prep(folder: nil)
    prep.text = "## Participants\n- Sarah\n\n## Talking points\n1. Budget\n2. Hiring"
    #expect(prep.talkingPointList == ["Budget", "Hiring"])
    #expect(prep.participantList == ["Sarah"])
}

@MainActor @Test func textWithoutHeadingsIsAllPrepNotes() {
    let prep = Prep(folder: nil)
    prep.text = "Ask about the budget.\n"
    #expect(prep.sections == PrepTemplate.Sections(notes: "Ask about the budget."))
    #expect(prep.talkingPointList.isEmpty)
}

@MainActor @Test func newPrepIsTheBlankTemplate() {
    let prep = Prep(folder: nil)
    #expect(prep.text == PrepTemplate.blank)
    prep.text = "x"
    prep.reset()
    #expect(prep.text == PrepTemplate.blank)
}

@MainActor @Test func prepIsSavedAndTheVersion1BoxesAreReadOnce() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = #"{"notes":"Forecast","agenda":"Budget","talkingPoints":"- Cut travel","participants":"Sarah"}"#
    try old.write(to: folder.appending(path: "prep.json"), atomically: true, encoding: .utf8)

    let migrated = Prep(folder: folder)
    #expect(migrated.sections == PrepTemplate.Sections(
        participants: "Sarah", agenda: "Budget", talkingPoints: "- Cut travel", notes: "Forecast"))
    migrated.text += "\nMore notes"
    #expect(Prep(folder: folder).text == migrated.text)
}
