import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let what: String
    let status: OSStatus

    init(_ what: String, _ status: OSStatus) {
        self.what = what
        self.status = status
    }

    var description: String { "\(what) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ what: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(what(), status) }
}

func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
    var addr = address(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "Reading audio property \(selector)")
    return value
}

func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "Reading audio string \(selector)")
    guard let value else { throw CoreAudioError("Reading audio string \(selector)", -1) }
    return value.takeRetainedValue() as String
}

func defaultOutputDevice() throws -> AudioDeviceID {
    try readProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(kAudioObjectUnknown))
}

/// Calls `handler` on the main queue whenever the Mac's sound output changes (picked in Control
/// Center, AirPlay/Screen Mirroring started, HDMI or headphones plugged in…).
func onDefaultOutputChange(_ handler: @escaping () -> Void) {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in handler() }
}

/// The Core Audio object for this process, so the tap can leave our own (processed) output alone.
func ownProcessObject() throws -> AudioObjectID {
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pid = getpid()
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object),
        "Looking up this process in Core Audio"
    )
    return object
}
