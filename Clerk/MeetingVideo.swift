import AppKit
import AVFoundation
import Vision

/// The video of the meeting window, after the meeting.
enum MeetingVideo {
    /// Copies the video from `offset` seconds, so that its time is the transcript's time, and adds your
    /// voice from `voice` (the microphone track, which starts at the transcript's time 0). No new video encoding.
    static func align(_ source: URL, from offset: TimeInterval, voice: URL?, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let start = CMTime(seconds: max(offset, 0), preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: duration)
        let composition = AVMutableComposition()
        for track in try await asset.load(.tracks) {
            let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            try copy?.insertTimeRange(range, of: track, at: .zero)
            if let copy { copy.preferredTransform = try await track.load(.preferredTransform) }
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        if let voice {
            // The microphone track is PCM, which an MP4 file cannot hold. Make it AAC first.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let aac = folder.appending(path: "me.m4a")
            try await export(AVURLAsset(url: voice), preset: AVAssetExportPresetAppleM4A, to: aac, as: .m4a)
            let voiceAsset = AVURLAsset(url: aac)
            if let track = try await voiceAsset.loadTracks(withMediaType: .audio).first {
                let length = min(try await voiceAsset.load(.duration), range.duration)
                let copy = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
            }
        }
        try await export(composition, preset: AVAssetExportPresetPassthrough, to: destination, as: .mp4)
    }

    private static func export(_ asset: AVAsset, preset: String, to destination: URL, as fileType: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw CocoaError(.fileWriteUnknown) }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: fileType)
    }
}

extension MeetingVideo {
    /// A line of text that text recognition found in a frame, and its height (a fraction of the frame).
    struct TextLine: Equatable {
        let text: String
        let height: Double
    }

    /// The frames at these times, in the order of the times. A time with no frame is left out.
    static func frames(of url: URL, at times: [TimeInterval]) async -> [(time: TimeInterval, image: CGImage)] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        var frames: [(time: TimeInterval, image: CGImage)] = []
        for time in times {
            if let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image {
                frames.append((time, image))
            }
        }
        return frames
    }

    /// The text in a frame, with on-device text recognition.
    static func textLines(in image: CGImage) async -> [TextLine] {
        var request = RecognizeTextRequest()
        request.usesLanguageCorrection = false
        request.recognitionLevel = .accurate
        var observations = try? await request.perform(on: image)
        if observations == nil {
            // Accurate recognition needs the Neural Engine, which a virtual Mac does not have.
            request.recognitionLevel = .fast
            observations = try? await request.perform(on: image)
        }
        return (observations ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { TextLine(text: $0.string, height: Double(observation.boundingBox.height)) }
        }
    }

    /// The participants whose names a frame shows in its biggest text. A meeting app shows the name of the
    /// person who talks bigger, or only that name. A participant's full name or first name must be whole words.
    static func participantsSeen(in lines: [TextLine], participants: [String]) -> Set<String> {
        var heights: [String: Double] = [:]
        for participant in participants {
            let words = participant.split(separator: " ")
            guard let firstName = words.first else { continue }
            let patterns = Set([participant, String(firstName)]).map { "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b" }
            for line in lines where patterns.contains(where: { line.text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                heights[participant] = max(heights[participant] ?? 0, line.height)
            }
        }
        guard let biggest = heights.values.max() else { return [] }
        return Set(heights.filter { $0.value >= biggest * 0.8 }.keys)
    }

    /// When to look at the video: every 5 s while one of the others talks, at most `limit` times.
    static func sampleTimes(of segments: [FinalTranscript.SpeakerSegment], limit: Int = 120) -> [TimeInterval] {
        let times = segments.flatMap { segment in
            stride(from: segment.start + 1, to: segment.end, by: 5).map { $0 }
        }
        guard times.count > limit else { return times }
        return (0..<limit).map { times[$0 * times.count / limit] }
    }

    /// For each speaker, the frame in the middle of their longest turn.
    static func pictures(of url: URL, segments: [FinalTranscript.SpeakerSegment], labels: [String: String]) async -> [String: NSImage] {
        var pictures: [String: NSImage] = [:]
        for (id, label) in labels {
            guard let longest = segments.filter({ $0.speakerID == id }).max(by: { $0.end - $0.start < $1.end - $1.start }),
                  let frame = await frames(of: url, at: [(longest.start + longest.end) / 2]).first
            else { continue }
            pictures[label] = NSImage(cgImage: frame.image, size: .zero)
        }
        return pictures
    }

    /// Which participants the video shows as the person who talks, while the others talk.
    static func sightings(of url: URL, segments: [FinalTranscript.SpeakerSegment], participants: [String]) async -> [FinalTranscript.Sighting] {
        var sightings: [FinalTranscript.Sighting] = []
        for frame in await frames(of: url, at: sampleTimes(of: segments)) {
            let names = participantsSeen(in: await textLines(in: frame.image), participants: participants)
            sightings.append(.init(time: frame.time, names: names))
        }
        return sightings
    }
}
