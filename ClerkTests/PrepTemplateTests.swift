import Testing
@testable import Clerk

@Test func blankTemplateGivesEmptySections() {
    #expect(PrepTemplate.sections(of: PrepTemplate.blank) == PrepTemplate.Sections())
}

@Test func filledTemplateFromAnAssistantFillsEverySection() {
    let answer = """
        ```markdown
        # Meeting prep

        ## Participants
        <!-- One name per line, as people say it. -->
        - Sarah Khan
        - Daniel

        ## Agenda
        1. Q3 budget
        2. Hiring

        ## Talking points
        - Cut travel by 10%
        - Two platform engineers before December

        ## Prep notes
        Forecast is 10% under plan.

        ## Risks
        Launch may slip.
        ```
        """
    let sections = PrepTemplate.sections(of: answer)
    #expect(sections == PrepTemplate.Sections(
        participants: "- Sarah Khan\n- Daniel",
        agenda: "1. Q3 budget\n2. Hiring",
        talkingPoints: "- Cut travel by 10%\n- Two platform engineers before December",
        notes: "Forecast is 10% under plan.\n\n## Risks\nLaunch may slip."
    ))
}

@Test func textWithoutTheHeadingsIsNotATemplate() {
    #expect(PrepTemplate.sections(of: "Just some notes\n# Title") == nil)
}

@Test func sectionsSurviveTheRoundTripThroughText() {
    let sections = PrepTemplate.Sections(participants: "- Sarah", agenda: "1. Budget", talkingPoints: "- Travel", notes: "Notes")
    #expect(PrepTemplate.sections(of: PrepTemplate.text(of: sections)) == sections)
}

@Test func aiPromptEndsWithThePrep() {
    #expect(PrepTemplate.aiPrompt(with: "## Agenda\n- Budget").hasSuffix("\n\n## Agenda\n- Budget"))
}
