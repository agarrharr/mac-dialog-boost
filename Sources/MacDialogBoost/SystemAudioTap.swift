import CoreAudio
import Foundation

/// Captures everything the Mac is playing (except this process) and exposes it as the input
/// side of a private aggregate device whose output side is the current speakers/headphones.
///
/// The tap starts unmuted: without the System Audio Recording permission it delivers silence,
/// and muting at that point would silence the whole Mac. Call `setMuted(true)` once real audio
/// is arriving.
final class SystemAudioTap {
    private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateID = AudioDeviceID(kAudioObjectUnknown)
    private let description: CATapDescription
    let outputDevice: AudioDeviceID
    let outputName: String
    let sampleRate: Double

    init() throws {
        let output = try defaultOutputDevice()
        outputDevice = output
        let outputUID = try readString(output, kAudioDevicePropertyDeviceUID)
        outputName = (try? readString(output, kAudioObjectPropertyName)) ?? outputUID

        let me = try ownProcessObject()
        let exclude = me == kAudioObjectUnknown ? [] : [me]
        description = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        description.uuid = UUID()
        description.name = "Dialog Boost"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating the system audio tap")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dialog Boost",
            kAudioAggregateDeviceUIDKey: "mac-dialog-boost-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        do {
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Creating the audio routing device")
            sampleRate = try readProperty(aggregateID, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    /// Mutes (or restores) the original sound of everything being tapped.
    func setMuted(_ muted: Bool) throws {
        description.muteBehavior = muted ? .muted : .unmuted
        var addr = address(kAudioTapPropertyDescription)
        var value = Unmanaged.passUnretained(description).toOpaque()
        try check(
            AudioObjectSetPropertyData(tapID, &addr, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &value),
            muted ? "Muting the original audio" : "Unmuting the original audio"
        )
    }

    var isMuted: Bool {
        var addr = address(kAudioTapPropertyDescription)
        var value: Unmanaged<CATapDescription>?
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        guard AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &value) == noErr, let value else { return false }
        return value.takeRetainedValue().muteBehavior != .unmuted
    }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioDeviceID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { invalidate() }
}
