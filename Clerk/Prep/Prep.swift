import Foundation
import Observation

/// What you prepare before a meeting: one markdown text in the format of `PrepTemplate`.
/// It is kept until you change it, and copied into the meeting file.
@MainActor @Observable
final class Prep {
    var text = PrepTemplate.blank { didSet { save() } }

    @ObservationIgnored private let folder: URL?

    /// `folder` nil keeps the prep in memory only (for tests).
    init(folder: URL? = Meeting.storageFolder) {
        self.folder = folder
        guard let folder else { return }
        if let saved = try? String(contentsOf: folder.appending(path: "prep.md"), encoding: .utf8) {
            text = saved
        } else if let old = Self.version1Prep(in: folder) {
            text = old
        }
    }

    /// The sections of the text. Text without the template's headings is all prep notes.
    var sections: PrepTemplate.Sections {
        PrepTemplate.sections(of: text) ?? PrepTemplate.Sections(notes: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var talkingPointList: [String] { Self.lines(of: sections.talkingPoints) }
    var participantList: [String] { Self.lines(of: sections.participants) }

    func reset() {
        text = PrepTemplate.blank
    }

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

    /// Version 1.0 kept four boxes in prep.json. Turn them into one text.
    private static func version1Prep(in folder: URL) -> String? {
        struct Saved: Codable {
            var notes, agenda, talkingPoints: String
            var participants: String?
        }
        guard let data = try? Data(contentsOf: folder.appending(path: "prep.json")),
              let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return nil }
        return PrepTemplate.text(of: PrepTemplate.Sections(
            participants: saved.participants ?? "", agenda: saved.agenda,
            talkingPoints: saved.talkingPoints, notes: saved.notes
        ))
    }

    private func save() {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.write(to: folder.appending(path: "prep.md"), atomically: true, encoding: .utf8)
    }
}
