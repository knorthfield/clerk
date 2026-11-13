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
        .frame(width: MeetingPanel.size.width, height: MeetingPanel.size.height)
        .glassEffect(in: .rect(cornerRadius: 24))
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
                Button("Stop") { meeting.stop() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .font(.headline)
            LevelBar(label: "Me", level: meeting.micLevel)
            LevelBar(label: "Others", level: meeting.othersLevel)
            Spacer()
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
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
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
