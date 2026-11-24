import SwiftUI

/// The window shows one stage of the meeting at a time.
struct ContentView: View {
    let meeting: Meeting
    let prep: Prep
    let setMeetingMode: (Bool) -> Void

    var body: some View {
        Group {
            switch meeting.stage {
            case .prep:
                PrepScreen(meeting: meeting, prep: prep)
            case .recording:
                MeetingView(meeting: meeting)
            case .processing:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Writing the meeting notes…").font(.headline)
                    Text("Clerk writes the transcript, finds who spoke when, then writes the summary.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .naming(let request):
                SpeakerNamesView(
                    speakers: request.speakers, participants: request.participants,
                    suggestedNames: request.suggestedNames
                ) { names in
                    meeting.finishNaming(names)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let url):
                NotesView(url: url) { meeting.newMeeting() }
            }
        }
        .onChange(of: meeting.isRecording) { _, isRecording in setMeetingMode(isRecording) }
    }
}

private struct PrepScreen: View {
    let meeting: Meeting
    let prep: Prep

    var body: some View {
        VStack(spacing: 0) {
            PrepView(prep: prep)
            Divider()
            HStack(spacing: 12) {
                if let error = meeting.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).lineLimit(2)
                } else if let status = meeting.modelStatus {
                    Text(status).foregroundStyle(.secondary)
                }
                if meeting.modelFailed {
                    Button("Try Again") { meeting.loadModel() }
                }
                Spacer()
                let count = prep.talkingPointList.count
                Text(count == 1 ? "1 talking point" : "\(count) talking points").foregroundStyle(.secondary)
                Button("Start Meeting") { meeting.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!meeting.canStart)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
