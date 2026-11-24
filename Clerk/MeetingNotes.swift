import Foundation

/// Everything that goes into the meeting's markdown files.
struct MeetingNotes {
    var startedAt: Date
    var duration: TimeInterval
    var agenda: String
    var prepNotes: String
    var participants: [String] = []
    var talkingPoints: [TalkingPoint]
    var lines: [Line]
    var summary: MeetingAssistant.Summary?
    /// Why there is no summary, if there is none.
    var summaryProblem: String?

    /// The title that Apple Intelligence wrote with the summary, else "Meeting".
    var title: String { summary.flatMap { Self.cleanTitle($0.title) } ?? "Meeting" }

    var speakers: [String] {
        var seen: Set<String> = []
        return lines.map(\.speaker).filter { seen.insert($0).inserted }
    }

    /// The meeting's folder in the output folder: the date and time ("2026-11-13 1405") while it records,
    /// then with the title from the summary ("2026-11-13 1405 Q3 budget review"). Like Daisy's
    /// `MeetingTitle`: the app's own name first, the model's title when there is one.
    static func folderName(startedAt: Date, title: String? = nil) -> String {
        let date = startedAt.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", timeZone: .current, calendar: .current))
        guard let title else { return date }
        return "\(date) \(title.replacing(/[\/:\\]/, with: "-"))"
    }

    /// The folder name with the summary's title, or nil without one.
    var titledFolderName: String? {
        summary.flatMap { Self.cleanTitle($0.title) }.map { Self.folderName(startedAt: startedAt, title: $0) }
    }

    /// The model's title made fit for a heading and a folder name: one line, no wrapping quotes, no
    /// closing period, at most 60 characters (cut at a word). Nil when nothing is left.
    static func cleanTitle(_ text: String) -> String? {
        var title = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        title = title.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’«».")))
        if title.count > 60 {
            let cut = title.prefix(60)
            title = String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut)
        }
        return title.isEmpty ? nil : title
    }

    static let summaryFile = "summary.md"
    static let transcriptFile = "transcript.md"
    static let prepFile = "prep.md"

    /// Summary, decisions, action items and talking points.
    var summaryMarkdown: String {
        var out: [String] = []
        let date = startedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
        out.append("# \(title)")
        out.append("\(date) · \(Int((duration / 60).rounded())) min" + (speakers.isEmpty ? "" : " · \(speakers.joined(separator: ", "))"))
        out.append("## Summary")
        out.append(summary?.summary ?? "_Summary not available: \(summaryProblem ?? "no speech was recorded")._")
        if let decisions = summary?.decisions, !decisions.isEmpty {
            out.append("## Decisions")
            out.append(decisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let items = summary?.actionItems, !items.isEmpty {
            out.append("## Action items")
            out.append(items.map { "- [ ] **\($0.owner)** — \($0.task)" }.joined(separator: "\n"))
        }
        if !talkingPoints.isEmpty {
            out.append("## Talking points")
            out.append(talkingPoints.map { "- [\($0.isCovered ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// Participants, agenda and prep notes. Nil if the prep was empty.
    var prepMarkdown: String? {
        var out: [String] = []
        if !participants.isEmpty {
            out.append("## Participants")
            out.append(participants.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !agenda.isEmpty {
            out.append("## Agenda")
            out.append(agenda)
        }
        if !prepNotes.isEmpty {
            out.append("## Prep notes")
            out.append(prepNotes)
        }
        guard !out.isEmpty else { return nil }
        return (["# \(title): prep"] + out).joined(separator: "\n\n") + "\n"
    }

    /// The transcript with front matter, like HushScribe's: each turn is the speaker and the clock time,
    /// then the text.
    var transcriptMarkdown: String {
        let quotedSpeakers = speakers.map { "\"\($0)\"" }.joined(separator: ", ")
        var out = """
            ---
            type: meeting
            created: "\(Self.format(startedAt, "yyyy-MM-dd"))"
            time: "\(Self.format(startedAt, "HH:mm"))"
            duration: "\(Self.duration(duration))"
            attendees: [\(quotedSpeakers)]
            ---

            # \(title): \(Self.format(startedAt, "yyyy-MM-dd HH:mm"))

            ## Transcript


            """
        out += lines.isEmpty
            ? "_No speech was recorded._"
            : lines.map { "**\($0.speaker)** (\(Self.format(startedAt.addingTimeInterval($0.start), "HH:mm:ss")))\n\($0.text)" }
                .joined(separator: "\n\n")
        return out + "\n"
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// "18:42", or "1:02:05" from one hour.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The transcript as the language model reads it.
    var transcriptText: String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    /// Replaces numbered speaker labels with names, everywhere in the file.
    static func renaming(_ markdown: String, names: [String: String]) -> String {
        var result = markdown
        for (label, name) in names where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            let number = label.replacing("Speaker ", with: "")
            result = result.replacing(try! Regex("\\bSpeaker \(number)\\b"), with: name.trimmingCharacters(in: .whitespaces))
        }
        return result
    }
}
