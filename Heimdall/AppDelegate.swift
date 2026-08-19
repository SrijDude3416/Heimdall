import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let powerAssertionManager = PowerAssertionManager()
    private let stateStore = StateStore()
    private let eventTapManager = EventTapManager()
    private lazy var lockController = LockController(stateStore: stateStore)
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular (Dock-visible) activation policy is the default and is
        // never changed — Heimdall stays a permanent Dock fixture whether
        // locked or unlocked, rather than flickering in and out as it did
        // when this toggled between .accessory and .regular per lock state.
        powerAssertionManager.start()

        lockController.eventTapManager = eventTapManager
        eventTapManager.lockController = lockController

        statusItemController = StatusItemController(lockController: lockController)

        AccessibilityPermissions.requestAccessibilityIfNeeded()
        eventTapManager.start()

        // If Heimdall was killed while locked, re-engage the overlay
        // immediately on relaunch — never show any unlocked UI first.
        // Otherwise, launching the app at all (Dock, Finder, `open`) engages
        // the lock screen — that's the app's entire purpose, so opening it
        // should never just silently sit in the background.
        //
        // Deferred to the next run loop turn rather than called inline here:
        // engageLock() calls NSApp.activate/presentationOptions, which
        // synchronously round-trips to WindowServer — calling that from
        // inside applicationDidFinishLaunching itself, before the run loop
        // is pumping, reliably deadlocks the app (observed: process alive,
        // 0% CPU, stuck forever on the very next line).
        let shouldRestoreLock = stateStore.load().isLocked
        DispatchQueue.main.async { [lockController] in
            if shouldRestoreLock {
                lockController.engageLock(reason: .restoredAfterRelaunch)
            } else {
                lockController.lock()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        eventTapManager.recheckPermissions()
    }

    /// Clicking the Dock icon while Heimdall is already running (no visible
    /// windows to reopen, since the overlay only exists while locked) engages
    /// the lock screen, same as a fresh launch or "Lock Now".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lockController.lock()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerAssertionManager.stop()
    }

    /// The universal quit gate. Every termination path — Cmd+Q's
    /// automatically-installed menu binding, AppleScript `quit`, the Force
    /// Quit dialog, Dock — calls NSApp.terminate(_:), which always invokes
    /// this delegate method first. Gating here (rather than only in the
    /// status-item menu's own Quit action) is what makes quitting impossible
    /// to bypass, since no quit path skips this check.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lockController.authorizeTermination { authorized in
            NSApp.reply(toApplicationShouldTerminate: authorized)
        }
        return .terminateLater
    }
}
