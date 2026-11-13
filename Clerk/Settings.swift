import FoundationModels
import SwiftUI

enum OutputFolder {
    private static let key = "outputFolder"

    static var url: URL {
        get {
            UserDefaults.standard.string(forKey: key).map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? URL.documentsDirectory.appending(path: "Clerk", directoryHint: .isDirectory)
        }
        set { UserDefaults.standard.set(newValue.path(percentEncoded: false), forKey: key) }
    }
}

struct SettingsView: View {
    let meeting: Meeting
    @State private var folder = OutputFolder.url
    @State private var isChoosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Save notes in") {
                    Menu {
                        Button("Choose…") { isChoosing = true }
                        Button("Show in Finder") { NSWorkspace.shared.open(folder) }
                    } label: {
                        Label {
                            Text(folder.lastPathComponent)
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path(percentEncoded: false)))
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Meeting Notes")
            } footer: {
                Text("One markdown file per meeting, in \(displayPath).")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Speech recognition") {
                    Text(meeting.modelStatus ?? "Ready")
                }
                LabeledContent("Summaries and talking points") {
                    if MeetingAssistant.isAvailable {
                        Text("Ready")
                    } else {
                        HStack {
                            Text(appleIntelligenceProblem)
                            if case .unavailable(.appleIntelligenceNotEnabled) = SystemLanguageModel.default.availability {
                                Button("Turn On…") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("On This Mac")
            } footer: {
                Text("Everything runs on your Mac. Your meetings do not go to the internet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            OutputFolder.url = url
            folder = url
        }
    }

    private var displayPath: String {
        folder.path(percentEncoded: false).replacing(URL.homeDirectory.path(percentEncoded: false), with: "~/")
    }

    private var appleIntelligenceProblem: String {
        switch SystemLanguageModel.default.availability {
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off"
        case .unavailable(.modelNotReady): "Apple Intelligence is getting ready"
        case .unavailable(.deviceNotEligible): "This Mac cannot use Apple Intelligence"
        default: "Not available"
        }
    }
}
