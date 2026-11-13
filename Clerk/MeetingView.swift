import SwiftUI

/// Two halves: notes on the left, the coach on the right.
struct MeetingView: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 0) {
            NotesHalf(meeting: meeting)
            Divider().padding(.vertical, 16)
            CoachHalf(meeting: meeting)
        }
        .frame(width: MainWindow.panelSize.width, height: MainWindow.panelSize.height)
        // Solid enough to read over any window, and still glass at the edge.
        .background(.thickMaterial, in: .rect(cornerRadius: 24))
        .glassEffect(.clear, in: .rect(cornerRadius: 24))
    }
}

private struct NotesHalf: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                if let startedAt = meeting.startedAt {
                    Text(startedAt, style: .timer).monospacedDigit()
                }
                Spacer()
                // A borderless panel never becomes active, so system buttons look disabled. Draw it ourselves.
                Button { meeting.stop() } label: {
                    Text("Stop").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.red, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .font(.headline)
            HStack(spacing: 16) {
                LevelBar(label: "Me", level: meeting.micLevel)
                LevelBar(label: "Others", level: meeting.othersLevel)
            }
            if !meeting.participants.isEmpty {
                SpeakerButtons(meeting: meeting)
            }
            LiveTranscript(chunks: meeting.chunks.suffix(20))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LevelBar: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            GeometryReader { geometry in
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.green).frame(width: geometry.size.width * CGFloat(level))
                    }
            }
            .frame(height: 4)
            .animation(.linear(duration: 0.1), value: level)
        }
    }
}

/// Tap a participant when they talk. After the meeting, Clerk uses the taps to fill in their names.
private struct SpeakerButtons: View {
    let meeting: Meeting

    var body: some View {
        let lastName = meeting.speakerMarks.last?.name
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(meeting.participants, id: \.self) { name in
                    let isLast = name == lastName
                    // The panel never becomes active, so draw the buttons ourselves (see Stop).
                    Button { meeting.markSpeaker(name) } label: {
                        Text(name).font(.caption.weight(.medium))
                            .foregroundStyle(isLast ? .white : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(isLast ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help("\(name) is talking now")
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// The newest text at the bottom, like a chat.
private struct LiveTranscript: View {
    let chunks: ArraySlice<Chunk>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if chunks.isEmpty {
                    Text("Listening… the text shows about 15 seconds after it is said.")
                        .foregroundStyle(.secondary)
                }
                ForEach(chunks) { chunk in
                    Text("\(Text(chunk.isMe ? "Me" : "Others").bold()) \(chunk.text)")
                        .foregroundStyle(chunk.isMe ? .secondary : .primary)
                        .id(chunk.id)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
    }
}

private struct CoachHalf: View {
    let meeting: Meeting

    private var open: [TalkingPoint] { meeting.talkingPoints.filter { !$0.isCovered } }
    private var covered: [TalkingPoint] { meeting.talkingPoints.filter(\.isCovered) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Talking points").font(.headline)
                Spacer()
                if !meeting.talkingPoints.isEmpty {
                    Text("\(covered.count) of \(meeting.talkingPoints.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if meeting.talkingPoints.isEmpty {
                Text("Add talking points in Meeting Prep, and Clerk ticks them off as you cover them.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !MeetingAssistant.isAvailable {
                Text("Turn on Apple Intelligence to tick points automatically. Click a point to tick it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(open + covered) { point in
                        PointRow(point: point) { meeting.toggle(point) }
                    }
                }
                .animation(.snappy, value: meeting.talkingPoints)
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PointRow: View {
    let point: TalkingPoint
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: point.isCovered ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(point.isCovered ? .green : .secondary)
                Text(point.text)
                    .foregroundStyle(point.isCovered ? .secondary : .primary)
                    .strikethrough(point.isCovered, color: .secondary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(point.isCovered ? "Mark as not covered" : "Mark as covered")
    }
}
