import Foundation

/// Everything that goes into the meeting's markdown file.
struct MeetingNotes {
    var startedAt: Date
    var duration: TimeInterval
    var agenda: String
    var prepNotes: String
    var talkingPoints: [TalkingPoint]
    var lines: [Line]
    var summary: MeetingAssistant.Summary?
    /// Why there is no summary, if there is none.
    var summaryProblem: String?

    var title: String { Prep.lines(of: agenda).first ?? "Meeting" }

    var speakers: [String] {
        var seen: Set<String> = []
        return lines.map(\.speaker).filter { seen.insert($0).inserted }
    }

    var fileName: String {
        let date = startedAt.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", timeZone: .current, calendar: .current))
        let safeTitle = title.replacing(/[\/:\\]/, with: "-").prefix(60)
        return "\(date) \(safeTitle).md"
    }

    var markdown: String {
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
        if !agenda.isEmpty {
            out.append("## Agenda")
            out.append(agenda)
        }
        if !prepNotes.isEmpty {
            out.append("## Prep notes")
            out.append(prepNotes)
        }
        out.append("## Transcript")
        out.append(lines.isEmpty ? "_No speech was recorded._" : lines.map { "**\($0.speaker)** [\(Self.time($0.start))]: \($0.text)" }.joined(separator: "\n\n"))
        return out.joined(separator: "\n\n") + "\n"
    }

    /// The transcript as the language model reads it.
    var transcriptText: String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
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
