import XCTest
@testable import OpenComputerUseKit

/// Headless fixture-mode snapshots: the fixture bridge is file-driven, so a
/// fabricated fixture descriptor exercises the snapshot pipeline (state_id,
/// element records, no screenshot) without any app, permission, or display.
/// The shared fixture state file is always removed after each test.
final class FixtureSnapshotContractTests: XCTestCase {
    private func withFixtureState<T>(
        _ state: FixtureAppState,
        _ body: () throws -> T
    ) throws -> T {
        try FixtureBridge.writeState(state)
        defer {
            try? FileManager.default.removeItem(at: FixtureBridge.stateFileURL)
        }
        return try body()
    }

    private func fixtureDescriptor(pid: pid_t = 9_001) -> RunningAppDescriptor {
        RunningAppDescriptor(
            name: FixtureBridge.appName,
            bundleIdentifier: "dev.opencodex.opencomputeruse.fixture",
            pid: pid,
            runningApplication: NSRunningApplication.current
        )
    }

    private func makeState() -> FixtureAppState {
        FixtureAppState(
            processIdentifier: 9_001,
            windowTitle: "Fixture Window",
            windowBounds: FixtureRect(rect: CGRect(x: 0, y: 0, width: 400, height: 300)),
            focusedIdentifier: "ok-button",
            elements: [
                FixtureElementState(
                    identifier: "ok-button",
                    index: 1,
                    role: "AXButton",
                    title: "OK",
                    value: nil,
                    actions: ["AXPress"],
                    frame: FixtureRect(rect: CGRect(x: 10, y: 10, width: 80, height: 24))
                ),
            ]
        )
    }

    func testFixtureSnapshotBuildsWithoutPermissionsAppsOrDisplays() throws {
        try withFixtureState(makeState()) {
            let snapshot = try SnapshotBuilder.build(for: fixtureDescriptor())

            XCTAssertTrue(snapshot.mode == .fixture)
            XCTAssertNil(snapshot.screenshotPNGData)
            XCTAssertNil(snapshot.screenshotPixelSize)
            XCTAssertEqual(snapshot.windowTitle, "Fixture Window")
            XCTAssertEqual(snapshot.elements[1]?.identifier, "ok-button")
        }
    }

    func testFixtureSnapshotExposesUniqueStateID() throws {
        try withFixtureState(makeState()) {
            let first = try SnapshotBuilder.build(for: fixtureDescriptor())
            let second = try SnapshotBuilder.build(for: fixtureDescriptor())

            XCTAssertFalse(first.stateID.isEmpty)
            XCTAssertTrue(first.stateID.hasPrefix("9001:0:"), "fixture snapshots have no window: \(first.stateID)")
            XCTAssertNotEqual(first.stateID, second.stateID, "each snapshot gets a fresh state_id")
            XCTAssertTrue(first.renderedText.contains("State-ID: \(first.stateID)"))
        }
    }

    func testFixtureSnapshotResultOmitsScreenshotButCarriesStateID() throws {
        try withFixtureState(makeState()) {
            // The service-level result shape: text only, state_id at the top
            // level, never an image item when no screenshot was captured.
            let snapshot = try SnapshotBuilder.build(for: fixtureDescriptor())
            let service = ComputerUseService(snapshotCache: SnapshotCache())
            let result = service.snapshotResult(for: snapshot, style: .fullState)

            XCTAssertEqual(result.content.count, 1)
            XCTAssertEqual(result.content[0].dictionary["type"] as? String, "text")
            XCTAssertEqual(result.stateID, snapshot.stateID)
            XCTAssertEqual(result.asDictionary["state_id"] as? String, snapshot.stateID)
        }
    }
}
