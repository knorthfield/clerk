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
    @State private var folder = OutputFolder.url
    @State private var isChoosing = false

    var body: some View {
        Form {
            LabeledContent("Meeting notes folder") {
                HStack {
                    Text(folder.path(percentEncoded: false).replacing(URL.homeDirectory.path(percentEncoded: false), with: "~/"))
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { isChoosing = true }
                    Button("Show") { NSWorkspace.shared.open(folder) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            OutputFolder.url = url
            folder = url
        }
    }
}
