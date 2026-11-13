import AVFoundation

/// Converts audio of any format to 16 kHz mono Float32, the format Parakeet needs.
final class Resampler {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    private let converter: AVAudioConverter

    init?(from inputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.format) else { return nil }
        converter.downmix = true
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = Self.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return [] }
        var isConsumed = false
        converter.convert(to: output, error: nil) { _, status in
            if isConsumed {
                // Keep the converter open for the next buffer.
                status.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return buffer
        }
        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
