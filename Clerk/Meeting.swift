import FluidAudio
import Foundation
import Observation

/// One meeting at a time: idle → recording → processing → idle.
@MainActor @Observable
final class Meeting {
    enum Stage {
        case idle, recording, processing
    }

    private enum ModelState {
        case loading(Double)
        case ready(AsrModels)
        case failed(String)
    }

    private(set) var stage = Stage.idle
    private var modelState = ModelState.loading(0)
    private(set) var startedAt: Date?
    private(set) var lastError: String?
    private(set) var micLevel: Float = 0
    private(set) var othersLevel: Float = 0
    var talkingPoints: [TalkingPoint] = []
    /// The transcript so far, in the order the chunks were transcribed.
    private(set) var chunks: [Chunk] = []

    @ObservationIgnored private let prep: Prep
    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private let systemAudio = SystemAudioTap()
    @ObservationIgnored private var tracks: [TrackWriter] = []
    @ObservationIgnored private var live: LiveTranscriber?
    @ObservationIgnored private var coach: Task<Void, Never>?

    /// How often the coach checks the transcript, and how much of the transcript it reads.
    private static let coachInterval = Duration.seconds(30)
    private static let coachWindow: TimeInterval = 120
    @ObservationIgnored private lazy var panel = MeetingPanel(meeting: self)

    init(prep: Prep) {
        self.prep = prep
    }

    var isRecording: Bool { stage == .recording }

    var status: String {
        switch (stage, modelState) {
        case (.recording, _): "Recording"
        case (.processing, _): "Writing the meeting notes…"
        case (.idle, .loading(let fraction)): "Getting the speech model ready… \(Int(fraction * 100)) %"
        case (.idle, .failed(let message)): "The speech model did not load: \(message)"
        case (.idle, .ready): "Ready"
        }
    }

    var canStart: Bool {
        if stage == .idle, case .ready = modelState { true } else { false }
    }

    var modelFailed: Bool {
        if case .failed = modelState { true } else { false }
    }

    /// Downloads the model on first use (about 480 MB), then loads it from the cache.
    func loadModel() {
        modelState = .loading(0)
        Task {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
                    Task { @MainActor [weak self] in
                        if case .loading = self?.modelState { self?.modelState = .loading(progress.fractionCompleted) }
                    }
                }
                modelState = .ready(models)
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    static var storageFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Clerk", directoryHint: .isDirectory)
    }

    func start() {
        guard stage == .idle, case .ready(let models) = modelState else { return }
        let now = Date.now
        let folder = Self.storageFolder.appending(path: Self.folderName(for: now), directoryHint: .isDirectory)
        let live = LiveTranscriber(models: models) { [weak self] chunk in
            Task { @MainActor in self?.chunks.append(chunk) }
        } onError: { [weak self] error in
            Task { @MainActor in self?.lastError = error.localizedDescription }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let micTrack = try TrackWriter(url: folder.appending(path: "me.caf"))
            let othersTrack = try TrackWriter(url: folder.appending(path: "others.caf"))
            try mic.start { [weak self] samples in
                micTrack.append(samples)
                live.feed(samples, isMe: true)
                let level = level(of: samples)
                Task { @MainActor in self?.micLevel = level }
            }
            do {
                try systemAudio.start { [weak self] samples in
                    othersTrack.append(samples)
                    live.feed(samples, isMe: false)
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
            Task { await live.finish() }
            return
        }
        self.live = live
        lastError = nil
        chunks = []
        talkingPoints = prep.talkingPointList.enumerated().map { TalkingPoint(id: $0.offset, text: $0.element) }
        startedAt = now
        stage = .recording
        panel.show()
        if MeetingAssistant.isAvailable { coach = Task { await runCoach() } }
    }

    /// Every 30 s, if there is new text, asks the model which open points the last 2 minutes covered.
    /// It only ticks points. You untick a point by hand if the model is wrong.
    private func runCoach() async {
        var checkedChunkCount = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.coachInterval)
            let open = talkingPoints.filter { !$0.isCovered }
            guard chunks.count > checkedChunkCount, !open.isEmpty, let last = chunks.last else { continue }
            checkedChunkCount = chunks.count
            let recent = chunks.filter { $0.start >= last.start - Self.coachWindow }
            do {
                let covered = try await MeetingAssistant.coveredPoints(in: MeetingAssistant.text(of: recent), of: open)
                for id in covered {
                    if let index = talkingPoints.firstIndex(where: { $0.id == id }) { talkingPoints[index].isCovered = true }
                }
            } catch {
                // The coach is a help, not the record: try again at the next check.
                continue
            }
        }
    }

    func stop() {
        guard stage == .recording, let live else { return }
        mic.stop()
        systemAudio.stop()
        tracks = []
        micLevel = 0
        othersLevel = 0
        panel.hide()
        coach?.cancel()
        coach = nil
        stage = .processing
        self.live = nil
        Task {
            await live.finish()
            stage = .idle
        }
    }

    func toggle(_ point: TalkingPoint) {
        guard let index = talkingPoints.firstIndex(where: { $0.id == point.id }) else { return }
        talkingPoints[index].isCovered.toggle()
    }

    static func folderName(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
    }
}
