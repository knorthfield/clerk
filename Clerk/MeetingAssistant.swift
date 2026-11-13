import FoundationModels

/// The on-device language model (Apple Intelligence): it finds the talking points that you covered,
/// and writes the summary and the action items.
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

    @Generable
    struct Summary {
        @Guide(description: "A summary of the meeting in one to three short paragraphs.")
        var summary: String
        @Guide(description: "The decisions that the meeting made. Empty if none.")
        var decisions: [String]
        @Guide(description: "The tasks that a person agreed to do. Empty if none.")
        var actionItems: [ActionItem]
    }

    @Generable
    struct ActionItem: Equatable {
        @Guide(description: "The name of the person who will do the task, as in the transcript, or \"Not known\".")
        var owner: String
        @Guide(description: "The task, starting with a verb. Include the deadline if there is one.")
        var task: String
    }

    /// The model's context is small (about 4,000 tokens for instructions, prompt and answer together),
    /// so a long transcript is first made into notes, part by part.
    static let partLength = 6_000

    static func summary(
        of transcript: String, agenda: String, prepNotes: String, participants: [String]
    ) async throws -> Summary {
        var text = transcript
        while text.count > partLength {
            var notes: [String] = []
            for part in parts(of: text) {
                let session = LanguageModelSession(instructions: """
                    You make short notes of a part of a meeting transcript. Keep the subjects, the decisions, \
                    the tasks with the person who will do them, numbers and dates. Use the speaker names as given.
                    """)
                notes.append(try await session.respond(to: part).content)
            }
            text = notes.joined(separator: "\n\n")
        }
        let session = LanguageModelSession(instructions: """
            You write meeting notes from a meeting transcript (or from notes of it). Be short and exact. Use the \
            speaker names as given ("Me" is the person who will read the notes). Do not add facts.
            """)
        var prompt = ""
        if !participants.isEmpty {
            prompt += "Participants (spell names like this; the transcript numbers speakers): "
            prompt += participants.joined(separator: ", ") + "\n\n"
        }
        if !agenda.isEmpty { prompt += "Agenda:\n\(agenda.prefix(1_000))\n\n" }
        if !prepNotes.isEmpty { prompt += "Background:\n\(prepNotes.prefix(1_000))\n\n" }
        prompt += "Meeting:\n\(text)"
        return try await session.respond(to: prompt, generating: Summary.self).content
    }

    /// Splits text into parts of at most `partLength` characters, at line ends where possible.
    static func parts(of text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for piece in line.chunks(ofCount: partLength) {
                if !current.isEmpty, current.count + piece.count + 1 > partLength {
                    parts.append(current)
                    current = ""
                }
                current += current.isEmpty ? String(piece) : "\n" + piece
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

private extension Substring {
    func chunks(ofCount count: Int) -> [Substring] {
        guard !isEmpty else { return [self] }
        var result: [Substring] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: count, limitedBy: endIndex) ?? endIndex
            result.append(self[start..<end])
            start = end
        }
        return result
    }
}
