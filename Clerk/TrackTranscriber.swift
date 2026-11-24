import AVFoundation
import FluidAudio

/// One track's transcribed speech. Times are seconds from the start of the meeting.
struct Chunk: Identifiable, Sendable {
    let id = UUID()
    let isMe: Bool
    let text: String
    let tokens: [TokenTiming]

    var start: TimeInterval { tokens.first?.startTime ?? 0 }
}

/// Speech to text for a whole track, after the meeting. Both tracks start at the meeting's start,
/// so the times of the tokens are meeting times.
enum TrackTranscriber {
    /// Nil if the track is too short or has no words.
    static func chunk(of url: URL, isMe: Bool, models: AsrModels) async throws -> Chunk? {
        let manager = AsrManager(config: .default, models: models)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await manager.transcribe(url, decoderState: &state)
        } catch ASRError.invalidAudioData {
            return nil
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let tokens = result.tokenTimings, !tokens.isEmpty else { return nil }
        return Chunk(isMe: isMe, text: text, tokens: tokens)
    }
}
