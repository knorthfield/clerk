import AVFoundation
import CoreAudio

/// Records the sound that all other apps play (the other people in the meeting) as 16 kHz mono samples.
/// It uses a Core Audio process tap. The first start shows the system's "System Audio Recording" prompt.
final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "Clerk.SystemAudioTap", qos: .userInitiated)

    /// `onSamples` gets each converted buffer on a background queue.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [try Self.ownProcessObject()])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID))

        do {
            var streamDescription = try Self.property(kAudioTapPropertyFormat, of: tapID, as: AudioStreamBasicDescription.self)
            guard let format = AVAudioFormat(streamDescription: &streamDescription),
                  let resampler = Resampler(from: format)
            else { throw SystemAudioTapError.unsupportedFormat }

            let outputUID = try Self.defaultOutputDeviceUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Clerk System Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID))
            try check(AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
                // The input also has the streams of the output device, if it has any (a headset's microphone).
                // The tap's stream comes after them.
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let tapBuffer = buffers.last else { return }
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: tapBuffer)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &list) else { return }
                onSamples(resampler.convert(buffer))
            })
            try check(AudioDeviceStart(deviceID, procID))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, procID)
            if let procID { AudioDeviceDestroyIOProcID(deviceID, procID) }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func ownProcessObject() throws -> AudioObjectID {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        ))
        return object
    }

    private static func defaultOutputDeviceUID() throws -> String {
        let device = try property(kAudioHardwarePropertyDefaultSystemOutputDevice,
                                  of: AudioObjectID(kAudioObjectSystemObject), as: AudioObjectID.self)
        return try property(kAudioDevicePropertyDeviceUID, of: device, as: CFString.self) as String
    }

    private static func property<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, as _: T.Type) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, value))
        return value.load(as: T.self)
    }
}

private func check(_ status: OSStatus) throws {
    guard status == noErr else { throw SystemAudioTapError.coreAudio(status) }
}

enum SystemAudioTapError: LocalizedError {
    case coreAudio(OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status): "System audio recording failed (Core Audio error \(status))."
        case .unsupportedFormat: "The system audio format is not supported."
        }
    }
}
