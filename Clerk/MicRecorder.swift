import AVFoundation

/// Records the microphone as 16 kHz mono samples.
final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()

    /// `onSamples` gets each converted buffer on the audio thread.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        let input = engine.inputNode
        // No voice processing: it takes the microphone in a voice-chat mode, and then the meeting app's
        // own voice processing gets silence. With speakers, the echo goes in `FinalTranscript.isEcho`.
        let inputFormat = input.outputFormat(forBus: 0)
        guard let resampler = Resampler(from: inputFormat) else { throw MicRecorderError.unsupportedMicrophone }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            onSamples(resampler.convert(buffer))
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

enum MicRecorderError: LocalizedError {
    case unsupportedMicrophone

    var errorDescription: String? { "The microphone's audio format is not supported." }
}
