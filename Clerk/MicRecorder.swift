import AVFoundation

/// Records the microphone as 16 kHz mono samples.
final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()

    /// `onSamples` gets each converted buffer on the audio thread.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        let input = engine.inputNode
        // Echo cancellation: with speakers, the microphone also hears the other people. Voice processing
        // removes what the Mac plays. Do not make the other apps quieter while it runs.
        try input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
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
