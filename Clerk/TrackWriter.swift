import AVFoundation

/// Writes 16 kHz mono samples to a file as they arrive, so a crash does not lose the meeting.
final class TrackWriter: @unchecked Sendable {
    let url: URL
    private let file: AVAudioFile
    private let lock = NSLock()

    init(url: URL) throws {
        self.url = url
        file = try AVAudioFile(forWriting: url, settings: Resampler.format.settings)
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: Resampler.format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        lock.withLock { try? file.write(from: buffer) }
    }

    /// Writes the end of the file. Call after the last `append`.
    func close() {
        lock.withLock { file.close() }
    }

    /// Replaces "name.caf" with "name.m4a" (AAC, about 20 times smaller). The CAF stays if this fails.
    /// AVAudioFile, not AVAssetExportSession: the export session took 90 s for 6 minutes, this takes 1 s.
    static func compress(_ url: URL) throws {
        let destination = url.deletingPathExtension().appendingPathExtension("m4a")
        let source = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: source.processingFormat.sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 24_000,
        ]
        do {
            let output = try AVAudioFile(
                forWriting: destination, settings: aac, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 65_536)
            else { throw CocoaError(.fileWriteUnknown) }
            while source.framePosition < source.length {
                try source.read(into: buffer)
                try output.write(from: buffer)
            }
            output.close()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Reads a track back as 16 kHz mono samples.
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
