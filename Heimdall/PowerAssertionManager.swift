import Foundation
import IOKit.pwr_mgt

/// Holds an IOKit power assertion for the whole app lifetime so the Mac never
/// idle-sleeps while Heimdall is running. This is the mechanism that actually
/// protects long-running SSH sessions — the lock overlay itself never touches
/// sleep/logout, it only blocks local interaction.
///
/// Known limitation: this cannot override lid-close (clamshell) sleep, which
/// is a firmware-level behavior unless an external display/keyboard/mouse and
/// power are attached.
final class PowerAssertionManager {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    func start() {
        guard !isActive else { return }
        let reason = "Heimdall keeps this Mac awake to protect active SSH sessions" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        isActive = (result == kIOReturnSuccess)
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        isActive = false
    }
}
