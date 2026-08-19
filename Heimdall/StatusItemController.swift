import AppKit
import Combine
import SwiftUI

/// Owns the menu-bar item — the guaranteed lock trigger (the global hotkey is
/// a bonus that only works once Input Monitoring is granted). While locked,
/// the real menu bar stays technically present (not hidden via
/// presentationOptions) but is fully covered, visually and interactively, by
/// the .screenSaver-level overlay window sitting above it — so this item is
/// unreachable during a lock regardless, same practical effect.
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem
    private let lockController: LockController
    private var onboardingWindow: NSWindow?
    private var lockObserver: AnyCancellable?

    init(lockController: LockController) {
        self.lockController = lockController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()

        // Repeatedly toggling NSApp.presentationOptions' .hideMenuBar across
        // lock/unlock cycles is observed to occasionally leave the status
        // item glitched/invisible in SystemUIServer even though the app
        // itself is otherwise fine. Rebuilding it fresh whenever we return
        // to unlocked reliably restores it, rather than leaving the user
        // with no way back into the app until a manual relaunch.
        lockObserver = lockController.$isLocked
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.rebuildStatusItem() }
    }

    private func rebuildStatusItem() {
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Heimdall")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Lock Now", action: #selector(lockNow), keyEquivalent: "l")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Setup Guide…", action: #selector(showOnboarding), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Heimdall", action: #selector(quit), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu
    }

    @objc private func lockNow() {
        lockController.lock()
    }

    @objc private func quit() {
        // Routes through NSApp.terminate -> AppDelegate.applicationShouldTerminate,
        // which is the single authenticated gate for every quit path.
        NSApp.terminate(nil)
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                onInstallLaunchAgent: { [weak self] in self?.confirmAndInstallLaunchAgent() },
                onUninstallLaunchAgent: { LaunchAgentInstaller.uninstall() }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Heimdall Setup"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func confirmAndInstallLaunchAgent() {
        let alert = NSAlert()
        alert.messageText = "Install Auto-Restart Helper?"
        alert.informativeText = "This adds a LaunchAgent at ~/Library/LaunchAgents/\(LaunchAgentInstaller.label).plist "
            + "that relaunches Heimdall automatically if it's ever force-quit while locked. You can remove it later "
            + "from this same Setup window."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LaunchAgentInstaller.install()
    }
}
