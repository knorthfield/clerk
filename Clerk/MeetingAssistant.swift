import FoundationModels

/// The on-device language model (Apple Intelligence): it finds the talking points that you covered.
enum MeetingAssistant {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    @Generable
    struct Coverage {
        @Guide(description: "The numbers of the talking points that the conversation discussed. Empty if none.")
        var coveredPointNumbers: [Int]
    }

    /// Returns the ids of the points in `openPoints` that the transcript covers.
    static func coveredPoints(in transcript: String, of openPoints: [TalkingPoint]) async throws -> [Int] {
        guard !openPoints.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            You help a person in a meeting. You get a part of the meeting transcript and a numbered list of \
            talking points. Tell which talking points the conversation discussed. A point counts as discussed \
            only if the people talked about its subject, not if they only said that they will talk about it later.
            """)
        let response = try await session.respond(
            to: coveragePrompt(transcript: transcript, points: openPoints),
            generating: Coverage.self
        )
        return ids(forNumbers: response.content.coveredPointNumbers, of: openPoints)
    }

    static func coveragePrompt(transcript: String, points: [TalkingPoint]) -> String {
        let list = points.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        return "Talking points:\n\(list)\n\nTranscript:\n\(transcript)"
    }

    /// The model numbers the points from 1. It can give a number that is not on the list; ignore it.
    static func ids(forNumbers numbers: [Int], of points: [TalkingPoint]) -> [Int] {
        numbers.compactMap { points.indices.contains($0 - 1) ? points[$0 - 1].id : nil }
    }

    /// The transcript as the model reads it: one line per chunk.
    static func text(of chunks: some Sequence<Chunk>) -> String {
        chunks.map { "\($0.isMe ? "Me" : "Others"): \($0.text)" }.joined(separator: "\n")
    }
}
