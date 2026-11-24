import AppKit
import os
import FluidAudio
import Observation

/// One meeting at a time: prep → recording → processing → naming the speakers → done → prep.
@MainActor @Observable
final class Meeting {
    enum Stage: Equatable {
        case prep, recording, processing
        case naming(NamingRequest)
        case done(URL)
    }

    /// The saved notes, and the numbered speakers in them.
    struct NamingRequest: Equatable {
        let url: URL
        let speakers: [SpeakerNamesView.Speaker]
        let participants: [String]
        /// Names from the taps in the panel, by label.
        let suggestedNames: [String: String]
    }

    private enum ModelState {
        case loading(Double)
        case ready(AsrModels)
        case failed(String)
    }

    private(set) var stage = Stage.prep
    private var modelState = ModelState.loading(0)
    private(set) var startedAt: Date?
    private(set) var lastError: String?
    private(set) var micLevel: Float = 0
    private(set) var othersLevel: Float = 0
    var talkingPoints: [TalkingPoint] = []
    /// The transcript so far, in the order the chunks were transcribed.
    private(set) var chunks: [Chunk] = []
    /// The participants from Meeting Prep, to tap when one of them talks.
    private(set) var participants: [String] = []
    private(set) var speakerMarks: [FinalTranscript.SpeakerMark] = []

    @ObservationIgnored private let prep: Prep
    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private let systemAudio = SystemAudioTap()
    @ObservationIgnored private var tracks: [TrackWriter] = []
    @ObservationIgnored private var live: LiveTranscriber?
    @ObservationIgnored private var video: WindowRecorder?
    @ObservationIgnored private var coach: Task<Void, Never>?

    /// How often the coach checks the transcript, and how much of the transcript it reads.
    private static let coachInterval = Duration.seconds(30)
    private static let coachWindow: TimeInterval = 120

    init(prep: Prep) {
        self.prep = prep
    }

    var isRecording: Bool { stage == .recording }

    /// While the speech model is not ready, what it does.
    var modelStatus: String? {
        switch modelState {
        case .loading(let fraction): "Getting the speech model ready… \(Int(fraction * 100)) %"
        case .failed(let message): "The speech model did not load: \(message)"
        case .ready: nil
        }
    }

    var canStart: Bool {
        if stage == .prep, case .ready = modelState { true } else { false }
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
        guard stage == .prep, case .ready(let models) = modelState else { return }
        Task {
            // Ask first: if the system prompt shows while the audio engine starts, the app stops responding.
            await Permissions.requestMicrophone()
            guard Permissions.hasMicrophone else {
                lastError = "Clerk needs the microphone. Allow it in System Settings › Privacy & Security."
                return
            }
            let folder = Self.storageFolder.appending(path: Self.folderName(for: .now), directoryHint: .isDirectory)
            var video: WindowRecorder?
            if VideoRecording.isOn {
                let recorder = WindowRecorder()
                guard let filter = await recorder.pickWindow() else { return }
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try await recorder.start(filter: filter, url: folder.appending(path: "video.mp4"))
                } catch {
                    lastError = "The video did not start: \(error.localizedDescription)"
                    return
                }
                recorder.onFailure = { [weak self] error in
                    self?.lastError = "The video stopped: \(error.localizedDescription)"
                }
                video = recorder
            }
            start(models: models, folder: folder, video: video)
        }
    }

    private func start(models: AsrModels, folder: URL, video: WindowRecorder?) {
        guard stage == .prep else {
            Task { _ = await video?.stop() }
            return
        }
        let live = LiveTranscriber(models: models) { [weak self] chunk in
            Task { @MainActor in self?.chunks.append(chunk) }
        } onError: { [weak self] error in
            Task { @MainActor in self?.lastError = error.localizedDescription }
        }
        // The two sources start at different times (the first time, macOS asks for permission between
        // them). Keep the audio of both only from the moment both run, so the two tracks have one clock.
        let gate = Gate()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let micTrack = try TrackWriter(url: folder.appending(path: "me.caf"))
            let othersTrack = try TrackWriter(url: folder.appending(path: "others.caf"))
            try mic.start { [weak self] samples in
                guard gate.isOpen else { return }
                micTrack.append(samples)
                live.feed(samples, isMe: true)
                let level = level(of: samples)
                Task { @MainActor in self?.micLevel = level }
            }
            do {
                try systemAudio.start { [weak self] samples in
                    guard gate.isOpen else { return }
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
            Task {
                await live.finish()
                _ = await video?.stop()
            }
            return
        }
        gate.open()
        self.live = live
        self.video = video
        lastError = nil
        chunks = []
        participants = prep.participantList
        speakerMarks = []
        talkingPoints = prep.talkingPointList.enumerated().map { TalkingPoint(id: $0.offset, text: $0.element) }
        startedAt = .now
        stage = .recording
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
        micLevel = 0
        othersLevel = 0
        coach?.cancel()
        coach = nil
        stage = .processing
        self.live = nil
        let startedAt = startedAt ?? .now
        let duration = Date.now.timeIntervalSince(startedAt)
        let othersURL = tracks.last?.url
        tracks = []
        let video = video
        self.video = nil
        Task {
            let rawVideo = await video?.stop()
            await live.finish()
            var notes = MeetingNotes(
                startedAt: startedAt, duration: duration, agenda: prep.sections.agenda, prepNotes: prep.sections.notes,
                participants: prep.participantList, talkingPoints: talkingPoints, lines: []
            )
            var videoURL: URL?
            if let rawVideo, let videoStartedAt = video?.startedAt {
                let url = OutputFolder.url.appending(path: notes.baseName + ".mp4")
                do {
                    try FileManager.default.createDirectory(at: OutputFolder.url, withIntermediateDirectories: true)
                    try await MeetingVideo.align(
                        rawVideo, from: startedAt.timeIntervalSince(videoStartedAt), to: url)
                    try? FileManager.default.removeItem(at: rawVideo)
                    notes.videoFileName = url.lastPathComponent
                    videoURL = url
                } catch {
                    lastError = "The video was not saved: \(error.localizedDescription)"
                }
            }
            let others = chunks.filter { !$0.isMe }
            var segments: [FinalTranscript.SpeakerSegment] = []
            if !others.isEmpty, let othersURL {
                do {
                    segments = try await FinalTranscript.speakerSegments(of: othersURL)
                } catch {
                    lastError = "Speaker separation failed: \(error.localizedDescription)"
                }
            }
            let transcript = FinalTranscript.lines(chunks: chunks, otherSpeakers: segments)
            notes.lines = transcript.lines
            var suggestedNames = FinalTranscript.suggestedNames(
                marks: speakerMarks, segments: segments, labels: transcript.labels)
            var pictures: [String: NSImage] = [:]
            if let videoURL, !segments.isEmpty {
                pictures = await MeetingVideo.pictures(of: videoURL, segments: segments, labels: transcript.labels)
                if !notes.participants.isEmpty {
                    let sightings = await MeetingVideo.sightings(of: videoURL, segments: segments, participants: notes.participants)
                    suggestedNames = FinalTranscript.merged(
                        taps: suggestedNames,
                        video: FinalTranscript.suggestedNames(sightings: sightings, segments: segments, labels: transcript.labels))
                }
            }
            if notes.lines.isEmpty {
                notes.summaryProblem = "no speech was recorded"
            } else if !MeetingAssistant.isAvailable {
                notes.summaryProblem = "turn on Apple Intelligence"
            } else {
                do {
                    notes.summary = try await MeetingAssistant.summary(
                        of: notes.transcriptText, agenda: notes.agenda, prepNotes: notes.prepNotes,
                        participants: notes.participants)
                } catch {
                    notes.summaryProblem = error.localizedDescription
                }
            }
            save(notes, suggestedNames: suggestedNames, pictures: pictures)
        }
    }

    /// Writes the file at once, so it is never lost, then asks for the speakers' names.
    private func save(_ notes: MeetingNotes, suggestedNames: [String: String], pictures: [String: NSImage]) {
        let folder = OutputFolder.url
        let url = folder.appending(path: notes.fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try notes.markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "The notes were not saved: \(error.localizedDescription)"
            stage = .prep
            return
        }
        let speakers = notes.speakers.filter { $0 != FinalTranscript.me }.map { label in
            SpeakerNamesView.Speaker(
                label: label, firstWords: notes.lines.first { $0.speaker == label }?.text ?? "", picture: pictures[label])
        }
        stage = speakers.isEmpty
            ? .done(url)
            : .naming(NamingRequest(
                url: url, speakers: speakers, participants: notes.participants, suggestedNames: suggestedNames))
    }

    /// Puts the names in the file. No names keeps the numbers.
    func finishNaming(_ names: [String: String]) {
        guard case .naming(let request) = stage else { return }
        if !names.isEmpty, let markdown = try? String(contentsOf: request.url, encoding: .utf8) {
            try? MeetingNotes.renaming(markdown, names: names).write(to: request.url, atomically: true, encoding: .utf8)
        }
        stage = .done(request.url)
    }

    /// Back to the prep, which still has the last meeting's text.
    func newMeeting() {
        chunks = []
        participants = []
        speakerMarks = []
        talkingPoints = []
        startedAt = nil
        lastError = nil
        stage = .prep
    }

    /// You tapped a participant's name because they talk now.
    func markSpeaker(_ name: String) {
        guard stage == .recording, let startedAt else { return }
        speakerMarks.append(.init(name: name, time: Date.now.timeIntervalSince(startedAt)))
    }

    func toggle(_ point: TalkingPoint) {
        guard let index = talkingPoints.firstIndex(where: { $0.id == point.id }) else { return }
        talkingPoints[index].isCovered.toggle()
    }

    static func folderName(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
    }
}

/// Closed until both audio sources run.
private final class Gate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isOpen: Bool { state.withLock { $0 } }

    func open() { state.withLock { $0 = true } }
}
