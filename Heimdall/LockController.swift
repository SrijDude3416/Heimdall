import AppKit
import Combine

enum LockEngageReason {
    case manual
    case restoredAfterRelaunch
}

/// Central .locked / .unlocked state machine. The only class that touches
/// NSApp.presentationOptions, creates/destroys OverlayWindows, and drives
/// EventTapManager's locked/unlocked mode.
final class LockController: NSObject, ObservableObject {
    @Published private(set) var isLocked = false
    @Published var lastErrorMessage: String?
    @Published private(set) var isAuthenticating = false

    var eventTapManager: EventTapManager?

    private let stateStore: StateStore
    private let authManager = AuthManager()
    private var overlayWindows: [OverlayWindow] = []
    private var screenObserver: NSObjectProtocol?

    // Bumped on every engageLock(). Captured by unlock() at call time and
    // checked when its async result arrives, so a completion from a stale
    // lock cycle (e.g. one superseded by a fresh lock/unlock in between)
    // can never mutate state for a cycle it no longer belongs to.
    private var lockGeneration = 0

    // True for the duration of engageLock()/completeUnlock()'s synchronous
    // body. Setting presentationOptions changes each screen's visibleFrame,
    // which can synchronously re-enter our own screen-change observer before
    // that body has finished — this blocks the reentrant reconcile from
    // running at a moment when overlayWindows doesn't yet reflect reality,
    // which previously created and orphaned a duplicate window.
    private var isTransitioningLockState = false

    init(stateStore: StateStore) {
        self.stateStore = stateStore
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileOverlayWindows()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func lock() {
        engageLock(reason: .manual)
    }

    func engageLock(reason: LockEngageReason) {
        guard !isLocked else { return }
        isTransitioningLockState = true
        defer { isTransitioningLockState = false }

        isLocked = true
        lastErrorMessage = nil
        lockGeneration += 1
        HeimdallLog.lock.notice("engageLock: generation \(self.lockGeneration, privacy: .public)")
        stateStore.save(HeimdallState(isLocked: true, lockedAt: Date()))

        // AppKit's "disable" kiosk options (disableProcessSwitching,
        // disableForceQuit, etc.) are only valid when paired with at least
        // one hide/auto-hide option — presentationOptions with just the
        // disable-* set alone throws an uncaught NSException and crashes
        // (confirmed: EXC_CRASH/SIGABRT, -[NSException raise] from this
        // exact assignment). .autoHideDock (rather than .hideDock) is used
        // so the Dock still exists as a consistent, standard fixture — it
        // tucks away and reveals on hover, rather than the app's own Dock
        // icon flickering in and out per lock state as it did before.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [
            .autoHideDock,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableAppleMenu
        ]

        eventTapManager?.setLocked(true)
        buildOverlayWindows()

        // Exactly one automatic silent Touch ID attempt per lock, triggered
        // here rather than from SwiftUI's onAppear — onAppear on a view
        // hosted in a manually-managed NSWindow can fire more than once,
        // which was invalidating and restarting the auth session repeatedly.
        unlock()
    }

    /// Always starts a fresh attempt, even if one is already in flight —
    /// AuthManager cancels and supersedes any prior in-flight evaluation, so
    /// a tap on Unlock can never be permanently swallowed by a stuck earlier
    /// attempt (isAuthenticating is UI-only feedback, not a hard gate here).
    func unlock() {
        guard isLocked else {
            HeimdallLog.lock.notice("unlock() ignored: not locked")
            return
        }
        let generation = lockGeneration
        HeimdallLog.lock.notice("unlock() called, generation \(generation, privacy: .public)")
        isAuthenticating = true
        lastErrorMessage = nil
        authManager.authenticate(reason: "Unlock Heimdall") { [weak self] result in
            guard let self else { return }
            guard generation == self.lockGeneration else {
                HeimdallLog.lock.notice("unlock() result for stale generation \(generation, privacy: .public), ignoring")
                return
            }
            self.isAuthenticating = false
            switch result {
            case .success:
                HeimdallLog.lock.notice("unlock() succeeded, generation \(generation, privacy: .public)")
                self.completeUnlock()
            case .cancelled:
                HeimdallLog.lock.notice("unlock() cancelled, generation \(generation, privacy: .public)")
            case .failure(let message):
                HeimdallLog.lock.notice("unlock() failed, generation \(generation, privacy: .public): \(message, privacy: .public)")
                self.lastErrorMessage = message
            }
        }
    }

    private var isTerminationAuthorized = false

    /// The single gate for *every* quit path — Cmd+Q, AppleScript `quit`,
    /// selecting Heimdall in the Force Quit dialog, Dock — since all of them
    /// funnel through NSApplicationDelegate.applicationShouldTerminate(_:)
    /// before AppKit actually tears the app down. Authenticating here, rather
    /// than only in the status-item menu's own Quit action, is what makes
    /// quitting impossible to bypass regardless of how it's triggered.
    func authorizeTermination(completion: @escaping (Bool) -> Void) {
        if isTerminationAuthorized {
            completion(true)
            return
        }
        authManager.authenticate(reason: "Quit Heimdall") { [weak self] result in
            if case .success = result {
                self?.isTerminationAuthorized = true
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    private func completeUnlock() {
        isTransitioningLockState = true
        defer { isTransitioningLockState = false }

        isLocked = false
        lastErrorMessage = nil
        stateStore.save(HeimdallState(isLocked: false, lockedAt: nil))
        NSApp.presentationOptions = []
        eventTapManager?.setLocked(false)
        destroyOverlayWindows()
    }

    private func buildOverlayWindows() {
        overlayWindows = NSScreen.screens.map { OverlayWindow(screen: $0, lockController: self) }
        HeimdallLog.lock.notice("buildOverlayWindows: created \(self.overlayWindows.count, privacy: .public) window(s)")
        overlayWindows.first?.makeKeyAndOrderFront(nil)
        for window in overlayWindows.dropFirst() {
            window.orderFrontRegardless()
        }
    }

    private func destroyOverlayWindows() {
        HeimdallLog.lock.notice("destroyOverlayWindows: tearing down \(self.overlayWindows.count, privacy: .public) window(s)")
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
    }

    /// NSApplication.didChangeScreenParametersNotification fires for any
    /// change to a screen's visibleFrame — including our own
    /// presentationOptions toggling the Dock/menu bar, which does NOT change
    /// screen.frame (what our overlay windows are actually sized to). Only
    /// react when the real number of connected displays changed; otherwise
    /// this handler can re-enter engageLock()/completeUnlock() mid-flight
    /// and orphan a window that's still on screen but no longer tracked.
    private func reconcileOverlayWindows() {
        guard isLocked, !isTransitioningLockState else { return }
        guard NSScreen.screens.count != overlayWindows.count else { return }
        HeimdallLog.lock.notice("reconcileOverlayWindows: screen count changed \(self.overlayWindows.count, privacy: .public) -> \(NSScreen.screens.count, privacy: .public)")
        destroyOverlayWindows()
        buildOverlayWindows()
    }
}
