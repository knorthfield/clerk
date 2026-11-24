import AVFoundation
import ScreenCaptureKit

/// Records one window that you pick (the meeting app) to a video file, with the sound of both sides.
/// The system's window picker gives Clerk access to that window only, so Clerk does not need the
/// Screen Recording permission.
@MainActor
final class WindowRecorder: NSObject {
    private var picked: CheckedContinuation<PickedWindow?, Never>?
    private var started: CheckedContinuation<Void, Error>?
    private var finished: CheckedContinuation<Void, Never>?
    private var isFinished = false
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private(set) var url: URL?
    private(set) var startedAt: Date?
    /// The video stopped before the meeting did (for example, the window closed).
    var onFailure: ((Error) -> Void)?

    /// Shows the system's window picker. Nil if you cancel.
    func pickWindow() async -> SCContentFilter? {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        if let id = Bundle.main.bundleIdentifier { configuration.excludedBundleIDs = [id] }
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        let window = await withCheckedContinuation { continuation in
            picked = continuation
            picker.present()
        }
        picker.remove(self)
        picker.isActive = false
        return window?.filter
    }

    /// The picker's filter is not Sendable, but only the main actor uses it after the picker.
    private struct PickedWindow: @unchecked Sendable {
        let filter: SCContentFilter
    }

    /// Returns when the first frame is in the file.
    func start(filter: SCContentFilter, url: URL) async throws {
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        var width = filter.contentRect.width * scale
        var height = filter.contentRect.height * scale
        if width > 1920 {
            height = height * 1920 / width
            width = 1920
        }
        // Even sizes: the HEVC encoder needs them.
        configuration.width = max(Int(width) / 2 * 2, 2)
        configuration.height = max(Int(height) / 2 * 2, 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = true

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .hevc
        if #available(macOS 27.0, *) { recording.mixesAudioWithMicrophone = true }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.output = output
        self.url = url
        try await withCheckedThrowingContinuation { continuation in
            started = continuation
            stream.startCapture { error in
                guard let error else { return }
                Task { @MainActor in self.fail(error) }
            }
        }
    }

    /// Stops and returns the file, if it has video.
    func stop() async -> URL? {
        guard let stream else { return nil }
        try? await stream.stopCapture()
        if !isFinished {
            await withCheckedContinuation { finished = $0 }
        }
        self.stream = nil
        output = nil
        return startedAt == nil ? nil : url
    }

    private func fail(_ error: Error) {
        if let started {
            self.started = nil
            started.resume(throwing: error)
        } else if !isFinished {
            onFailure?(error)
        }
        finish()
    }

    private func finish() {
        isFinished = true
        finished?.resume()
        finished = nil
    }
}

extension WindowRecorder: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            picked?.resume(returning: nil)
            picked = nil
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let window = PickedWindow(filter: filter)
        Task { @MainActor in
            picked?.resume(returning: window)
            picked = nil
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            picked?.resume(returning: nil)
            picked = nil
        }
    }
}

extension WindowRecorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in fail(error) }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            startedAt = .now
            started?.resume()
            started = nil
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in fail(error) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in finish() }
    }
}
