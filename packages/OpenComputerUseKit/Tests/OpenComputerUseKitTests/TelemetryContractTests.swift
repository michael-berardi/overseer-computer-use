import Foundation
import XCTest
@testable import OpenComputerUseKit

final class TelemetryContractTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "telemetry-contract-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testNoPayloadOrSendBeforeOptIn() throws {
        let store = TelemetryStore(defaults: makeDefaults())
        var sent = 0
        let coordinator = TelemetryCoordinator(store: store, sender: { _, _, completion in sent += 1; completion(true) })
        coordinator.recordToolResult(toolName: "click", succeeded: true)
        coordinator.start()
        XCTAssertEqual(store.consent, .undecided)
        XCTAssertNil(store.installID)
        XCTAssertEqual(sent, 0)
    }

    func testDeclinePersistsAndDisableDeletesIdentifierAndCounters() throws {
        let store = TelemetryStore(defaults: makeDefaults())
        store.decline()
        XCTAssertEqual(store.consent, .declined)
        XCTAssertNil(store.installID)
        _ = store.optIn()
        store.addUsage { $0.record(toolName: "click", succeeded: true) }
        XCTAssertNotNil(store.installID)
        store.disable()
        XCTAssertEqual(store.consent, .declined)
        XCTAssertNil(store.installID)
        XCTAssertTrue(store.usage().isEmpty)
        XCTAssertNil(store.lastHeartbeatDay())
    }

    func testPayloadContainsOnlyV2AllowlistedKeys() throws {
        let store = TelemetryStore(defaults: makeDefaults())
        _ = store.optIn()
        var usage = TelemetryUsage()
        usage.record(toolName: "get_app_state", succeeded: false)
        let payload = TelemetryPayload(event: .usage, installId: store.installID!, version: "1.2.3", platform: .macos, arch: .arm64, day: "2026-08-16", usage: usage, batchId: "550e8400-e29b-41d4-a716-446655440000")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "app", "event", "installId", "version", "platform", "arch", "day", "batchId", "usage"])
        XCTAssertEqual(object["batchId"] as? String, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertNil(object["osVersion"])
        XCTAssertNil(object["sentAt"])
        let usageObject = try XCTUnwrap(object["usage"] as? [String: Any])
        XCTAssertEqual(Set(usageObject.keys).count, 27)
        XCTAssertNil(usageObject["toolName"])
        XCTAssertNil(usageObject["arguments"])
    }
    func testBatchIDIsUsageOnly() throws {
        let store = TelemetryStore(defaults: makeDefaults())
        _ = store.optIn()
        let launch = TelemetryPayload(event: .launch, installId: store.installID!, version: "1", platform: .macos, arch: .arm64, day: "2026-08-16", batchId: "550e8400-e29b-41d4-a716-446655440000")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(launch)) as? [String: Any])
        XCTAssertNil(object["batchId"])
        let usage = TelemetryPayload(event: .usage, installId: store.installID!, version: "1", platform: .macos, arch: .arm64, day: "2026-08-16")
        let usageObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(usage)) as? [String: Any])
        let batchId = try XCTUnwrap(usageObject["batchId"] as? String)
        XCTAssertEqual(batchId, batchId.lowercased())
        XCTAssertEqual(batchId.count, 36)
        XCTAssertEqual(Array(batchId)[14], "4")
    }

    func testLaunchAndHeartbeatCadence() {
        let defaults = makeDefaults()
        let store = TelemetryStore(defaults: defaults)
        _ = store.optIn()
        var current = Date(timeIntervalSince1970: 1_755_321_600)
        var sentEvents: [String] = []
        let coordinator = TelemetryCoordinator(store: store, now: { current }, sender: { _, body, completion in
            let object = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            sentEvents.append(object["event"] as! String)
            completion(true)
        })
        coordinator.start()
        coordinator.start()
        XCTAssertEqual(sentEvents, ["launch", "heartbeat", "launch"])
        current.addTimeInterval(86_400)
        coordinator.recordToolResult(toolName: "click", succeeded: true)
        coordinator.start()
        XCTAssertEqual(sentEvents, ["launch", "heartbeat", "launch", "launch", "heartbeat", "usage"])
    }

    func testFailedDeliveryKeepsImmutableUsageBatchForRetry() throws {
        let store = TelemetryStore(defaults: makeDefaults())
        _ = store.optIn()
        store.addUsage { $0.record(toolName: "click", succeeded: true) }
        var bodies: [[String: Any]] = []
        var current = Date(timeIntervalSince1970: 1_755_321_600)
        let coordinator = TelemetryCoordinator(
            store: store,
            now: { current },
            sender: { _, body, completion in
                bodies.append(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
                completion(false)
            }
        )
        coordinator.start()
        let firstBatch = try XCTUnwrap(store.inFlightUsageBatch())
        store.addUsage { $0.record(toolName: "click", succeeded: true) }
        current.addTimeInterval(86_400)
        coordinator.start()
        let usageBodies = bodies.filter { $0["event"] as? String == "usage" }
        XCTAssertEqual(usageBodies.count, 2)
        XCTAssertEqual(usageBodies[0]["batchId"] as? String, firstBatch.batchId)
        XCTAssertEqual(usageBodies[1]["batchId"] as? String, firstBatch.batchId)
        XCTAssertNotEqual(usageBodies[0]["day"] as? String, usageBodies[1]["day"] as? String)
        XCTAssertEqual((usageBodies[0]["usage"] as? [String: Any])?["toolSuccessClick"] as? Int, 1)
        XCTAssertEqual((usageBodies[1]["usage"] as? [String: Any])?["toolSuccessClick"] as? Int, 1)
        XCTAssertFalse(store.usage().isEmpty)
        XCTAssertNil(store.lastUsageDay())
    }

    func testUnknownToolCannotCreateCounter() {
        var usage = TelemetryUsage()
        usage.record(toolName: "user-supplied-name", succeeded: true)
        XCTAssertTrue(usage.isEmpty)
    }

    func testTelemetryCLIRequiresExplicitActionAndNeverUsesAppAgent() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["telemetry", "status"]),
            .telemetry(.status)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["telemetry", "enable"]),
            .telemetry(.enable)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["telemetry", "disable"]),
            .telemetry(.disable)
        )
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["telemetry"]))
        XCTAssertFalse(
            shouldUseMacOSAppAgentProxy(
                command: .telemetry(.disable),
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            )
        )
    }
}
