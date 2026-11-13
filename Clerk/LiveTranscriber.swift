import AVFoundation
import FluidAudio

/// One window of transcribed speech from one track. Times are seconds from the start of the meeting.
struct Chunk: Identifiable, Sendable {
    let id = UUID()
    let isMe: Bool
    let text: String
    let tokens: [TokenTiming]

    var start: TimeInterval { tokens.first?.startTime ?? 0 }
}

/// Speech to text for both tracks while the meeting runs, about 13 s behind the speech.
/// FluidAudio's sliding window gives each 11 s of audio once, with the times of its tokens.
final class LiveTranscriber: Sendable {
    private let mic: AsyncStream<[Float]>.Continuation
    private let others: AsyncStream<[Float]>.Continuation
    private let tasks: [Task<Void, Never>]

    /// `onChunk` gets each chunk on a background task.
    init(models: AsrModels, onChunk: @escaping @Sendable (Chunk) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        let (micStream, mic) = AsyncStream.makeStream(of: [Float].self)
        let (othersStream, others) = AsyncStream.makeStream(of: [Float].self)
        self.mic = mic
        self.others = others
        tasks = [(micStream, true), (othersStream, false)].map { stream, isMe in
            Task {
                do {
                    try await Self.transcribe(stream, isMe: isMe, models: models, onChunk: onChunk)
                } catch {
                    onError(error)
                }
            }
        }
    }

    /// Call on the audio thread. The stream keeps the order of the buffers.
    func feed(_ samples: [Float], isMe: Bool) {
        (isMe ? mic : others).yield(samples)
    }

    /// Transcribes the audio that is still waiting, then returns.
    func finish() async {
        mic.finish()
        others.finish()
        for task in tasks { await task.value }
    }

    private static func transcribe(
        _ stream: AsyncStream<[Float]>, isMe: Bool, models: AsrModels,
        onChunk: @escaping @Sendable (Chunk) -> Void
    ) async throws {
        let manager = SlidingWindowAsrManager(config: .default)
        try await manager.loadModels(models)
        try await manager.startStreaming(source: isMe ? .microphone : .system)
        let updates = await manager.transcriptionUpdates
        let publisher = Task {
            for await update in updates where !update.text.trimmingCharacters(in: .whitespaces).isEmpty {
                onChunk(Chunk(isMe: isMe, text: update.text.trimmingCharacters(in: .whitespaces), tokens: update.tokenTimings))
            }
        }
        for await samples in stream where !samples.isEmpty {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: Resampler.format, frameCapacity: AVAudioFrameCount(samples.count))
            else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            await manager.streamAudio(buffer)
        }
        _ = try await manager.finish()
        // `cleanup` ends the update stream, so the loop above ends after the last update.
        await manager.cleanup()
        await publisher.value
    }
}
