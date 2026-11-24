import FluidAudio
import Foundation
import Testing
@testable import Clerk

/// One token per word, one second per word, starting at `start`.
private func chunk(_ text: String, isMe: Bool, start: TimeInterval) -> Chunk {
    let words = text.split(separator: " ")
    let tokens = words.enumerated().map { index, word in
        TokenTiming(token: " " + word, tokenId: 0, startTime: start + Double(index),
                    endTime: start + Double(index) + 0.9, confidence: 1)
    }
    return Chunk(isMe: isMe, text: text, tokens: tokens)
}

@Test func sentencesGetTheTimesOfTheirTokens() {
    let sentences = FinalTranscript.sentences(of: chunk("Good morning everyone. Can you hear me?", isMe: false, start: 10))
    #expect(sentences == [
        .init(start: 10, end: 12.9, text: "Good morning everyone."),
        .init(start: 13, end: 16.9, text: "Can you hear me?"),
    ])
}

@Test func sentencesWorkWhenTokensSplitWords() {
    let tokens = [(" Go", 0.0), ("od", 0.2), (" mor", 0.4), (" ning", 0.6), (".", 0.8), (" Hi", 5.0), ("!", 5.4)]
        .map { TokenTiming(token: $0.0, tokenId: 0, startTime: $0.1, endTime: $0.1 + 0.2, confidence: 1) }
    let sentences = FinalTranscript.sentences(of: Chunk(isMe: false, text: "Good morning. Hi!", tokens: tokens))
    #expect(sentences.map(\.start) == [0, 5])
}

@Test func speakerWithTheMostOverlapWins() {
    let segments: [FinalTranscript.SpeakerSegment] = [
        .init(speakerID: "A", start: 0, end: 4),
        .init(speakerID: "B", start: 4, end: 10),
    ]
    #expect(FinalTranscript.speakerID(from: 3, to: 8, in: segments) == "B")
    #expect(FinalTranscript.speakerID(from: 12, to: 13, in: segments) == "B")
    #expect(FinalTranscript.speakerID(from: 0, to: 1, in: []) == nil)
}

@Test func linesMergeBothTracksByTimeAndNumberSpeakersInOrder() {
    let chunks = [
        chunk("Hello all. Thanks for joining.", isMe: false, start: 0),
        chunk("Hi. Great to be here.", isMe: false, start: 6),
        chunk("Morning both.", isMe: true, start: 4),
    ]
    let segments: [FinalTranscript.SpeakerSegment] = [
        .init(speakerID: "x", start: 0, end: 5.5),
        .init(speakerID: "y", start: 5.5, end: 20),
    ]
    #expect(FinalTranscript.lines(chunks: chunks, otherSpeakers: segments).lines == [
        Line(speaker: "Speaker 1", start: 0, text: "Hello all. Thanks for joining."),
        Line(speaker: "Me", start: 4, text: "Morning both."),
        Line(speaker: "Speaker 2", start: 6, text: "Hi. Great to be here."),
    ])
}

@Test func theEchoOfTheOthersOnTheMicrophoneIsRemoved() {
    let chunks = [
        chunk("We should cut travel by ten percent.", isMe: false, start: 0),
        // The microphone heard the speakers, a little late and not quite the same words.
        chunk("we should cut the travel by ten per cent", isMe: true, start: 0.5),
        chunk("I agree with that.", isMe: true, start: 3),
    ]
    let lines = FinalTranscript.lines(chunks: chunks, otherSpeakers: []).lines
    #expect(lines == [
        Line(speaker: "Speaker 1", start: 0, text: "We should cut travel by ten percent."),
        Line(speaker: "Me", start: 3, text: "I agree with that."),
    ])
}

@Test func theSameWordsLaterAreNotAnEcho() {
    let theirs = FinalTranscript.Sentence(start: 0, end: 3, text: "Budget is approved.")
    #expect(FinalTranscript.isEcho(.init(start: 60, end: 62, text: "Budget is approved."), of: [theirs]) == false)
    #expect(FinalTranscript.isEcho(.init(start: 1, end: 3, text: "Budget is approved."), of: [theirs]))
    #expect(FinalTranscript.isEcho(.init(start: 1, end: 3, text: "…"), of: [theirs]) == false)
}

@Test func tapsSuggestNamesForSpeakers() {
    let segments: [FinalTranscript.SpeakerSegment] = [
        .init(speakerID: "x", start: 0, end: 10),
        .init(speakerID: "y", start: 10, end: 20),
    ]
    let labels = ["x": "Speaker 1", "y": "Speaker 2"]
    func mark(_ name: String, _ time: TimeInterval) -> FinalTranscript.SpeakerMark { .init(name: name, time: time) }

    // One tap for each speaker.
    #expect(FinalTranscript.suggestedNames(marks: [mark("Sarah", 1), mark("Priya", 11)], segments: segments, labels: labels)
        == ["Speaker 1": "Sarah", "Speaker 2": "Priya"])
    // A wrong tap loses to more right taps.
    #expect(FinalTranscript.suggestedNames(
        marks: [mark("Sarah", 1), mark("Priya", 2), mark("Sarah", 5)], segments: segments, labels: labels)
        == ["Speaker 1": "Sarah"])
    // A name goes to one speaker only: the one with more taps.
    #expect(FinalTranscript.suggestedNames(
        marks: [mark("Sarah", 1), mark("Sarah", 12), mark("Sarah", 15)], segments: segments, labels: labels)
        == ["Speaker 2": "Sarah"])
    // A tap in silence goes to the nearest speaker. No segments, no names.
    #expect(FinalTranscript.suggestedNames(marks: [mark("Sarah", 30)], segments: segments, labels: labels)
        == ["Speaker 2": "Sarah"])
    #expect(FinalTranscript.suggestedNames(marks: [mark("Sarah", 1)], segments: [], labels: [:]) == [:])
}
