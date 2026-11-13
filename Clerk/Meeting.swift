import Foundation
import Observation

/// One meeting at a time: idle → recording → idle.
@MainActor @Observable
final class Meeting {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private var micTrack: TrackWriter?

    static var storageFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Clerk", directoryHint: .isDirectory)
    }

    func start() {
        guard !isRecording else { return }
        let now = Date.now
        let folder = Self.storageFolder.appending(path: Self.folderName(for: now), directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let micTrack = try TrackWriter(url: folder.appending(path: "me.caf"))
            try mic.start { samples in micTrack.append(samples) }
            self.micTrack = micTrack
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        startedAt = now
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        mic.stop()
        micTrack = nil
        isRecording = false
    }

    static func folderName(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
    }
}
