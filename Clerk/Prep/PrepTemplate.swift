import Foundation

/// The recommended format of a meeting prep. Fill it in yourself, or give it to an AI assistant,
/// then paste it back: each section goes into its box in Meeting Prep.
enum PrepTemplate {
    static let blank = """
        # Meeting prep

        ## Participants
        <!-- One name per line, as people say it. -->
        -

        ## Agenda
        <!-- One item per line, in order. -->
        -

        ## Talking points
        <!-- One point per line: what you must raise, ask or agree. Click each one in the panel when you cover it. -->
        -

        ## Prep notes
        <!-- Background, numbers, links, and what you want from the meeting. -->

        """

    /// Copy this to an AI assistant: the instructions, then your prep so far.
    static func aiPrompt(with prep: String) -> String {
        """
        Help me prepare for a meeting. Ask me about the meeting first if you need more information \
        (who is coming, the purpose, what I want from it). Then fill in the template below; keep what I \
        already wrote. Keep the headings exactly as they are. In Participants, Agenda and Talking points, \
        put one short item per line. Keep talking points short and specific, so that I can see quickly if \
        we covered them. Answer with only the filled template, in one markdown code block.

        \(prep)
        """
    }

    /// A filled template with these sections.
    static func text(of sections: Sections) -> String {
        """
        # Meeting prep

        ## Participants
        \(sections.participants)

        ## Agenda
        \(sections.agenda)

        ## Talking points
        \(sections.talkingPoints)

        ## Prep notes
        \(sections.notes)

        """
    }

    struct Sections: Equatable {
        var participants = ""
        var agenda = ""
        var talkingPoints = ""
        var notes = ""
    }

    /// Reads a filled template. Nil if the text has none of the template's headings.
    /// Text under other headings, or before the first heading, goes into the prep notes.
    static func sections(of markdown: String) -> Sections? {
        let text = markdown
            .replacing(/<!--[\s\S]*?-->/, with: "")
            .replacing(/^```[a-z]*$/.anchorsMatchLineEndings(), with: "")
        var sections = Sections()
        var found = false
        var current = \Sections.notes
        var extra: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: /#{1,3}\s+(.+?)\s*/) {
                switch match.1.lowercased() {
                case "participants", "attendees": current = \.participants; found = true; continue
                case "agenda": current = \.agenda; found = true; continue
                case "talking points": current = \.talkingPoints; found = true; continue
                case "prep notes", "notes": current = \.notes; found = true; continue
                case "meeting prep": continue
                default: current = \.notes; extra.append(String(line)); continue
                }
            }
            // An empty list item from the blank template.
            if line.trimmingCharacters(in: .whitespaces) == "-" { continue }
            if current == \.notes { extra.append(String(line)) } else { sections[keyPath: current] += line + "\n" }
        }
        guard found else { return nil }
        sections.notes = extra.joined(separator: "\n")
        for keyPath in [\Sections.participants, \.agenda, \.talkingPoints, \.notes] {
            sections[keyPath: keyPath] = sections[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sections
    }
}
