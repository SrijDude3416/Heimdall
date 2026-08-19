import AppKit
import CoreGraphics

/// Session-level CGEventTap: the supplementary hardening layer beyond
/// NSApplication.presentationOptions. While locked it swallows the keyboard
/// escape hatches (Spotlight, App Switcher, Force Quit, Quit, Close, Hide,
/// Minimize, Mission Control) before WindowServer/Dock/Spotlight ever see
/// them. It also watches for the global lock hotkey at all times.
///
/// Requires the user to grant Accessibility + Input Monitoring in System
/// Settings; Heimdall cannot grant these itself.
final class EventTapManager {
    weak var lockController: LockController?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isLockedMode = false

    func setLocked(_ locked: Bool) {
        isLockedMode = locked
    }

    func start() {
        guard CGPreflightListenEventAccess() else { return }
        installTap()
    }

    /// Call when the app becomes active again — permissions can be revoked
    /// or granted at any time from System Settings while Heimdall runs.
    func recheckPermissions() {
        guard eventTap == nil, CGPreflightListenEventAccess() else { return }
        installTap()
    }

    private func installTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // WindowServer disables a tap that doesn't return promptly; re-arm
        // immediately or the hardening layer silently disappears.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if HotkeyRouter.matches(flags: flags, keyCode: keyCode) {
            DispatchQueue.main.async { [weak self] in
                self?.lockController?.lock()
            }
            return nil
        }

        if isLockedMode, isEscapeHatchCombo(flags: flags, keyCode: keyCode) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // Standard ANSI virtual key codes.
    private func isEscapeHatchCombo(flags: CGEventFlags, keyCode: Int64) -> Bool {
        let cmd = flags.contains(.maskCommand)
        let cmdOpt = cmd && flags.contains(.maskAlternate)
        let ctrl = flags.contains(.maskControl)

        switch keyCode {
        case 49 where cmd: return true    // Cmd+Space — Spotlight
        case 48 where cmd: return true    // Cmd+Tab — App Switcher
        case 53 where cmdOpt: return true // Cmd+Opt+Esc — Force Quit
        case 12 where cmd: return true    // Cmd+Q — Quit
        case 13 where cmd: return true    // Cmd+W — Close
        case 4 where cmd: return true     // Cmd+H — Hide
        case 46 where cmd: return true    // Cmd+M — Minimize
        case 126 where ctrl: return true  // Ctrl+Up — Mission Control
        case 125 where ctrl: return true  // Ctrl+Down — App Exposé
        default: return false
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
