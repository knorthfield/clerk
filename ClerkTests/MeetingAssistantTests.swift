import FluidAudio
import Testing
@testable import Clerk

private let points = [TalkingPoint(id: 4, text: "Budget"), TalkingPoint(id: 7, text: "Hiring")]

@Test func promptNumbersThePointsFromOne() {
    let prompt = MeetingAssistant.coveragePrompt(transcript: "Me: Hello", points: points)
    #expect(prompt == "Talking points:\n1. Budget\n2. Hiring\n\nTranscript:\nMe: Hello")
}

@Test func numbersMapToIdsAndNumbersNotOnTheListAreIgnored() {
    #expect(MeetingAssistant.ids(forNumbers: [2, 0, 3, 1], of: points) == [7, 4])
}

@Test func transcriptHasOneLinePerChunk() {
    let chunks = [Chunk(isMe: true, text: "Hello.", tokens: []), Chunk(isMe: false, text: "Hi.", tokens: [])]
    #expect(MeetingAssistant.text(of: chunks) == "Me: Hello.\nOthers: Hi.")
}
