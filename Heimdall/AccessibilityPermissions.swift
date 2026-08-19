import AppKit
import ApplicationServices

/// Wraps the two TCC permission checks Heimdall relies on for its hardening
/// layer (the session-level CGEventTap). Neither can be granted
/// programmatically — the user must do it in System Settings.
enum AccessibilityPermissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system's native "grant Accessibility access" prompt if not
    /// already trusted. Safe to call repeatedly; the prompt only appears once
    /// per unapproved app until the user acts on it.
    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
