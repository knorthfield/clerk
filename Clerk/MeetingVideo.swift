import AVFoundation

/// The video of the meeting window, after the meeting.
enum MeetingVideo {
    /// Copies the video from `offset` seconds, so that its time is the transcript's time. No new encoding.
    static func align(_ source: URL, from offset: TimeInterval, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { throw CocoaError(.fileWriteUnknown) }
        let duration = try await asset.load(.duration)
        let start = CMTime(seconds: max(offset, 0), preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, end: duration)
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .mp4)
    }
}
