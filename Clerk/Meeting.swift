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
        /// The meeting's folder.
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
    /// The participants from Meeting Prep, to tap when one of them talks.
    private(set) var participants: [String] = []
    private(set) var speakerMarks: [FinalTranscript.SpeakerMark] = []

    @ObservationIgnored private let prep: Prep
    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private let systemAudio = SystemAudioTap()
    @ObservationIgnored private var tracks: [TrackWriter] = []
    /// The meeting's folder in the output folder: the recordings, then the notes.
    @ObservationIgnored private var folder: URL?

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

    /// Downloads the model on first use (about 600 MB), then loads it from the cache.
    func loadModel() {
        modelState = .loading(0)
        Task {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .ultra) { progress in
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
        guard canStart else { return }
        Task {
            // Ask first: if the system prompt shows while the audio engine starts, the app stops responding.
            await Permissions.requestMicrophone()
            guard Permissions.hasMicrophone else {
                lastError = "Clerk needs the microphone. Allow it in System Settings › Privacy & Security."
                return
            }
            startRecording()
        }
    }

    /// Only records: Clerk transcribes the tracks after the meeting.
    private func startRecording() {
        guard stage == .prep else { return }
        let now = Date.now
        let folder = Self.newFolder(
            named: MeetingNotes.folderName(startedAt: now, agenda: prep.sections.agenda), in: OutputFolder.url)
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
                let level = level(of: samples)
                Task { @MainActor in self?.micLevel = level }
            }
            do {
                try systemAudio.start { [weak self] samples in
                    guard gate.isOpen else { return }
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
        gate.open()
        lastError = nil
        participants = prep.participantList
        speakerMarks = []
        talkingPoints = prep.talkingPointList.enumerated().map { TalkingPoint(id: $0.offset, text: $0.element) }
        self.folder = folder
        startedAt = now
        stage = .recording
    }

    func stop() {
        guard stage == .recording, case .ready(let models) = modelState, let folder else { return }
        mic.stop()
        systemAudio.stop()
        micLevel = 0
        othersLevel = 0
        stage = .processing
        let startedAt = startedAt ?? .now
        let duration = Date.now.timeIntervalSince(startedAt)
        for track in tracks { track.close() }
        let urls = tracks.map(\.url)
        tracks = []
        Task {
            var notes = MeetingNotes(
                startedAt: startedAt, duration: duration, agenda: prep.sections.agenda, prepNotes: prep.sections.notes,
                participants: prep.participantList, talkingPoints: talkingPoints, lines: []
            )
            var chunks: [Chunk] = []
            do {
                for (url, isMe) in zip(urls, [true, false]) {
                    if let chunk = try await TrackTranscriber.chunk(of: url, isMe: isMe, models: models) { chunks.append(chunk) }
                }
            } catch {
                lastError = "Transcription failed: \(error.localizedDescription). The recordings are in \(folder.path)."
            }
            var segments: [FinalTranscript.SpeakerSegment] = []
            if chunks.contains(where: { !$0.isMe }), let othersURL = urls.last {
                do {
                    segments = try await FinalTranscript.speakerSegments(of: othersURL)
                } catch {
                    lastError = "Speaker separation failed: \(error.localizedDescription)"
                }
            }
            let transcript = FinalTranscript.lines(chunks: chunks, otherSpeakers: segments)
            notes.lines = transcript.lines
            let suggestedNames = FinalTranscript.suggestedNames(
                marks: speakerMarks, segments: segments, labels: transcript.labels)
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
            for url in urls {
                do {
                    try TrackWriter.compress(url)
                } catch {
                    lastError = "The recording \(url.lastPathComponent) was not compressed: \(error.localizedDescription)"
                }
            }
            save(notes, in: folder, suggestedNames: suggestedNames)
        }
    }

    /// Writes the files at once, so they are never lost, then asks for the speakers' names.
    private func save(_ notes: MeetingNotes, in folder: URL, suggestedNames: [String: String]) {
        do {
            try notes.summaryMarkdown.write(to: folder.appending(path: MeetingNotes.summaryFile), atomically: true, encoding: .utf8)
            try notes.transcriptMarkdown.write(to: folder.appending(path: MeetingNotes.transcriptFile), atomically: true, encoding: .utf8)
            try notes.prepMarkdown?.write(to: folder.appending(path: MeetingNotes.prepFile), atomically: true, encoding: .utf8)
        } catch {
            lastError = "The notes were not saved: \(error.localizedDescription)"
            stage = .prep
            return
        }
        let speakers = notes.speakers.filter { $0 != FinalTranscript.me }.map { label in
            SpeakerNamesView.Speaker(label: label, firstWords: notes.lines.first { $0.speaker == label }?.text ?? "")
        }
        stage = speakers.isEmpty
            ? .done(folder)
            : .naming(NamingRequest(
                url: folder, speakers: speakers, participants: notes.participants, suggestedNames: suggestedNames))
    }

    /// Puts the names in the summary and the transcript. No names keeps the numbers.
    func finishNaming(_ names: [String: String]) {
        guard case .naming(let request) = stage else { return }
        if !names.isEmpty {
            for file in [MeetingNotes.summaryFile, MeetingNotes.transcriptFile] {
                let url = request.url.appending(path: file)
                guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { continue }
                try? MeetingNotes.renaming(markdown, names: names).write(to: url, atomically: true, encoding: .utf8)
            }
        }
        stage = .done(request.url)
    }

    /// A folder that does not exist yet: "name", else "name 2", "name 3"…
    nonisolated static func newFolder(named name: String, in parent: URL) -> URL {
        var folder = parent.appending(path: name, directoryHint: .isDirectory)
        var number = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appending(path: "\(name) \(number)", directoryHint: .isDirectory)
            number += 1
        }
        return folder
    }

    /// Back to the prep, which still has the last meeting's text.
    func newMeeting() {
        folder = nil
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

}

/// Closed until both audio sources run.
private final class Gate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isOpen: Bool { state.withLock { $0 } }

    func open() { state.withLock { $0 = true } }
}
