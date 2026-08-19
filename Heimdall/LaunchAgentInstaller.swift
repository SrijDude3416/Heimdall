import Foundation

/// Installs/removes a LaunchAgent that relaunches Heimdall if it's ever
/// force-killed (e.g. via Activity Monitor) while locked. The plist is
/// generated at install time (rather than shipped as a static resource) so it
/// always points at wherever this build of Heimdall actually lives.
///
/// Uses `/usr/bin/open -a` rather than execing the bundle's binary directly —
/// launching via LaunchServices is what makes TCC attribute Accessibility /
/// Input Monitoring grants to the Heimdall app bundle on relaunch, instead of
/// to some other process.
///
/// Never called automatically; only in response to an explicit, confirmed
/// user action (see OnboardingView / StatusItemController).
enum LaunchAgentInstaller {
    static let label = "com.srija.Heimdall"

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @discardableResult
    static func install() -> Bool {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive"
        ]

        do {
            let dir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } catch {
            return false
        }

        return runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
    }

    @discardableResult
    static func uninstall() -> Bool {
        let ok = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
        return ok
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
