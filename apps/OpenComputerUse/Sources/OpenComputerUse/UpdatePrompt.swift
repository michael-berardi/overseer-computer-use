import AppKit
import Foundation
import OpenComputerUseKit

@MainActor
enum NativeUpdatePrompt {
    static func checkAtLaunch() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let updater = OverseerUpdater()
        updater.checkLatest { result in
            guard case let .success(release) = result,
                  isNewer(release.tagName, than: resolvedOpenComputerUseVersion()) else { return }
            Task { @MainActor in
                if updater.installAutomatically {
                    updater.downloadAndInstall(release: release, automatic: true) { result in
                        guard case .success = result else { return }
                        Task { @MainActor in NSApp.terminate(nil) }
                    }
                } else {
                    present(release: release, updater: updater)
                }
            }
        }
    }

    private static func present(release: OverseerRelease, updater: OverseerUpdater) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "A stable Overseer Computer Use update is ready"
        alert.informativeText = "Version \(release.tagName) is available. Updates are checked once per day and are verified before replacing this app."
        alert.addButton(withTitle: "Update now")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Install updates automatically")
        let automatic = NSButton(checkboxWithTitle: "Allow verified updates to install automatically", target: nil, action: nil)
        automatic.state = updater.installAutomatically ? .on : .off
        alert.accessoryView = automatic

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            updater.downloadAndInstall(release: release, automatic: false) { result in
                Task { @MainActor in
                    if case .failure = result {
                        let error = NSAlert()
                        error.alertStyle = .warning
                        error.messageText = "Update was not installed"
                        error.informativeText = "The downloaded app did not pass checksum, Developer ID, bundle, team, designated-requirement, or notarization checks. Your existing app is unchanged."
                        error.runModal()
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        case .alertThirdButtonReturn:
            updater.installAutomatically = true
            updater.downloadAndInstall(release: release, automatic: true) { result in
                Task { @MainActor in
                    if case .success = result { NSApp.terminate(nil) }
                }
            }
        default:
            updater.installAutomatically = automatic.state == .on
        }
    }

    private static func isNewer(_ raw: String, than current: String) -> Bool {
        func components(_ value: String) -> [Int] {
            value.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        }
        let candidate = components(raw)
        let installed = components(current)
        return candidate.lexicographicallyPrecedes(installed) == false && candidate != installed
    }
}
