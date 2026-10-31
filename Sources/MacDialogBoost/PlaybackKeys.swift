import AppKit
import CoreGraphics

/// Controls whatever video is playing by sending the same events as the keyboard's media keys.
/// macOS requires Accessibility permission for the app this runs in (e.g. Terminal) to send them.
enum PlaybackKeys {
    /// Whether we're allowed to send key events; asks macOS to show the permission prompt if not.
    @discardableResult
    static func requestPermission() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    static var hasPermission: Bool { CGPreflightPostEventAccess() }

    /// The ⏯ media key: browsers and the TV app route it to the video that's playing, even full screen.
    static func playPause() {
        postMediaKey(16)  // NX_KEYTYPE_PLAY
    }

    /// The ← key in the front window: YouTube and most web players jump back a few seconds.
    static func back() {
        postKey(123)  // kVK_LeftArrow
    }

    /// The → key in the front window: jumps forward a few seconds.
    static func forward() {
        postKey(124)  // kVK_RightArrow
    }

    private static func postMediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: (key << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}
