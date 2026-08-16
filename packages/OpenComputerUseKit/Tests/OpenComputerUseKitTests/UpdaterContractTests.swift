import Foundation
import XCTest
@testable import OpenComputerUseKit

final class UpdaterContractTests: XCTestCase {
    func testReleaseMetadataRequiresStableSemverAndExpectedAsset() throws {
        let json = """
        {"tag_name":"v1.2.3","name":"Overseer Computer Use","draft":false,"prerelease":false,"assets":[{"name":"Overseer-Computer-Use.zip","browser_download_url":"https://example.invalid/release.zip","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(OverseerRelease.self, from: json)
        XCTAssertTrue(release.isStable)
        XCTAssertEqual(release.assets.first?.name, OverseerUpdater.assetName)
    }

    func testPreferencesCheckAtMostOncePerUtcDay() {
        let suite = "updater-contract-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = OverseerUpdatePreferences(defaults: defaults)
        XCTAssertTrue(prefs.shouldCheck(on: "2026-08-16"))
        prefs.markChecked(on: "2026-08-16")
        XCTAssertFalse(prefs.shouldCheck(on: "2026-08-16"))
        XCTAssertTrue(prefs.shouldCheck(on: "2026-08-17"))
    }
    func testPendingUpdateMarkerOnlyConfirmsMatchingBundleVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("updater-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Overseer Computer Use.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let info: [String: Any] = [
            "CFBundleIdentifier": PermissionSupport.bundleIdentifier,
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
        ]
        try (info as NSDictionary).write(to: infoURL)

        let markerURL = OverseerUpdater.pendingUpdateMarkerURL(for: appURL)
        let marker: [String: String] = [
            "bundleIdentifier": PermissionSupport.bundleIdentifier,
            "shortVersion": "2.0.0",
            "bundleVersion": "2",
        ]
        try JSONSerialization.data(withJSONObject: marker).write(to: markerURL)
        let backupURL = appURL.deletingLastPathComponent().appendingPathComponent(appURL.lastPathComponent + ".previous")
        try Data("rollback".utf8).write(to: backupURL)

        OverseerUpdater.confirmSuccessfulLaunch(currentBundleURL: appURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

        let matchingAppURL = root.appendingPathComponent("Matching.app", isDirectory: true)
        let matchingContentsURL = matchingAppURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: matchingContentsURL, withIntermediateDirectories: true)
        let matchingInfo: [String: Any] = [
            "CFBundleIdentifier": PermissionSupport.bundleIdentifier,
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "2",
        ]
        try (matchingInfo as NSDictionary).write(to: matchingContentsURL.appendingPathComponent("Info.plist"))
        let matchingMarkerURL = OverseerUpdater.pendingUpdateMarkerURL(for: matchingAppURL)
        try JSONSerialization.data(withJSONObject: marker).write(to: matchingMarkerURL)
        let matchingBackupURL = matchingAppURL.deletingLastPathComponent().appendingPathComponent(matchingAppURL.lastPathComponent + ".previous")
        try Data("rollback".utf8).write(to: matchingBackupURL)
        OverseerUpdater.confirmSuccessfulLaunch(currentBundleURL: matchingAppURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: matchingBackupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: matchingMarkerURL.path))
    }


    func testUpdateRequirementsStayStable() {
        XCTAssertEqual(PermissionSupport.bundleIdentifier, "com.libertydesignstudio.overseer-computer-use")
        XCTAssertEqual(OverseerUpdater.releasesURL.absoluteString, "https://api.github.com/repos/michael-berardi/overseer-computer-use/releases/latest")
    }
}
