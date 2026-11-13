import FluidAudio
import Foundation
import NaturalLanguage

/// One speaker's turn in the final transcript.
struct Line: Equatable {
    var speaker: String
    let start: TimeInterval
    var text: String
}

/// After the meeting: finds who spoke when on the "others" track, and joins both tracks into one
/// transcript with a speaker for each turn. "Me" is the microphone track.
enum FinalTranscript {
    struct SpeakerSegment: Equatable {
        let speakerID: String
        let start: TimeInterval
        let end: TimeInterval
    }

    struct Sentence: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    static let me = "Me"

    /// Speaker separation of a track (pyannote community-1 in Core ML). Downloads its models on first use.
    static func speakerSegments(of url: URL) async throws -> [SpeakerSegment] {
        let diarizer = OfflineDiarizerManager()
        try await diarizer.prepareModels()
        return try await diarizer.process(url).segments.map {
            SpeakerSegment(speakerID: $0.speakerId, start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds))
        }
    }

    static func lines(chunks: [Chunk], otherSpeakers segments: [SpeakerSegment]) -> [Line] {
        var labels: [String: String] = [:]
        let sentences = chunks
            .flatMap { chunk in sentences(of: chunk).map { (sentence: $0, isMe: chunk.isMe) } }
            .sorted { $0.sentence.start < $1.sentence.start }
        var lines: [Line] = []
        for (sentence, isMe) in sentences {
            let speaker: String
            if isMe {
                speaker = me
            } else {
                let id = speakerID(from: sentence.start, to: sentence.end, in: segments) ?? ""
                // Number the speakers in the order they first speak.
                speaker = labels[id] ?? {
                    let label = "Speaker \(labels.count + 1)"
                    labels[id] = label
                    return label
                }()
            }
            if lines.last?.speaker == speaker {
                lines[lines.count - 1].text += " " + sentence.text
            } else {
                lines.append(Line(speaker: speaker, start: sentence.start, text: sentence.text))
            }
        }
        return lines
    }

    /// The speaker who overlaps the time most. With no overlap, the nearest segment's speaker.
    static func speakerID(from start: TimeInterval, to end: TimeInterval, in segments: [SpeakerSegment]) -> String? {
        func overlap(_ segment: SpeakerSegment) -> TimeInterval { min(end, segment.end) - max(start, segment.start) }
        func distance(_ segment: SpeakerSegment) -> TimeInterval { max(segment.start - end, start - segment.end, 0) }
        var overlapBySpeaker: [String: TimeInterval] = [:]
        for segment in segments where overlap(segment) > 0 {
            overlapBySpeaker[segment.speakerID, default: 0] += overlap(segment)
        }
        if let best = overlapBySpeaker.max(by: { $0.value < $1.value }) { return best.key }
        return segments.min { distance($0) < distance($1) }?.speakerID
    }

    /// Splits a chunk into sentences, and finds the time of each sentence from the chunk's tokens.
    /// The tokens and the text have nearly the same letters, so the n-th letter of the text is
    /// in the token that holds the n-th letter of the tokens.
    static func sentences(of chunk: Chunk) -> [Sentence] {
        let text = chunk.text
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var tokenEnds: [Int] = []  // The number of letters up to and including each token.
        var count = 0
        for token in chunk.tokens {
            count += token.token.count { !$0.isWhitespace }
            tokenEnds.append(count)
        }
        func token(atLetter letter: Int) -> TokenTiming? {
            guard let last = chunk.tokens.last else { return nil }
            guard let index = tokenEnds.firstIndex(where: { $0 > letter }) else { return last }
            return chunk.tokens[index]
        }
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return nil }
            let firstLetter = text[..<range.lowerBound].count { !$0.isWhitespace }
            let lastLetter = firstLetter + max(sentence.count { !$0.isWhitespace } - 1, 0)
            return Sentence(
                start: token(atLetter: firstLetter)?.startTime ?? chunk.start,
                end: token(atLetter: lastLetter)?.endTime ?? chunk.start,
                text: sentence
            )
        }
    }
}
