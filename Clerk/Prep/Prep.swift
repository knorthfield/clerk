import Foundation
import Observation

/// What you prepare before a meeting. It is kept until you change it, and copied into the meeting file.
@MainActor @Observable
final class Prep {
    var notes = "" { didSet { save() } }
    var agenda = "" { didSet { save() } }
    var talkingPoints = "" { didSet { save() } }
    var participants = "" { didSet { save() } }

    @ObservationIgnored private let url: URL?

    private struct Saved: Codable {
        var notes, agenda, talkingPoints: String
        var participants: String?
    }

    /// `url` nil keeps the prep in memory only (for tests).
    init(url: URL? = Meeting.storageFolder.appending(path: "prep.json")) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return }
        notes = saved.notes
        agenda = saved.agenda
        talkingPoints = saved.talkingPoints
        participants = saved.participants ?? ""
    }

    /// Puts each section of a filled template into its box. False if the text is not a template.
    func fill(fromTemplate markdown: String) -> Bool {
        guard let sections = PrepTemplate.sections(of: markdown) else { return false }
        participants = sections.participants
        agenda = sections.agenda
        talkingPoints = sections.talkingPoints
        notes = sections.notes
        return true
    }

    func clear() {
        _ = fill(fromTemplate: "## Agenda")
    }

    var talkingPointList: [String] { Self.lines(of: talkingPoints) }
    var participantList: [String] { Self.lines(of: participants) }

    /// One item per line. List markers (`-`, `*`, `•`, `1.`, `1)`, `[ ]`) and empty lines are removed.
    nonisolated static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let item = line
                .replacing(/^\s*([-*•+]|\d+[.)])\s*/, with: "")
                .replacing(/^\[[ xX]?\]\s*/, with: "")
                .trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    private func save() {
        guard let url else { return }
        let saved = Saved(notes: notes, agenda: agenda, talkingPoints: talkingPoints, participants: participants)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }
}
