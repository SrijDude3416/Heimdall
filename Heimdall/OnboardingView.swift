import SwiftUI
import CoreGraphics

struct OnboardingView: View {
    let onInstallLaunchAgent: () -> Void
    let onUninstallLaunchAgent: () -> Void

    @State private var accessibilityGranted = AccessibilityPermissions.isAccessibilityTrusted()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var launchAgentInstalled = LaunchAgentInstaller.isInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heimdall Setup")
                .font(.title2).bold()

            Text("Heimdall needs these two permissions to block escape shortcuts (Cmd+Tab, Spotlight, Force Quit) while locked. Without them, the lock overlay still works, just with fewer of these shortcuts suppressed.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(title: "Accessibility", granted: accessibilityGranted) {
                AccessibilityPermissions.openAccessibilitySettings()
            }
            permissionRow(title: "Input Monitoring", granted: inputMonitoringGranted) {
                AccessibilityPermissions.openInputMonitoringSettings()
            }

            Divider()

            Text("Optionally install a background helper so Heimdall automatically restarts if it's ever force-quit while locked.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if launchAgentInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Remove") {
                        onUninstallLaunchAgent()
                        launchAgentInstalled = LaunchAgentInstaller.isInstalled
                    }
                } else {
                    Button("Install Auto-Restart Helper…") {
                        onInstallLaunchAgent()
                        launchAgentInstalled = LaunchAgentInstaller.isInstalled
                    }
                }
            }

            Spacer()

            Button("Refresh Status") {
                accessibilityGranted = AccessibilityPermissions.isAccessibilityTrusted()
                inputMonitoringGranted = CGPreflightListenEventAccess()
                launchAgentInstalled = LaunchAgentInstaller.isInstalled
            }
        }
        .padding(24)
        .frame(width: 440, height: 380)
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            Button(granted ? "Granted" : "Open Settings", action: action)
                .disabled(granted)
        }
    }
}
