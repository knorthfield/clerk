import AVFoundation
import Testing
@testable import Clerk

@Test func resamplerConverts48kStereoTo16kMono() throws {
    let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800)!
    buffer.frameLength = 4800
    let resampler = try #require(Resampler(from: input))
    var count = 0
    for _ in 0..<10 { count += resampler.convert(buffer).count }
    // 10 × 0.1 s at 16 kHz; the converter keeps about 14 ms back for its filter.
    #expect(abs(count - 16_000) < 300, "count \(count)")
}

@Test func trackWriterWritesSamplesThatReadBack() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let samples = (0..<1600).map { Float($0) / 1600 }
    do {
        let writer = try TrackWriter(url: url)
        writer.append(samples)
        writer.append(samples)
    }
    let read = try TrackWriter.read(url)
    #expect(read.count == 3200)
    #expect(read[1599] == samples[1599])
}
