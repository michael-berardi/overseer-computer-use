import XCTest
@testable import OpenComputerUseKit

/// Snapshot cache TTL/LRU bounds, state_id freshness, and fail-before-mutation
/// semantics. Uses injected clocks and liveness checks; no real apps.
final class SnapshotCacheContractTests: XCTestCase {
    private func makeCache(
        policy: SnapshotCachePolicy = SnapshotCachePolicy(ttl: 15, capacity: 3),
        clock: MutableDateClock,
        alive: @escaping SnapshotCache.ProcessAliveCheck = { _ in true },
        window: @escaping SnapshotCache.WindowExistenceCheck = { _, _ in true }
    ) -> SnapshotCache {
        SnapshotCache(
            policy: policy,
            clock: { clock.now() },
            isProcessAlive: alive,
            windowExists: window
        )
    }

    func testCachePolicyDefaultsMatchContract() {
        XCTAssertEqual(SnapshotCachePolicy.defaultTTL, 15)
        XCTAssertEqual(SnapshotCachePolicy.defaultCapacity, 16)
        XCTAssertEqual(SnapshotCachePolicy.defaults.ttl, 15)
        XCTAssertEqual(SnapshotCachePolicy.defaults.capacity, 16)
    }

    func testCanonicalKeyIsPidScoped() {
        XCTAssertEqual(SnapshotCache.canonicalKey(for: makeContractSnapshot(pid: 123)), "pid:123")
    }

    func testFreshSnapshotIsReturnedThroughEveryAlias() {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)
        let snapshot = makeContractSnapshot()

        cache.store(snapshot, aliasKeys: ["contractapp", "dev.test.contract"])

        XCTAssertEqual(cache.snapshot(forKey: "contractapp")?.stateID, snapshot.stateID)
        XCTAssertEqual(cache.snapshot(forKey: "dev.test.contract")?.stateID, snapshot.stateID)
        XCTAssertEqual(cache.snapshot(forKey: "pid:\(snapshot.app.pid)")?.stateID, snapshot.stateID)
    }

    func testSnapshotExpiresAfterTTLAndIsEvicted() {
        let clock = MutableDateClock()
        let cache = makeCache(policy: SnapshotCachePolicy(ttl: 10, capacity: 3), clock: clock)

        cache.store(makeContractSnapshot(), aliasKeys: ["contractapp"])
        clock.advance(by: 10)
        XCTAssertNotNil(cache.snapshot(forKey: "contractapp"), "exactly at the TTL boundary is still fresh")

        clock.advance(by: 0.001)
        XCTAssertNil(cache.snapshot(forKey: "contractapp"))

        // Expiry evicted the entry, so even rewinding the clock cannot revive it.
        XCTAssertNil(cache.snapshot(forKey: "pid:4242"))
    }

    func testDeadProcessInvalidatesCachedSnapshot() {
        let clock = MutableDateClock()
        var alive = true
        let cache = makeCache(clock: clock, alive: { _ in alive })

        cache.store(makeContractSnapshot(), aliasKeys: ["contractapp"])
        XCTAssertNotNil(cache.snapshot(forKey: "contractapp"))

        alive = false
        XCTAssertNil(cache.snapshot(forKey: "contractapp"))
    }

    func testMissingWindowInvalidatesCachedSnapshot() {
        let clock = MutableDateClock()
        var windowPresent = true
        let cache = makeCache(clock: clock, window: { _, _ in windowPresent })

        cache.store(makeContractSnapshot(windowID: 99), aliasKeys: ["contractapp"])
        XCTAssertNotNil(cache.snapshot(forKey: "contractapp"))

        windowPresent = false
        XCTAssertNil(cache.snapshot(forKey: "contractapp"))
    }

    func testSnapshotWithoutWindowSkipsWindowExistenceCheck() {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock, window: { _, _ in false })

        cache.store(makeContractSnapshot(windowID: nil), aliasKeys: ["contractapp"])
        XCTAssertNotNil(cache.snapshot(forKey: "contractapp"))
    }

    func testLRUEvictsLeastRecentlyUsedBeyondCapacity() {
        let clock = MutableDateClock()
        let cache = makeCache(policy: SnapshotCachePolicy(ttl: 60, capacity: 2), clock: clock)

        cache.store(makeContractSnapshot(pid: 1, stateID: "a"), aliasKeys: ["a"])
        cache.store(makeContractSnapshot(pid: 2, stateID: "b"), aliasKeys: ["b"])
        // Touch "a" so "b" becomes the least recently used entry.
        XCTAssertNotNil(cache.snapshot(forKey: "a"))

        cache.store(makeContractSnapshot(pid: 3, stateID: "c"), aliasKeys: ["c"])

        XCTAssertNotNil(cache.snapshot(forKey: "a"))
        XCTAssertNil(cache.snapshot(forKey: "b"), "capacity 2 must evict the least recently used snapshot")
        XCTAssertNotNil(cache.snapshot(forKey: "c"))
    }

    func testRestoringSamePidReplacesEntryAndDropsStaleAliases() {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)

        cache.store(makeContractSnapshot(pid: 7, stateID: "old"), aliasKeys: ["old-alias"])
        cache.store(makeContractSnapshot(pid: 7, stateID: "new"), aliasKeys: ["new-alias"])

        XCTAssertNil(cache.snapshot(forKey: "old-alias"))
        XCTAssertEqual(cache.snapshot(forKey: "new-alias")?.stateID, "new")
    }

    func testRemoveAllClearsEveryAlias() {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)

        cache.store(makeContractSnapshot(), aliasKeys: ["contractapp"])
        cache.removeAll()

        XCTAssertNil(cache.snapshot(forKey: "contractapp"))
    }

    func testStateIDFormatIsPidWindowAndLowercaseUUID() {
        let withWindow = makeSnapshotStateID(pid: 123, windowID: 456)
        let components = withWindow.split(separator: ":")
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(components[0], "123")
        XCTAssertEqual(components[1], "456")
        XCTAssertEqual(components[2].count, 36)
        XCTAssertEqual(String(components[2]), String(components[2]).lowercased())
        XCTAssertNotNil(UUID(uuidString: String(components[2])))

        let withoutWindow = makeSnapshotStateID(pid: 123, windowID: nil)
        XCTAssertTrue(withoutWindow.hasPrefix("123:0:"))

        XCTAssertNotEqual(
            makeSnapshotStateID(pid: 123, windowID: 456),
            makeSnapshotStateID(pid: 123, windowID: 456),
            "each snapshot gets a unique state_id"
        )
    }

    func testSnapshotRenderedTextExposesStateIDLine() {
        let snapshot = makeContractSnapshot(stateID: "1:2:abc")
        let rendered = snapshot.renderedText(style: .fullState)

        XCTAssertTrue(rendered.contains("State-ID: 1:2:abc"))
    }

    func testRequireFreshStateReturnsMatchingSnapshot() throws {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)
        cache.store(makeContractSnapshot(stateID: "fresh-id"), aliasKeys: ["contractapp"])
        let service = ComputerUseService(snapshotCache: cache)

        let snapshot = try service.requireFreshState("fresh-id", for: "ContractApp")
        XCTAssertEqual(snapshot.stateID, "fresh-id")
    }

    func testRequireFreshStateRejectsStaleStateIDBeforeAnyMutation() {
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)
        cache.store(makeContractSnapshot(stateID: "current-id"), aliasKeys: ["contractapp"])
        let service = ComputerUseService(snapshotCache: cache)

        XCTAssertThrowsError(try service.requireFreshState("old-id", for: "ContractApp")) { error in
            guard case let ComputerUseError.staleState(message) = error else {
                return XCTFail("expected staleState, got \(error)")
            }
            XCTAssertEqual(
                message,
                "Snapshot state_id 'old-id' is stale for 'ContractApp'. Call get_app_state to refresh state_id."
            )
        }
    }

    func testRequireFreshStateFailsWhenNothingFreshIsCached() {
        let service = ComputerUseService(snapshotCache: makeCache(clock: MutableDateClock()))

        XCTAssertThrowsError(try service.requireFreshState("any", for: "Nowhere")) { error in
            guard case let ComputerUseError.stateUnavailable(message) = error else {
                return XCTFail("expected stateUnavailable, got \(error)")
            }
            XCTAssertEqual(message, "No fresh snapshot is cached for 'Nowhere'. Run get_app_state first.")
        }
    }

    func testActionWithStaleStateIDFailsBeforeResolvingOrMutating() {
        // The app name does not exist; if the state check did not run first we
        // would get appNotFound from resolution. staleState proves the action
        // failed before any app lookup or input simulation.
        let clock = MutableDateClock()
        let cache = makeCache(clock: clock)
        cache.store(makeContractSnapshot(stateID: "current-id"), aliasKeys: ["contractapp"])
        let service = ComputerUseService(snapshotCache: cache)

        XCTAssertThrowsError(
            try service.click(
                app: "ContractApp",
                elementIndex: "0",
                x: nil,
                y: nil,
                clickCount: 1,
                mouseButton: "left",
                stateID: "stale-id"
            )
        ) { error in
            guard case ComputerUseError.staleState = error else {
                return XCTFail("expected staleState, got \(error)")
            }
        }
    }

    func testActionWithUnknownCachedAppFailsBeforeResolution() {
        // Empty cache + supplied state_id: stateUnavailable must win over app
        // resolution, proving fail-before-mutation ordering.
        let service = ComputerUseService(snapshotCache: makeCache(clock: MutableDateClock()))

        XCTAssertThrowsError(
            try service.typeText(app: "no-such-app-contract-xyz", text: "hi", stateID: "any")
        ) { error in
            guard case ComputerUseError.stateUnavailable = error else {
                return XCTFail("expected stateUnavailable, got \(error)")
            }
        }
    }
}
