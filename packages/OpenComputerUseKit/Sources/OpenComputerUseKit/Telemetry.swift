import Foundation
import Darwin

/// The only consent states persisted by Overseer Computer Use.
public enum TelemetryConsent: String, Codable, Sendable {
    case undecided
    case optedIn
    case declined
}

/// Fixed counters for the nine Computer Use tools. These names are deliberately
/// closed and stable; no client-provided tool name can reach the wire.
public struct TelemetryUsage: Codable, Equatable, Sendable {
    public var toolEnumListApps = 0
    public var toolSuccessListApps = 0
    public var toolErrorListApps = 0
    public var toolEnumGetAppState = 0
    public var toolSuccessGetAppState = 0
    public var toolErrorGetAppState = 0
    public var toolEnumClick = 0
    public var toolSuccessClick = 0
    public var toolErrorClick = 0
    public var toolEnumPerformSecondaryAction = 0
    public var toolSuccessPerformSecondaryAction = 0
    public var toolErrorPerformSecondaryAction = 0
    public var toolEnumScroll = 0
    public var toolSuccessScroll = 0
    public var toolErrorScroll = 0
    public var toolEnumDrag = 0
    public var toolSuccessDrag = 0
    public var toolErrorDrag = 0
    public var toolEnumTypeText = 0
    public var toolSuccessTypeText = 0
    public var toolErrorTypeText = 0
    public var toolEnumPressKey = 0
    public var toolSuccessPressKey = 0
    public var toolErrorPressKey = 0
    public var toolEnumSetValue = 0
    public var toolSuccessSetValue = 0
    public var toolErrorSetValue = 0

    public init() {}

    public var isEmpty: Bool { self == Self() }
    public mutating func add(_ other: TelemetryUsage) {
        toolEnumListApps = min(toolEnumListApps + other.toolEnumListApps, 1_000_000)
        toolSuccessListApps = min(toolSuccessListApps + other.toolSuccessListApps, 1_000_000)
        toolErrorListApps = min(toolErrorListApps + other.toolErrorListApps, 1_000_000)
        toolEnumGetAppState = min(toolEnumGetAppState + other.toolEnumGetAppState, 1_000_000)
        toolSuccessGetAppState = min(toolSuccessGetAppState + other.toolSuccessGetAppState, 1_000_000)
        toolErrorGetAppState = min(toolErrorGetAppState + other.toolErrorGetAppState, 1_000_000)
        toolEnumClick = min(toolEnumClick + other.toolEnumClick, 1_000_000)
        toolSuccessClick = min(toolSuccessClick + other.toolSuccessClick, 1_000_000)
        toolErrorClick = min(toolErrorClick + other.toolErrorClick, 1_000_000)
        toolEnumPerformSecondaryAction = min(toolEnumPerformSecondaryAction + other.toolEnumPerformSecondaryAction, 1_000_000)
        toolSuccessPerformSecondaryAction = min(toolSuccessPerformSecondaryAction + other.toolSuccessPerformSecondaryAction, 1_000_000)
        toolErrorPerformSecondaryAction = min(toolErrorPerformSecondaryAction + other.toolErrorPerformSecondaryAction, 1_000_000)
        toolEnumScroll = min(toolEnumScroll + other.toolEnumScroll, 1_000_000)
        toolSuccessScroll = min(toolSuccessScroll + other.toolSuccessScroll, 1_000_000)
        toolErrorScroll = min(toolErrorScroll + other.toolErrorScroll, 1_000_000)
        toolEnumDrag = min(toolEnumDrag + other.toolEnumDrag, 1_000_000)
        toolSuccessDrag = min(toolSuccessDrag + other.toolSuccessDrag, 1_000_000)
        toolErrorDrag = min(toolErrorDrag + other.toolErrorDrag, 1_000_000)
        toolEnumTypeText = min(toolEnumTypeText + other.toolEnumTypeText, 1_000_000)
        toolSuccessTypeText = min(toolSuccessTypeText + other.toolSuccessTypeText, 1_000_000)
        toolErrorTypeText = min(toolErrorTypeText + other.toolErrorTypeText, 1_000_000)
        toolEnumPressKey = min(toolEnumPressKey + other.toolEnumPressKey, 1_000_000)
        toolSuccessPressKey = min(toolSuccessPressKey + other.toolSuccessPressKey, 1_000_000)
        toolErrorPressKey = min(toolErrorPressKey + other.toolErrorPressKey, 1_000_000)
        toolEnumSetValue = min(toolEnumSetValue + other.toolEnumSetValue, 1_000_000)
        toolSuccessSetValue = min(toolSuccessSetValue + other.toolSuccessSetValue, 1_000_000)
        toolErrorSetValue = min(toolErrorSetValue + other.toolErrorSetValue, 1_000_000)
    }

    public mutating func record(toolName: String, succeeded: Bool) {
        switch toolName {
        case "list_apps": Self.record(&toolEnumListApps, &toolSuccessListApps, &toolErrorListApps, succeeded)
        case "get_app_state": Self.record(&toolEnumGetAppState, &toolSuccessGetAppState, &toolErrorGetAppState, succeeded)
        case "click": Self.record(&toolEnumClick, &toolSuccessClick, &toolErrorClick, succeeded)
        case "perform_secondary_action": Self.record(&toolEnumPerformSecondaryAction, &toolSuccessPerformSecondaryAction, &toolErrorPerformSecondaryAction, succeeded)
        case "scroll": Self.record(&toolEnumScroll, &toolSuccessScroll, &toolErrorScroll, succeeded)
        case "drag": Self.record(&toolEnumDrag, &toolSuccessDrag, &toolErrorDrag, succeeded)
        case "type_text": Self.record(&toolEnumTypeText, &toolSuccessTypeText, &toolErrorTypeText, succeeded)
        case "press_key": Self.record(&toolEnumPressKey, &toolSuccessPressKey, &toolErrorPressKey, succeeded)
        case "set_value": Self.record(&toolEnumSetValue, &toolSuccessSetValue, &toolErrorSetValue, succeeded)
        default: break
        }
    }

    private static func record(_ enumCounter: inout Int, _ successCounter: inout Int, _ errorCounter: inout Int, _ succeeded: Bool) {
        enumCounter = min(enumCounter + 1, 1_000_000)
        if succeeded {
            successCounter = min(successCounter + 1, 1_000_000)
        } else {
            errorCounter = min(errorCounter + 1, 1_000_000)
        }
    }
}

/// Exact v2 wire payload. Keep this type closed: adding a field is a privacy review,
/// not a convenience change.
public struct TelemetryPayload: Encodable, Equatable, Sendable {
    public static let schema = "lds.app-telemetry.event.v2"
    public static let app = "overseer-computer-use"

    public let schema: String
    public let app: String
    public let event: Event
    public let installId: String
    public let version: String
    public let platform: Platform
    public let arch: Architecture
    public let day: String
    public let batchId: String?
    public let usage: TelemetryUsage?

    public enum Event: String, Codable, Sendable {
        case launch
        case heartbeat
        case usage
    }

    public enum Platform: String, Codable, Sendable {
        case macos
        case windows
        case linux
        case ios
        case android
        case web
        case unknown
    }

    public enum Architecture: String, Codable, Sendable {
        case arm64
        case x64
        case x86
        case unknown
    }

    public init(event: Event, installId: String, version: String, platform: Platform, arch: Architecture, day: String, usage: TelemetryUsage? = nil, batchId: String? = nil) {
        self.schema = Self.schema
        self.app = Self.app
        self.event = event
        self.installId = installId
        self.version = version
        self.platform = platform
        self.arch = arch
        self.day = day
        self.batchId = event == .usage ? Self.normalizedBatchID(batchId) : nil
        self.usage = event == .usage ? usage : nil
    }

    private enum CodingKeys: String, CodingKey {
        case schema, app, event, installId, version, platform, arch, day, batchId, usage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(app, forKey: .app)
        try container.encode(event, forKey: .event)
        try container.encode(installId, forKey: .installId)
        try container.encode(version, forKey: .version)
        try container.encode(platform, forKey: .platform)
        try container.encode(arch, forKey: .arch)
        try container.encode(day, forKey: .day)
        if event == .usage {
            try container.encode(batchId, forKey: .batchId)
            if let usage {
                try container.encode(usage, forKey: .usage)
            }
        }
    }

    private static func normalizedBatchID(_ value: String?) -> String {
        let candidate = value?.lowercased() ?? ""
        let characters = Array(candidate)
        guard characters.count == 36,
              UUID(uuidString: candidate) != nil,
              characters[14] == "4",
              "89ab".contains(characters[19]) else {
            return UUID().uuidString.lowercased()
        }
        return candidate
    }
}

/// Consent and cadence storage. No UUID is generated until `optIn()` succeeds.
public struct TelemetryUsageBatch: Codable, Equatable, Sendable {
    public let batchId: String
    public let usage: TelemetryUsage

    public init(batchId: String, usage: TelemetryUsage) {
        self.batchId = batchId
        self.usage = usage
    }
}

public final class TelemetryStore: @unchecked Sendable {
    public static let endpoint = URL(string: "https://analytics.libertydesign.studio/api/app-telemetry/event")!

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let lockURL: URL
    private let consentKey = "overseer.telemetry.consent"
    private let installIDKey = "overseer.telemetry.install-id"
    private let heartbeatDayKey = "overseer.telemetry.heartbeat-day"
    private let heartbeatClaimDayKey = "overseer.telemetry.heartbeat-claim-day"
    private let usageDayKey = "overseer.telemetry.usage-day"
    private let usageInFlightKey = "overseer.telemetry.usage-in-flight"
    private let usageClaimBatchKey = "overseer.telemetry.usage-claim-batch"
    private let usageKey = "overseer.telemetry.usage"

    public init(defaults: UserDefaults = .standard, lockURL: URL? = nil) {
        self.defaults = defaults
        self.lockURL = lockURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("overseer-computer-use-telemetry.lock")
    }

    public var consent: TelemetryConsent {
        withStateLock {
            TelemetryConsent(rawValue: defaults.string(forKey: consentKey) ?? "") ?? .undecided
        }
    }

    public var installID: String? {
        withStateLock { defaults.string(forKey: installIDKey) }
    }

    public func optIn() -> String {
        withStateLock {
            let id = defaults.string(forKey: installIDKey) ?? UUID().uuidString.lowercased()
            defaults.set(TelemetryConsent.optedIn.rawValue, forKey: consentKey)
            defaults.set(id, forKey: installIDKey)
            return id
        }
    }

    public func decline() {
        withStateLock {
            defaults.set(TelemetryConsent.declined.rawValue, forKey: consentKey)
            removePrivateStateLocked()
        }
    }

    public func disable() {
        decline()
    }

    public func usage() -> TelemetryUsage {
        withStateLock {
            var value = usageLocked()
            if let inFlight = usageBatchLocked() {
                value.add(inFlight.usage)
            }
            return value
        }
    }

    public func addUsage(_ update: (inout TelemetryUsage) -> Void) {
        withStateLock {
            var value = usageLocked()
            update(&value)
            guard let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: usageKey)
        }
    }

    public func inFlightUsageBatch() -> TelemetryUsageBatch? {
        withStateLock { usageBatchLocked() }
    }

    public func beginUsageBatch() -> TelemetryUsageBatch? {
        withStateLock {
            guard usageBatchLocked() == nil else { return nil }
            let value = usageLocked()
            guard !value.isEmpty else { return nil }
            let batch = TelemetryUsageBatch(batchId: UUID().uuidString.lowercased(), usage: value)
            guard let data = try? JSONEncoder().encode(batch) else { return nil }
            defaults.set(data, forKey: usageInFlightKey)
            defaults.removeObject(forKey: usageKey)
            return batch
        }
    }

    public func claimUsageBatch(_ batchId: String) -> Bool {
        withStateLock {
            guard usageBatchLocked()?.batchId == batchId else { return false }
            guard !claimIsActive(defaults.string(forKey: usageClaimBatchKey), for: batchId) else { return false }
            defaults.set(claimValue(for: batchId), forKey: usageClaimBatchKey)
            return true
        }
    }

    public func releaseUsageBatch(_ batchId: String) {
        withStateLock {
            if let claim = defaults.string(forKey: usageClaimBatchKey),
               claim == batchId || claim.hasPrefix("\(batchId)|") {
                defaults.removeObject(forKey: usageClaimBatchKey)
            }
        }
    }

    public func markHeartbeatSent(on day: String) {
        withStateLock {
            defaults.set(day, forKey: heartbeatDayKey)
            defaults.removeObject(forKey: heartbeatClaimDayKey)
        }
    }

    public func claimHeartbeat(on day: String) -> Bool {
        withStateLock {
            guard defaults.string(forKey: heartbeatDayKey) != day,
                  !claimIsActive(defaults.string(forKey: heartbeatClaimDayKey), for: day) else { return false }
            defaults.set(claimValue(for: day), forKey: heartbeatClaimDayKey)
            return true
        }
    }
    public func releaseHeartbeat(on day: String) {
        withStateLock {
            if let claim = defaults.string(forKey: heartbeatClaimDayKey),
               claim == day || claim.hasPrefix("\(day)|") {
                defaults.removeObject(forKey: heartbeatClaimDayKey)
            }
        }
    }

    public func markUsageSent(on day: String, batchId: String? = nil) {
        withStateLock {
            guard let inFlight = usageBatchLocked() else {
                guard batchId == nil else { return }
                defaults.set(day, forKey: usageDayKey)
                defaults.removeObject(forKey: usageKey)
                return
            }
            if let batchId, inFlight.batchId != batchId { return }
            defaults.set(day, forKey: usageDayKey)
            defaults.removeObject(forKey: usageInFlightKey)
            defaults.removeObject(forKey: usageClaimBatchKey)
        }
    }

    public func lastHeartbeatDay() -> String? {
        withStateLock { defaults.string(forKey: heartbeatDayKey) }
    }

    public func lastUsageDay() -> String? {
        withStateLock { defaults.string(forKey: usageDayKey) }
    }

    private func usageLocked() -> TelemetryUsage {
        guard let data = defaults.data(forKey: usageKey),
              let value = try? JSONDecoder().decode(TelemetryUsage.self, from: data) else { return TelemetryUsage() }
        return value
    }

    private func usageBatchLocked() -> TelemetryUsageBatch? {
        guard let data = defaults.data(forKey: usageInFlightKey) else { return nil }
        return try? JSONDecoder().decode(TelemetryUsageBatch.self, from: data)
    }

    private func removePrivateStateLocked() {
        defaults.removeObject(forKey: installIDKey)
        defaults.removeObject(forKey: heartbeatDayKey)
        defaults.removeObject(forKey: heartbeatClaimDayKey)
        defaults.removeObject(forKey: usageDayKey)
        defaults.removeObject(forKey: usageKey)
        defaults.removeObject(forKey: usageInFlightKey)
        defaults.removeObject(forKey: usageClaimBatchKey)
    }
    private func claimIsActive(_ storedValue: String?, for token: String) -> Bool {
        guard let storedValue,
              let separator = storedValue.lastIndex(of: "|"),
              String(storedValue[..<separator]) == token,
              let timestamp = TimeInterval(String(storedValue[storedValue.index(after: separator)...]))
        else {
            return false
        }
        return Date().timeIntervalSince1970 - timestamp < 600
    }

    private func claimValue(for token: String) -> String {
        "\(token)|\(Date().timeIntervalSince1970)"
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        defaults.synchronize()
        let result = withProcessLock(body)
        defaults.synchronize()
        return result
    }
    private func withProcessLock<T>(_ body: () -> T) -> T {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: lockURL.path) {
            fileManager.createFile(atPath: lockURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: lockURL) else {
            return body()
        }
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            try? handle.close()
            return body()
        }
        defer {
            _ = flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
        }
        return body()
    }
}

/// Best-effort, non-blocking telemetry. All failures are deliberately ignored.
public final class TelemetryCoordinator: @unchecked Sendable {
    public typealias Sender = (URLRequest, Data, @escaping @Sendable (Bool) -> Void) -> Void

    private let store: TelemetryStore
    private let version: String
    private let platform: TelemetryPayload.Platform
    private let arch: TelemetryPayload.Architecture
    private let now: () -> Date
    private let sender: Sender
    private let calendar: Calendar

    public init(
        store: TelemetryStore = TelemetryStore(),
        version: String = openComputerUseVersion,
        platform: TelemetryPayload.Platform = .macos,
        arch: TelemetryPayload.Architecture? = nil,
        now: @escaping () -> Date = Date.init,
        sender: Sender? = nil
    ) {
        self.store = store
        self.version = version
        self.platform = platform
        self.arch = arch ?? Self.currentArchitecture
        self.now = now
        self.sender = sender ?? Self.sendSilently
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = utc
    }

    public var consent: TelemetryConsent { store.consent }

    public func recordToolResult(toolName: String, succeeded: Bool) {
        guard store.consent == .optedIn else { return }
        store.addUsage { usage in
            usage.record(toolName: toolName, succeeded: succeeded)
        }
    }

    /// Call once at process launch. Launch is recorded for this process and the
    /// heartbeat is limited to one event per UTC day. Usage batches are immutable
    /// once in flight; later counters accrue into a separate pending aggregate.
    public func start() {
        guard store.consent == .optedIn, let installID = store.installID else { return }
        let day = dayString(now())
        send(event: .launch, installID: installID, day: day)
        if store.claimHeartbeat(on: day) {
            send(event: .heartbeat, installID: installID, day: day) { [store] succeeded in
                if succeeded {
                    store.markHeartbeatSent(on: day)
                } else {
                    store.releaseHeartbeat(on: day)
                }
            }
        }
        let batch = store.inFlightUsageBatch() ?? (
            store.lastUsageDay() != day ? store.beginUsageBatch() : nil
        )
        if let batch, store.claimUsageBatch(batch.batchId) {
            send(event: .usage, installID: installID, day: day, usage: batch.usage, batchId: batch.batchId) { [store] succeeded in
                if succeeded {
                    store.markUsageSent(on: day, batchId: batch.batchId)
                } else {
                    store.releaseUsageBatch(batch.batchId)
                }
            }
        }
    }

    /// Persist consent only. The next real process launch emits the launch
    /// event, avoiding a duplicate event from the onboarding helper process.
    public func optIn() {
        _ = store.optIn()
    }

    public func decline() { store.decline() }
    public func disable() { store.disable() }

    public func makePayload(event: TelemetryPayload.Event, day: String, usage: TelemetryUsage? = nil, batchId: String? = nil) -> TelemetryPayload? {
        guard store.consent == .optedIn, let installID = store.installID else { return nil }
        return TelemetryPayload(event: event, installId: installID, version: version, platform: platform, arch: arch, day: day, usage: usage, batchId: batchId)
    }

    private func send(
        event: TelemetryPayload.Event,
        installID: String,
        day: String,
        usage: TelemetryUsage? = nil,
        batchId: String? = nil,
        completion: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        let payload = TelemetryPayload(event: event, installId: installID, version: version, platform: platform, arch: arch, day: day, usage: usage, batchId: batchId)
        guard let body = try? JSONEncoder().encode(payload) else {
            completion(false)
            return
        }
        var request = URLRequest(url: TelemetryStore.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sender(request, body, completion)
    }

    private func dayString(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }


    private static var currentArchitecture: TelemetryPayload.Architecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x64
        #elseif arch(i386)
        return .x86
        #else
        return .unknown
        #endif
    }

    private static func sendSilently(
        _ request: URLRequest,
        _ body: Data,
        _ completion: @escaping @Sendable (Bool) -> Void
    ) {
        var request = request
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = false
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            completion(error == nil && status.map((200..<300).contains) == true)
        }.resume()
    }
}
