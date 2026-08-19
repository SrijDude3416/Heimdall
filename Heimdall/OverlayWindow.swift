import AppKit
import SwiftUI

/// One of these is created per connected NSScreen while locked. Sits at
/// .screenSaver level (above normal app windows, the Dock, and the menu bar),
/// joins every Space so switching Spaces can't escape it, and captures all
/// mouse/keyboard input (ignoresMouseEvents = false).
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, lockController: LockController) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        isMovable = false
        setFrame(screen.frame, display: true)

        let hostingView = NSHostingView(rootView: LockView(lockController: lockController))
        hostingView.frame = CGRect(origin: .zero, size: screen.frame.size)
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
