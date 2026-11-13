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

@MainActor @Test func talkingPointListUsesTheLines() {
    let prep = Prep(url: nil)
    prep.talkingPoints = "1. Budget\n2. Hiring"
    #expect(prep.talkingPointList == ["Budget", "Hiring"])
}
