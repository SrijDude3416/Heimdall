import CoreGraphics

/// Defines the global "lock now" hotkey. Matching happens inside
/// EventTapManager's callback, reusing the single session-level CGEventTap
/// rather than standing up a second, separately-permissioned mechanism.
enum HotkeyRouter {
    /// Control+Option+Command+L
    static let requiredFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    static let keyCode: Int64 = 37 // 'L'

    static func matches(flags: CGEventFlags, keyCode: Int64) -> Bool {
        flags.contains(requiredFlags) && keyCode == Self.keyCode
    }
}
