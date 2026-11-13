import Foundation
import Observation

/// One meeting at a time: idle → recording → idle.
@MainActor @Observable
final class Meeting {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var lastError: String?
    private(set) var micLevel: Float = 0
    private(set) var othersLevel: Float = 0
    var talkingPoints: [TalkingPoint] = []

    @ObservationIgnored private let prep: Prep
    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private let systemAudio = SystemAudioTap()
    @ObservationIgnored private var tracks: [TrackWriter] = []
    @ObservationIgnored private lazy var panel = MeetingPanel(meeting: self)

    init(prep: Prep) {
        self.prep = prep
    }

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
            let othersTrack = try TrackWriter(url: folder.appending(path: "others.caf"))
            try mic.start { [weak self] samples in
                micTrack.append(samples)
                let level = level(of: samples)
                Task { @MainActor in self?.micLevel = level }
            }
            do {
                try systemAudio.start { [weak self] samples in
                    othersTrack.append(samples)
                    let level = level(of: samples)
                    Task { @MainActor in self?.othersLevel = level }
                }
            } catch {
                mic.stop()
                throw error
            }
            tracks = [micTrack, othersTrack]
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        talkingPoints = prep.talkingPointList.enumerated().map { TalkingPoint(id: $0.offset, text: $0.element) }
        startedAt = now
        isRecording = true
        panel.show()
    }

    func stop() {
        guard isRecording else { return }
        mic.stop()
        systemAudio.stop()
        tracks = []
        isRecording = false
        micLevel = 0
        othersLevel = 0
        panel.hide()
    }

    func toggle(_ point: TalkingPoint) {
        guard let index = talkingPoints.firstIndex(where: { $0.id == point.id }) else { return }
        talkingPoints[index].isCovered.toggle()
    }

    static func folderName(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
    }
}
