import AppKit
import ApplicationServices
import Foundation

struct VisualCursorTarget: Equatable {
    let point: CGPoint
    let window: CursorTargetWindow?
}

public enum ClickMethod: String, CaseIterable, Sendable {
    case auto
    case accessibility
    case appPost = "app_post"
    case skyClick = "sky_click"
    case global
}

func clickActionSnapshotRecoveryPolicy(for method: ClickMethod) -> SnapshotRecoveryPolicy {
    method == .skyClick ? .readOnly : .allowActivation
}

func parseClickMethod(_ rawValue: String?) throws -> ClickMethod {
    let normalized = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ClickMethod.auto.rawValue

    guard let method = ClickMethod(rawValue: normalized) else {
        let expected = ClickMethod.allCases.map(\.rawValue).joined(separator: ", ")
        throw ComputerUseError.message(
            "Invalid click_method '\(rawValue ?? "")'. Expected one of: \(expected)"
        )
    }

    return method
}

func validateClickMethod(
    _ method: ClickMethod,
    hasElementIndex: Bool,
    environment: [String: String]
) throws {
    if method == .accessibility, !hasElementIndex {
        throw ComputerUseError.message("click_method 'accessibility' requires element_index")
    }

    if method == .global, !globalPointerFallbacksEnabled(environment: environment) {
        throw ComputerUseError.message(
            "click_method 'global' requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 because it may move the system pointer and change foreground focus"
        )
    }
}

func validateSkyClickArguments(
    method: ClickMethod,
    mouseButton: String,
    clickCount: Int
) throws {
    guard method == .skyClick else {
        return
    }

    guard mouseButton.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == MouseButtonKind.left.rawValue else {
        throw ComputerUseError.message(
            "click_method 'sky_click' only supports mouse_button 'left'"
        )
    }

    guard (1...2).contains(clickCount) else {
        throw ComputerUseError.message(
            "click_method 'sky_click' supports click_count 1 or 2"
        )
    }
}

struct VisualCursorScreenMapping: Equatable {
    let screenStateFrame: CGRect
    let appKitFrame: CGRect
}

func currentVisualCursorScreenMappings() -> [VisualCursorScreenMapping] {
    NSScreen.screens.compactMap { screen in
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return VisualCursorScreenMapping(
            screenStateFrame: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value)),
            appKitFrame: screen.frame
        )
    }
}

func screenStatePointToAppKitGlobalPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    guard let mapping = screenMappings.first(where: { $0.screenStateFrame.contains(point) }) else {
        return point
    }

    let localX = point.x - mapping.screenStateFrame.minX
    let localY = point.y - mapping.screenStateFrame.minY

    return CGPoint(
        x: mapping.appKitFrame.minX + localX,
        y: mapping.appKitFrame.maxY - localY
    )
}

func visualCursorAppKitPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    screenStatePointToAppKitGlobalPoint(
        fromScreenStatePoint: point,
        screenMappings: screenMappings
    )
}

func inputEventPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    point
}

func makeVisualCursorTarget(
    at point: CGPoint,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> VisualCursorTarget {
    VisualCursorTarget(
        point: screenStatePointToAppKitGlobalPoint(
            fromScreenStatePoint: point,
            screenMappings: screenMappings
        ),
        window: targetWindowID.map { CursorTargetWindow(windowID: $0, layer: targetWindowLayer ?? 0) }
    )
}

func makeVisualCursorTarget(
    localFrame: CGRect?,
    windowBounds: CGRect?,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> VisualCursorTarget? {
    guard let localFrame, let windowBounds else {
        return nil
    }

    let point = CGPoint(
        x: windowBounds.minX + localFrame.midX,
        y: windowBounds.minY + localFrame.midY
    )
    return makeVisualCursorTarget(
        at: point,
        targetWindowID: targetWindowID,
        targetWindowLayer: targetWindowLayer,
        screenMappings: screenMappings
    )
}

/// How the visual cursor wraps up after a tool action. Primary clicks end with a
/// click pulse; every other visual action (secondary action, scroll, drag,
/// set_value) settles back to the resting pose.
enum VisualCursorCompletion: Equatable {
    case pulse(clickCount: Int, mouseButton: MouseButtonKind)
    case settle
}

/// Centralized trigger policy for the software cursor overlay. Every visual
/// action (click, secondary action, scroll, drag, set_value) routes through
/// these entry points so cursor semantics stay consistent: `begin` moves the
/// cursor to the target before the action runs, `finish` plays the completion
/// on success, and failures always settle instead of leaving the cursor
/// mid-flight.
enum VisualCursorTriggerPolicy {
    static func begin(_ target: VisualCursorTarget?) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.moveCursor(to: target.point, in: target.window)
        }
    }

    static func finish(_ target: VisualCursorTarget?, completion: VisualCursorCompletion) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            switch completion {
            case let .pulse(clickCount, mouseButton):
                SoftwareCursorOverlay.pulseClick(
                    at: target.point,
                    clickCount: clickCount,
                    mouseButton: mouseButton,
                    in: target.window
                )
            case .settle:
                SoftwareCursorOverlay.settle(at: target.point, in: target.window)
            }
        }
    }

    @discardableResult
    static func run<T>(
        target: VisualCursorTarget?,
        completion: VisualCursorCompletion,
        action: () throws -> T
    ) throws -> T {
        begin(target)
        do {
            let value = try action()
            finish(target, completion: completion)
            return value
        } catch {
            finish(target, completion: .settle)
            throw error
        }
    }
}

func inputFallbackDebugEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

func globalPointerFallbacksEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

func screenshotPixelScale(
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGSize {
    guard
        let screenshotPixelSize,
        let windowBounds,
        windowBounds.width > 0,
        windowBounds.height > 0,
        screenshotPixelSize.width > 0,
        screenshotPixelSize.height > 0
    else {
        return CGSize(width: 1, height: 1)
    }

    return CGSize(
        width: screenshotPixelSize.width / windowBounds.width,
        height: screenshotPixelSize.height / windowBounds.height
    )
}

func screenshotPixelToWindowPoint(
    _ point: CGPoint,
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGPoint {
    let scale = screenshotPixelScale(
        screenshotPixelSize: screenshotPixelSize,
        windowBounds: windowBounds
    )
    return CGPoint(
        x: point.x / scale.width,
        y: point.y / scale.height
    )
}

let nonSettableSetValueErrorMessage = "Cannot set a value for an element that is not settable"

func setValueAttributeIsSettable(result: AXError, settable: Bool, attribute: String) throws -> Bool {
    guard result == .success else {
        throw ComputerUseError.message("AXUIElementIsAttributeSettable(\(attribute)) failed with \(result.rawValue)")
    }

    return settable
}

func invalidSecondaryActionErrorMessage(action: String, elementIndex: Int) -> String {
    "\(action) is not a valid secondary action for \(elementIndex)"
}

func localClickActionPoints(frame: CGRect, isSyntheticText: Bool) -> [CGPoint] {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let leading = CGPoint(
        x: frame.minX + min(max(frame.width * 0.3, 20), max(frame.width - 4, 20)),
        y: frame.midY
    )

    if isSyntheticText {
        return [leading]
    }

    if abs(leading.x - center.x) < 1 {
        return [center]
    }

    return [center, leading]
}

func isLikelySyntheticSideActionCandidate(
    parentFrame: CGRect?,
    candidateFrame: CGRect?,
    hasPrimaryAction: Bool,
    labels: [String]
) -> Bool {
    let hasSideActionLabel = labels.contains { label in
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        if normalized == "完成" || normalized == "done" || normalized == "complete" || normalized == "archive" {
            return true
        }

        if normalized.count <= 24 {
            if normalized.contains("完成") {
                return true
            }

            if normalized.contains("mark") && (normalized.contains("done") || normalized.contains("complete")) {
                return true
            }
        }

        return false
    }

    guard let parentFrame, let candidateFrame else {
        return false
    }

    let trailingBandWidth = min(max(parentFrame.width * 0.22, 56), 140)
    let isTrailing = candidateFrame.midX >= parentFrame.maxX - trailingBandWidth
    let compactWidth = candidateFrame.width <= max(88, parentFrame.width * 0.18)
    let compactHeight = candidateFrame.height <= max(44, parentFrame.height * 1.2)
    let isCompact = compactWidth && compactHeight

    if hasSideActionLabel && hasPrimaryAction && isCompact {
        return true
    }

    return isTrailing && isCompact && (hasPrimaryAction || hasSideActionLabel)
}

func shouldScanDescendantsOfHitRecord(originalFrame: CGRect?, hitFrame: CGRect?) -> Bool {
    guard let originalFrame, let hitFrame else {
        return true
    }

    let originalArea = max(originalFrame.width * originalFrame.height, 1)
    let hitArea = hitFrame.width * hitFrame.height
    if hitArea > max(originalArea * 12, 20_000) {
        return false
    }

    if hitFrame.height > max(originalFrame.height * 4, 96),
       hitFrame.width > max(originalFrame.width * 2, 240)
    {
        return false
    }

    return true
}

func isLikelyContainingRowActionFrame(
    targetFrame: CGRect,
    candidateFrame: CGRect?,
    hasPrimaryAction: Bool
) -> Bool {
    let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
    guard
        hasPrimaryAction,
        let candidateFrame,
        candidateFrame.insetBy(dx: -2, dy: -2).contains(targetCenter),
        candidateFrame.width >= targetFrame.width,
        candidateFrame.height >= targetFrame.height,
        candidateFrame.height <= max(targetFrame.height + 32, targetFrame.height * 2)
    else {
        return false
    }

    return true
}

func canUseActivationOnlyClickFallback(role: String?) -> Bool {
    guard let role else {
        return false
    }

    return role == kAXWindowRole as String
}

func canUseKeyboardTextFallback(role: String?, roleDescription: String?, isValueSettable: Bool) -> Bool {
    if isValueSettable {
        return true
    }

    guard let role else {
        return false
    }

    if role == kAXTextFieldRole as String || role == "AXTextArea" || role == "AXTextView" {
        return true
    }

    guard let roleDescription = roleDescription?.lowercased() else {
        return false
    }

    return roleDescription.contains("text field")
        || roleDescription.contains("text area")
        || roleDescription.contains("text entry")
}

func isElectronScopedWebRowClickOptimizationTarget(appName: String, bundleIdentifier: String?) -> Bool {
    let normalizedBundleIdentifier = bundleIdentifier?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedName = appName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    if let normalizedBundleIdentifier,
       normalizedBundleIdentifier.hasPrefix("com.electron.")
            || normalizedBundleIdentifier.contains(".electron.")
            || normalizedBundleIdentifier.contains("lark")
            || normalizedBundleIdentifier.contains("feishu")
    {
        return true
    }

    return normalizedName == "lark" || normalizedName == "feishu" || normalizedName == "飞书"
}

func shouldPreferContainingWebRowAXClickCandidate(
    role: String?,
    isSyntheticText: Bool,
    hasWebAreaAncestor: Bool,
    appName: String,
    bundleIdentifier: String?
) -> Bool {
    guard hasWebAreaAncestor,
          isElectronScopedWebRowClickOptimizationTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier
          )
    else {
        return false
    }

    guard let role else {
        return isSyntheticText
    }

    return role == kAXStaticTextRole as String || role == kAXGroupRole as String || isSyntheticText
}

/// Bounds how long and how many snapshots the service keeps. The TTL keeps
/// actions from silently operating on ancient state; the capacity keeps
/// memory bounded regardless of how many apps are queried.
public struct SnapshotCachePolicy: Equatable, Sendable {
    public static let defaultTTL: TimeInterval = 15
    public static let defaultCapacity = 16
    public static let defaults = SnapshotCachePolicy()

    public let ttl: TimeInterval
    public let capacity: Int

    public init(ttl: TimeInterval = defaultTTL, capacity: Int = defaultCapacity) {
        precondition(ttl > 0, "ttl must be positive")
        precondition(capacity > 0, "capacity must be positive")
        self.ttl = ttl
        self.capacity = capacity
    }
}

/// Bounded TTL/LRU cache of app snapshots. Entries are keyed canonically by
/// pid with query/name/bundle aliases; reads revalidate TTL, process
/// liveness, and target-window existence before a snapshot is reused.
final class SnapshotCache {
    typealias Clock = () -> Date
    typealias ProcessAliveCheck = (pid_t) -> Bool
    typealias WindowExistenceCheck = (pid_t, CGWindowID) -> Bool

    private struct Entry {
        let snapshot: AppSnapshot
        let storedAt: Date
        let aliasKeys: Set<String>
    }

    private let policy: SnapshotCachePolicy
    private let clock: Clock
    private let isProcessAlive: ProcessAliveCheck
    private let windowExists: WindowExistenceCheck

    private var entriesByCanonicalKey: [String: Entry] = [:]
    private var canonicalKeyByAlias: [String: String] = [:]
    /// Oldest first; the back is the most recently used canonical key.
    private var lruKeys: [String] = []

    init(
        policy: SnapshotCachePolicy = .defaults,
        clock: @escaping Clock = { Date() },
        isProcessAlive: @escaping ProcessAliveCheck = SnapshotCache.defaultIsProcessAlive,
        windowExists: @escaping WindowExistenceCheck = SnapshotCache.defaultWindowExists
    ) {
        self.policy = policy
        self.clock = clock
        self.isProcessAlive = isProcessAlive
        self.windowExists = windowExists
    }

    static func defaultIsProcessAlive(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.isTerminated == false
    }

    static func defaultWindowExists(_ pid: pid_t, _ windowID: CGWindowID) -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return infoList.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }
    }

    /// Returns the cached snapshot for an alias key when it is still fresh
    /// and its target process/window are intact; otherwise evicts it.
    func snapshot(forKey key: String) -> AppSnapshot? {
        guard let canonicalKey = canonicalKeyByAlias[key],
              let entry = entriesByCanonicalKey[canonicalKey]
        else {
            return nil
        }

        guard isValid(entry) else {
            evict(canonicalKey: canonicalKey)
            return nil
        }

        promote(canonicalKey: canonicalKey)
        return entry.snapshot
    }

    func store(_ snapshot: AppSnapshot, aliasKeys: Set<String>) {
        let canonicalKey = Self.canonicalKey(for: snapshot)
        evict(canonicalKey: canonicalKey)

        let allAliases = aliasKeys.union([canonicalKey]).filter { !$0.isEmpty }
        entriesByCanonicalKey[canonicalKey] = Entry(
            snapshot: snapshot,
            storedAt: clock(),
            aliasKeys: allAliases
        )
        for alias in allAliases {
            canonicalKeyByAlias[alias] = canonicalKey
        }
        lruKeys.append(canonicalKey)

        while lruKeys.count > policy.capacity, let oldest = lruKeys.first {
            evict(canonicalKey: oldest)
        }
    }

    func removeAll() {
        entriesByCanonicalKey.removeAll()
        canonicalKeyByAlias.removeAll()
        lruKeys.removeAll()
    }

    static func canonicalKey(for snapshot: AppSnapshot) -> String {
        "pid:\(snapshot.app.pid)"
    }

    private func isValid(_ entry: Entry) -> Bool {
        guard clock().timeIntervalSince(entry.storedAt) <= policy.ttl else {
            return false
        }

        let pid = entry.snapshot.app.pid
        guard isProcessAlive(pid) else {
            return false
        }

        if let windowID = entry.snapshot.targetWindowID, !windowExists(pid, windowID) {
            return false
        }

        return true
    }

    private func promote(canonicalKey: String) {
        lruKeys.removeAll { $0 == canonicalKey }
        lruKeys.append(canonicalKey)
    }

    private func evict(canonicalKey: String) {
        guard let entry = entriesByCanonicalKey.removeValue(forKey: canonicalKey) else {
            lruKeys.removeAll { $0 == canonicalKey }
            return
        }

        for alias in entry.aliasKeys where canonicalKeyByAlias[alias] == canonicalKey {
            canonicalKeyByAlias.removeValue(forKey: alias)
        }
        lruKeys.removeAll { $0 == canonicalKey }
    }
}

public final class ComputerUseService {
    private let snapshotCache: SnapshotCache

    public convenience init() {
        self.init(snapshotCache: SnapshotCache())
    }

    init(snapshotCache: SnapshotCache) {
        self.snapshotCache = snapshotCache
    }

    public func listApps() -> ToolCallResult {
        ToolCallResult.text(
            AppDiscovery.listCatalog()
                .map(\.renderedLine)
                .joined(separator: "\n")
        )
    }

    public func getAppState(
        app query: String,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults,
        includeScreenshot: Bool = true
    ) throws -> ToolCallResult {
        snapshotResult(
            for: try refreshSnapshot(
                for: query,
                textLimit: textLimit,
                treeLimits: treeLimits,
                includeScreenshot: includeScreenshot
            ),
            style: .fullState
        )
    }

    public func click(
        app query: String,
        elementIndex: String?,
        x: Double?,
        y: Double?,
        clickCount: Int,
        mouseButton: String,
        clickMethod: ClickMethod = .auto,
        stateID: String? = nil
    ) throws -> ToolCallResult {
        try validateClickMethod(
            clickMethod,
            hasElementIndex: elementIndex != nil,
            environment: ProcessInfo.processInfo.environment
        )
        try validateSkyClickArguments(
            method: clickMethod,
            mouseButton: mouseButton,
            clickCount: clickCount
        )

        // Defense in depth: the dispatcher and schema validator reject these
        // first, but direct service callers must never get a silent .left
        // fallback or a clamped click count.
        guard let button = MouseButtonKind(
            rawValue: mouseButton.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) else {
            throw ComputerUseError.invalidArguments(
                "mouse_button must be one of \(MouseButtonKind.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        guard clickCount > 0 else {
            throw ComputerUseError.invalidArguments("click_count must be a positive integer")
        }

        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        if snapshot.mode == .fixture {
            guard clickMethod == .auto else {
                throw ComputerUseError.message(
                    "click_method '\(clickMethod.rawValue)' is not supported for fixture apps"
                )
            }

            let cursorTarget: VisualCursorTarget?
            if let elementIndex {
                let record = try lookupElement(snapshot: snapshot, index: elementIndex)
                guard let identifier = record.identifier else {
                    throw ComputerUseError.invalidArguments("fixture click requires an identifier-backed element")
                }
                cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
                try VisualCursorTriggerPolicy.run(
                    target: cursorTarget,
                    completion: .pulse(clickCount: clickCount, mouseButton: button)
                ) {
                    try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier))
                    Thread.sleep(forTimeInterval: 0.15)
                }
            } else if let x, let y {
                let identifier = try fixtureIdentifier(at: CGPoint(x: x, y: y), snapshot: snapshot)
                cursorTarget = fixtureVisualCursorTarget(identifier: identifier, snapshot: snapshot)
                try VisualCursorTriggerPolicy.run(
                    target: cursorTarget,
                    completion: .pulse(clickCount: clickCount, mouseButton: button)
                ) {
                    try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier, x: x, y: y))
                    Thread.sleep(forTimeInterval: 0.15)
                }
            } else {
                throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
            }

            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        if let elementIndex {
            let record = try lookupElement(snapshot: snapshot, index: elementIndex)
            guard let windowPoint = clickPoint(for: record, snapshot: snapshot) else {
                throw ComputerUseError.stateUnavailable("element \(elementIndex) has no clickable frame")
            }
            let targetPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: windowPoint)
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            try VisualCursorTriggerPolicy.run(
                target: cursorTarget,
                completion: .pulse(clickCount: clickCount, mouseButton: button)
            ) {
                switch clickMethod {
                case .auto:
                    if !(try performAXClickSequence(
                        on: record,
                        snapshot: snapshot,
                        button: button,
                        clickCount: clickCount,
                        includeNearbyHitTesting: true,
                        allowActivationFallback: true
                    )) {
                        try performNonAXClickFallback(
                            at: targetPoint,
                            button: button,
                            clickCount: clickCount,
                            targetDescription: "element_index=\(elementIndex)",
                            snapshot: snapshot
                        )
                    }
                case .accessibility:
                    guard try performAXClickSequence(
                        on: record,
                        snapshot: snapshot,
                        button: button,
                        clickCount: clickCount,
                        includeNearbyHitTesting: true,
                        allowActivationFallback: true
                    ) else {
                        throw ComputerUseError.message(
                            "click_method 'accessibility' could not click element_index=\(elementIndex)"
                        )
                    }
                case .appPost, .skyClick, .global:
                    try performExplicitMouseClick(
                        method: clickMethod,
                        at: targetPoint,
                        windowPoint: windowPoint,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "element_index=\(elementIndex)",
                        snapshot: snapshot
                    )
                }
            }
        } else if let x, let y {
            let screenshotPoint = CGPoint(x: x, y: y)
            let point = screenshotPixelToWindowPointInSnapshot(snapshot: snapshot, point: screenshotPoint)
            let targetPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: point)
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            try VisualCursorTriggerPolicy.run(
                target: cursorTarget,
                completion: .pulse(clickCount: clickCount, mouseButton: button)
            ) {
                switch clickMethod {
                case .auto:
                    let candidates = try clickCandidates(at: point, in: snapshot)
                    var handled = false
                    for record in candidates {
                        if try performAXClickSequence(
                            on: record,
                            snapshot: snapshot,
                            button: button,
                            clickCount: clickCount,
                            includeNearbyHitTesting: false,
                            allowActivationFallback: false
                        ) {
                            handled = true
                            break
                        }
                    }

                    if !handled {
                        try performNonAXClickFallback(
                            at: targetPoint,
                            button: button,
                            clickCount: clickCount,
                            targetDescription: "x=\(Int(screenshotPoint.x)) y=\(Int(screenshotPoint.y))",
                            snapshot: snapshot
                        )
                    }
                case .accessibility:
                    throw ComputerUseError.message("click_method 'accessibility' requires element_index")
                case .appPost, .skyClick, .global:
                    try performExplicitMouseClick(
                        method: clickMethod,
                        at: targetPoint,
                        windowPoint: point,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "x=\(Int(screenshotPoint.x)) y=\(Int(screenshotPoint.y))",
                        snapshot: snapshot
                    )
                }
            }
        } else {
            throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
        }

        return snapshotResult(
            for: try refreshSnapshot(
                for: query,
                recoveryPolicy: clickActionSnapshotRecoveryPolicy(for: clickMethod)
            ),
            style: .actionResult
        )
    }

    public func performSecondaryAction(app query: String, elementIndex: String, action: String, stateID: String? = nil) throws -> ToolCallResult {
        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard action.caseInsensitiveCompare("Raise") == .orderedSame else {
                throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
            }

            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard let rawAction = matchingAction(requested: action, record: record) else {
            throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
        try VisualCursorTriggerPolicy.run(target: cursorTarget, completion: .settle) {
            let result = AXUIElementPerformAction(element, rawAction as CFString)
            guard result == .success else {
                throw ComputerUseError.message("AXUIElementPerformAction failed with \(result.rawValue)")
            }

            Thread.sleep(forTimeInterval: 0.15)
        }
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func scroll(app query: String, direction: String, elementIndex: String, pages: Double, stateID: String? = nil) throws -> ToolCallResult {
        let normalized = direction.lowercased()
        guard ["up", "down", "left", "right"].contains(normalized) else {
            throw ComputerUseError.message("Invalid scroll direction: \(direction)")
        }
        guard pages.isFinite, pages > 0 else {
            throw ComputerUseError.message("pages must be > 0")
        }

        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture scroll requires an identifier-backed element")
            }
            let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
            try VisualCursorTriggerPolicy.run(target: cursorTarget, completion: .settle) {
                try FixtureBridge.post(FixtureCommand(kind: "scroll", identifier: identifier, direction: normalized, pages: pages))
                Thread.sleep(forTimeInterval: 0.15)
            }
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
        try VisualCursorTriggerPolicy.run(target: cursorTarget, completion: .settle) {
            if let repeatCount = integralScrollPageCount(pages),
               let rawAction = record.rawActions.first(where: { $0.caseInsensitiveCompare("AXScroll\(normalized.capitalized)ByPage") == .orderedSame }),
               let element = record.element {
                for _ in 0..<repeatCount {
                    _ = AXUIElementPerformAction(element, rawAction as CFString)
                    Thread.sleep(forTimeInterval: 0.05)
                }
            } else if let point = try globalPoint(for: record, snapshot: snapshot) {
                try performScrollEvent(
                    at: point,
                    direction: normalized,
                    pages: pages,
                    targetDescription: "element_index=\(elementIndex)",
                    snapshot: snapshot
                )
            } else {
                throw ComputerUseError.stateUnavailable("element \(elementIndex) has no scrollable frame")
            }
        }

        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func drag(app query: String, fromX: Double, fromY: Double, toX: Double, toY: Double, stateID: String? = nil) throws -> ToolCallResult {
        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        if snapshot.mode == .fixture {
            let startTarget = makeVisualCursorTarget(
                at: CGPoint(x: fromX, y: fromY),
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )
            let endTarget = makeVisualCursorTarget(
                at: CGPoint(x: toX, y: toY),
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )
            VisualCursorTriggerPolicy.begin(startTarget)
            do {
                try FixtureBridge.post(FixtureCommand(kind: "drag", identifier: "fixture-drag-pad", x: fromX, y: fromY, toX: toX, toY: toY))
                Thread.sleep(forTimeInterval: 0.15)
            } catch {
                VisualCursorTriggerPolicy.finish(startTarget, completion: .settle)
                throw error
            }
            VisualCursorTriggerPolicy.finish(endTarget, completion: .settle)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        let start = try screenshotToGlobalPoint(snapshot: snapshot, x: fromX, y: fromY)
        let end = try screenshotToGlobalPoint(snapshot: snapshot, x: toX, y: toY)
        let startTarget = makeVisualCursorTarget(
            at: start,
            targetWindowID: snapshot.targetWindowID,
            targetWindowLayer: snapshot.targetWindowLayer
        )
        let endTarget = makeVisualCursorTarget(
            at: end,
            targetWindowID: snapshot.targetWindowID,
            targetWindowLayer: snapshot.targetWindowLayer
        )
        VisualCursorTriggerPolicy.begin(startTarget)
        do {
            try performDragEvent(
                from: start,
                to: end,
                targetDescription: "from=(\(Int(fromX)), \(Int(fromY))) to=(\(Int(toX)), \(Int(toY)))",
                snapshot: snapshot
            )
        } catch {
            VisualCursorTriggerPolicy.finish(startTarget, completion: .settle)
            throw error
        }
        VisualCursorTriggerPolicy.finish(endTarget, completion: .settle)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func typeText(app query: String, text: String, stateID: String? = nil) throws -> ToolCallResult {
        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "type_text", identifier: "fixture-input", value: text))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        if try typeTextBySettingFocusedValueIfAvailable(text, in: snapshot) {
            Thread.sleep(forTimeInterval: 0.1)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard try canTypeTextUsingKeyboardFallback(in: snapshot) else {
            throw ComputerUseError.stateUnavailable("type_text requires a focused editable text element. Click a text entry area first, or use set_value on a settable text element.")
        }

        try InputSimulation.typeText(text, pid: snapshot.app.pid)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func pressKey(app query: String, key: String, stateID: String? = nil) throws -> ToolCallResult {
        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "press_key", identifier: "fixture-key-capture", value: key))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        try InputSimulation.pressKey(key, pid: snapshot.app.pid)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func setValue(app query: String, elementIndex: String, value: String, stateID: String? = nil) throws -> ToolCallResult {
        let snapshot = try snapshotForAction(query: query, stateID: stateID)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture set_value requires a known element identifier")
            }

            let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
            try VisualCursorTriggerPolicy.run(target: cursorTarget, completion: .settle) {
                try FixtureBridge.post(FixtureCommand(kind: "set_value", identifier: identifier, value: value))
                Thread.sleep(forTimeInterval: 0.15)
            }
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        guard try isSettableForSetValue(element: element, attribute: kAXValueAttribute) else {
            throw ComputerUseError.message(nonSettableSetValueErrorMessage)
        }

        let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
        try VisualCursorTriggerPolicy.run(target: cursorTarget, completion: .settle) {
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
            guard result == .success else {
                throw ComputerUseError.message("AXUIElementSetAttributeValue failed with \(result.rawValue)")
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    private func currentSnapshot(for query: String) throws -> AppSnapshot {
        if let snapshot = snapshotCache.snapshot(forKey: query.lowercased()) {
            return snapshot
        }

        return try refreshSnapshot(for: query)
    }

    /// Resolves the snapshot an action should operate on. When the caller
    /// supplies a `stateID`, the cached snapshot must match it exactly — a
    /// stale identifier fails before any input is simulated.
    private func snapshotForAction(query: String, stateID: String?) throws -> AppSnapshot {
        if let stateID {
            return try requireFreshState(stateID, for: query)
        }

        return try currentSnapshot(for: query)
    }

    /// Returns the fresh cached snapshot for `query` only when its
    /// `stateID` matches; throws `ComputerUseError.staleState` on mismatch
    /// and `ComputerUseError.stateUnavailable` when nothing fresh is cached.
    @discardableResult
    public func requireFreshState(_ stateID: String, for query: String) throws -> AppSnapshot {
        guard let snapshot = snapshotCache.snapshot(forKey: query.lowercased()) else {
            throw ComputerUseError.stateUnavailable(
                "No fresh snapshot is cached for '\(query)'. Run get_app_state first."
            )
        }

        guard snapshot.stateID == stateID else {
            throw ComputerUseError.staleState(
                "Snapshot state_id '\(stateID)' is stale for '\(query)'. Call get_app_state to refresh state_id."
            )
        }

        return snapshot
    }

    @discardableResult
    private func refreshSnapshot(
        for query: String,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults,
        recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation,
        includeScreenshot: Bool = true
    ) throws -> AppSnapshot {
        let app = try AppDiscovery.resolve(query)
        let snapshot = try SnapshotBuilder.build(
            for: app,
            textLimit: textLimit,
            treeLimits: treeLimits,
            recoveryPolicy: recoveryPolicy,
            includeScreenshot: includeScreenshot
        )

        let keys = Set([
            query.lowercased(),
            app.name.lowercased(),
            (app.bundleIdentifier ?? "").lowercased(),
        ].filter { !$0.isEmpty })

        snapshotCache.store(snapshot, aliasKeys: keys)

        return snapshot
    }

    private func lookupElement(snapshot: AppSnapshot, index: String) throws -> ElementRecord {
        guard let parsedIndex = Int(index), let record = snapshot.elements[parsedIndex] else {
            throw ComputerUseError.invalidArguments("unknown element_index '\(index)'")
        }

        return record
    }

    private func matchingAction(requested: String, record: ElementRecord) -> String? {
        if let exact = record.rawActions.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
            return exact
        }

        if let pretty = zip(record.rawActions, record.prettyActions).first(where: { $0.1.caseInsensitiveCompare(requested) == .orderedSame }) {
            return pretty.0
        }

        return nil
    }

    private func invalidSecondaryActionMessage(action: String, record: ElementRecord) -> String {
        invalidSecondaryActionErrorMessage(action: action, elementIndex: record.index)
    }

    private func performPreferredClick(on record: ElementRecord, button: MouseButtonKind, clickCount: Int) throws -> Bool {
        guard let element = record.element else {
            return false
        }

        switch button {
        case .left:
            if clickCount <= 1,
               !hasAncestorRole("AXWebArea", of: element),
               try selectContainingListItem(for: element)
            {
                return true
            }

            if try performAction(named: kAXPressAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try performAction(named: kAXConfirmAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try performAction(named: "AXOpen", on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .right:
            if try performAction(named: kAXShowMenuAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .middle:
            break
        }

        return false
    }

    private func clickCandidates(at point: CGPoint, in snapshot: AppSnapshot) throws -> [ElementRecord] {
        var candidates: [ElementRecord] = []

        if let bestRecord = bestElement(containing: point, in: snapshot) {
            candidates.append(bestRecord)
        }

        if let hitRecord = try hitTestElement(at: point, in: snapshot) {
            candidates.append(hitRecord)
        }

        return candidates.reduce(into: []) { uniqueCandidates, candidate in
            if !uniqueCandidates.contains(where: { sameElement($0.element, candidate.element) }) {
                uniqueCandidates.append(candidate)
            }
        }
    }

    private func sameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        return CFEqual(lhs, rhs)
    }

    private func selectContainingListItem(for element: AXUIElement) throws -> Bool {
        guard let target = selectableListItem(containing: element) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            target.list,
            kAXSelectedChildrenAttribute as CFString,
            [target.item] as CFArray
        )

        switch result {
        case .success:
            Thread.sleep(forTimeInterval: 0.15)
            return true
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue(\(kAXSelectedChildrenAttribute)) failed with \(result.rawValue)")
        }
    }

    private func selectableListItem(containing element: AXUIElement) -> (list: AXUIElement, item: AXUIElement)? {
        var current = element
        var directChild = element

        for _ in 0..<8 {
            guard let parent = copyParent(of: current) else {
                return nil
            }

            if stringValue(of: parent, attribute: kAXRoleAttribute) == kAXListRole as String,
               isSettable(element: parent, attribute: kAXSelectedChildrenAttribute)
            {
                return (parent, directChild)
            }

            directChild = parent
            current = parent
        }

        return nil
    }

    private func performAXClickSequence(
        on record: ElementRecord,
        snapshot: AppSnapshot,
        button: MouseButtonKind,
        clickCount: Int,
        includeNearbyHitTesting: Bool,
        allowActivationFallback: Bool
    ) throws -> Bool {
        let preferContainingWebRowAXClick = shouldPreferContainingWebRowAXClick(record, in: snapshot)
        debugClickDecision("record=\(clickDebugDescription(record)) preferContainingWebRowAXClick=\(preferContainingWebRowAXClick)")

        if preferContainingWebRowAXClick,
           try performContainingWebRowClick(for: record, snapshot: snapshot, button: button, clickCount: clickCount)
        {
            Thread.sleep(forTimeInterval: 0.15)
            return true
        }

        if !preferContainingWebRowAXClick {
            if try performPreferredClick(on: record, button: button, clickCount: clickCount) {
                debugClickDecision("handled by preferred target \(clickDebugDescription(record))")
                Thread.sleep(forTimeInterval: 0.15)
                return true
            }

            for candidate in descendantClickCandidates(for: record, snapshot: snapshot) {
                if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                    debugClickDecision("handled by descendant \(clickDebugDescription(candidate))")
                    Thread.sleep(forTimeInterval: 0.15)
                    return true
                }
            }

            if includeNearbyHitTesting {
                for localPoint in clickActionPoints(for: record, snapshot: snapshot) {
                    guard let hitRecord = try hitTestElement(at: localPoint, in: snapshot) ?? bestElement(containing: localPoint, in: snapshot) else {
                        continue
                    }

                    if !isLikelySyntheticSideAction(hitRecord, in: record),
                       try performPreferredClick(on: hitRecord, button: button, clickCount: clickCount)
                    {
                        debugClickDecision("handled by hit record \(clickDebugDescription(hitRecord))")
                        Thread.sleep(forTimeInterval: 0.15)
                        return true
                    }

                    if shouldScanDescendantsOfHitRecord(
                        originalFrame: clickFrame(for: record, snapshot: snapshot),
                        hitFrame: hitRecord.localFrame
                    ) {
                        for candidate in descendantClickCandidates(
                            for: hitRecord,
                            snapshot: snapshot,
                            sideActionScope: record
                        ) {
                            if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                                debugClickDecision("handled by hit descendant \(clickDebugDescription(candidate))")
                                Thread.sleep(forTimeInterval: 0.15)
                                return true
                            }
                        }
                    }
                }
            }
        }

        guard
            allowActivationFallback,
            !record.isSyntheticText,
            button == .left,
            let element = record.element,
            canUseActivationOnlyClickFallback(role: stringValue(of: element, attribute: kAXRoleAttribute))
        else {
            return false
        }

        if try activateClickTarget(element: element, availableActions: record.rawActions) {
            debugClickDecision("handled by activation fallback \(clickDebugDescription(record))")
            Thread.sleep(forTimeInterval: 0.15)
            return true
        }

        return false
    }

    private func performAction(named action: String, on element: AXUIElement, availableActions: [String], repeatCount: Int = 1) throws -> Bool {
        guard availableActions.contains(where: { $0.caseInsensitiveCompare(action) == .orderedSame }) else {
            return false
        }

        let attempts = max(repeatCount, 1)
        for index in 0..<attempts {
            let result = AXUIElementPerformAction(element, action as CFString)
            switch result {
            case .success:
                if index < attempts - 1 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            case .attributeUnsupported where action.caseInsensitiveCompare("AXOpen") == .orderedSame:
                return true
            case .failure, .actionUnsupported, .attributeUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
                return false
            default:
                throw ComputerUseError.message("AXUIElementPerformAction(\(action)) failed with \(result.rawValue)")
            }
        }

        return true
    }

    private func activateClickTarget(element: AXUIElement, availableActions: [String]) throws -> Bool {
        var activated = false

        if try performAction(named: kAXRaiseAction as String, on: element, availableActions: availableActions) {
            activated = true
        }

        if try setBoolAttribute(named: kAXMainAttribute, on: element) {
            activated = true
        }

        if try setBoolAttribute(named: kAXFocusedAttribute, on: element) {
            activated = true
        }

        return activated
    }

    private func setBoolAttribute(named attribute: String, on element: AXUIElement) throws -> Bool {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        switch result {
        case .success:
            return true
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue(\(attribute)) failed with \(result.rawValue)")
        }
    }

    private func isSettable(element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func isSettableForSetValue(element: AXUIElement, attribute: String) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return try setValueAttributeIsSettable(
            result: result,
            settable: settable.boolValue,
            attribute: attribute
        )
    }

    private func bestElement(containing point: CGPoint, in snapshot: AppSnapshot) -> ElementRecord? {
        snapshot.elements.values
            .filter { $0.localFrame?.contains(point) ?? false }
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
            .first
    }

    private func hitTestElement(at point: CGPoint, in snapshot: AppSnapshot) throws -> ElementRecord? {
        let appElement = AXUIElementCreateApplication(snapshot.app.pid)
        applyAccessibilityMessagingTimeout(to: appElement)
        // `point` is already window-relative (from snapshot element frames or
        // clickActionPoints). Convert window -> global exactly once; routing
        // through screenshotToGlobalPoint would re-apply the screenshot
        // pixel-to-window scale and land off-target on Retina displays.
        let globalPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: point)
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(appElement, Float(globalPoint.x), Float(globalPoint.y), &hitElement)
        guard result == .success, let hitElement else {
            return nil
        }

        let rawActions = copyActions(for: hitElement) ?? []
        return ElementRecord(
            index: -1,
            identifier: nil,
            element: hitElement,
            localFrame: localFrame(of: hitElement, windowBounds: snapshot.windowBounds),
            rawActions: rawActions,
            prettyActions: rawActions
        )
    }

    private func clickPriority(for record: ElementRecord) -> Int {
        if record.rawActions.contains(where: {
            $0.caseInsensitiveCompare(kAXPressAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXConfirmAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXShowMenuAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXRaiseAction as String) == .orderedSame
        }) {
            return 0
        }

        if let element = record.element,
           isSettable(element: element, attribute: kAXMainAttribute) ||
           isSettable(element: element, attribute: kAXFocusedAttribute) {
            return 1
        }

        return 2
    }

    private func frameArea(of record: ElementRecord) -> CGFloat {
        guard let frame = record.localFrame else {
            return .greatestFiniteMagnitude
        }

        return frame.width * frame.height
    }

    private func localCenter(for record: ElementRecord) -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func clickActionPoints(for record: ElementRecord, snapshot: AppSnapshot) -> [CGPoint] {
        guard let frame = clickFrame(for: record, snapshot: snapshot) else {
            return []
        }

        return localClickActionPoints(frame: frame, isSyntheticText: record.isSyntheticText)
    }

    private func descendantClickCandidates(
        for record: ElementRecord,
        snapshot: AppSnapshot,
        sideActionScope: ElementRecord? = nil
    ) -> [ElementRecord] {
        guard let element = record.element else {
            return []
        }

        let sideActionParent = sideActionScope ?? record
        return descendantClickCandidates(of: element, windowBounds: snapshot.windowBounds)
            .filter { candidate in
                !isLikelySyntheticSideAction(candidate, in: sideActionParent)
            }
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
    }

    private func descendantClickCandidates(of element: AXUIElement, windowBounds: CGRect?, depth: Int = 0) -> [ElementRecord] {
        guard depth < 3 else {
            return []
        }

        var results: [ElementRecord] = []
        for child in copyChildren(of: element) {
            let rawActions = copyActions(for: child) ?? []
            results.append(
                ElementRecord(
                    index: -1,
                    identifier: nil,
                    element: child,
                    localFrame: localFrame(of: child, windowBounds: windowBounds),
                    rawActions: rawActions,
                    prettyActions: rawActions
                )
            )
            results.append(contentsOf: descendantClickCandidates(of: child, windowBounds: windowBounds, depth: depth + 1))
        }

        return results
    }

    private func isLikelySyntheticSideAction(_ candidate: ElementRecord, in parent: ElementRecord) -> Bool {
        isLikelySyntheticSideActionCandidate(
            parentFrame: parent.localFrame,
            candidateFrame: candidate.localFrame,
            hasPrimaryAction: hasPrimaryClickAction(candidate),
            labels: accessibilityLabels(for: candidate.element)
        )
    }

    private func hasPrimaryClickAction(_ record: ElementRecord) -> Bool {
        record.rawActions.contains { action in
            action.caseInsensitiveCompare(kAXPressAction as String) == .orderedSame ||
                action.caseInsensitiveCompare(kAXConfirmAction as String) == .orderedSame ||
                action.caseInsensitiveCompare("AXOpen") == .orderedSame ||
                action.caseInsensitiveCompare(kAXShowMenuAction as String) == .orderedSame
        }
    }

    private func shouldPreferContainingWebRowAXClick(_ record: ElementRecord, in snapshot: AppSnapshot) -> Bool {
        guard
            let element = record.element
        else {
            return false
        }

        return shouldPreferContainingWebRowAXClickCandidate(
            role: stringValue(of: element, attribute: kAXRoleAttribute),
            isSyntheticText: record.isSyntheticText,
            hasWebAreaAncestor: hasAncestorRole("AXWebArea", of: element),
            appName: snapshot.app.name,
            bundleIdentifier: snapshot.app.bundleIdentifier
        )
    }

    private func performContainingWebRowClick(
        for record: ElementRecord,
        snapshot: AppSnapshot,
        button: MouseButtonKind,
        clickCount: Int
    ) throws -> Bool {
        guard
            button == .left,
            clickCount <= 1,
            let element = record.element,
            let targetFrame = record.localFrame
        else {
            return false
        }

        var current = element

        for _ in 0..<6 {
            guard let parent = copyParent(of: current) else {
                return false
            }

            let rawActions = copyActions(for: parent) ?? []
            let candidate = ElementRecord(
                index: -1,
                identifier: nil,
                element: parent,
                localFrame: localFrame(of: parent, windowBounds: snapshot.windowBounds),
                rawActions: rawActions,
                prettyActions: rawActions
            )

            if isLikelyContainingWebRowAction(targetFrame: targetFrame, candidate: candidate),
               !isLikelySyntheticSideAction(candidate, in: record),
               try performAction(named: kAXPressAction as String, on: parent, availableActions: rawActions)
            {
                debugClickDecision("handled by containing web row \(clickDebugDescription(candidate))")
                return true
            }

            current = parent
        }

        return false
    }

    private func isLikelyContainingWebRowAction(
        targetFrame: CGRect,
        candidate: ElementRecord
    ) -> Bool {
        isLikelyContainingRowActionFrame(
            targetFrame: targetFrame,
            candidateFrame: candidate.localFrame,
            hasPrimaryAction: hasPrimaryClickAction(candidate)
        )
    }

    private func hasAncestorRole(_ role: String, of element: AXUIElement) -> Bool {
        var current = element

        for _ in 0..<12 {
            guard let parent = copyParent(of: current) else {
                return false
            }

            if stringValue(of: parent, attribute: kAXRoleAttribute) == role {
                return true
            }

            current = parent
        }

        return false
    }

    private func accessibilityLabels(for element: AXUIElement?) -> [String] {
        guard let element else {
            return []
        }

        return [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXValueAttribute as String,
            "AXIdentifier"
        ].compactMap { attribute in
            stringValue(of: element, attribute: attribute)
        }
    }

    private func typeTextBySettingFocusedValueIfAvailable(_ text: String, in snapshot: AppSnapshot) throws -> Bool {
        guard let element = snapshot.focusedElement else {
            return false
        }

        guard try isSettableForSetValue(element: element, attribute: kAXValueAttribute) else {
            return false
        }

        let baseValue = editableBaseValue(for: element)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (baseValue + text) as CFString)
        switch result {
        case .success:
            return true
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue failed with \(result.rawValue)")
        }
    }

    private func canTypeTextUsingKeyboardFallback(in snapshot: AppSnapshot) throws -> Bool {
        guard let element = snapshot.focusedElement else {
            return false
        }

        let role = stringValue(of: element, attribute: kAXRoleAttribute)
        let roleDescription = role.flatMap {
            stringValue(of: element, attribute: kAXRoleDescriptionAttribute) ?? humanizedRoleDescription(for: $0)
        }
        return canUseKeyboardTextFallback(
            role: role,
            roleDescription: roleDescription,
            isValueSettable: try isSettableForSetValue(element: element, attribute: kAXValueAttribute)
        )
    }

    private func humanizedRoleDescription(for role: String) -> String {
        if role == kAXTextFieldRole as String {
            return "text field"
        }

        switch role {
        case "AXTextArea", "AXTextView":
            return "text entry area"
        default:
            return ""
        }
    }

    private func editableBaseValue(for element: AXUIElement) -> String {
        let childTextValues = editableDescendantTextValues(in: element)
            .filter { !looksLikeEditablePlaceholder($0) }
        if !childTextValues.isEmpty {
            return childTextValues.joined()
        }

        guard let currentValue = stringValue(of: element, attribute: kAXValueAttribute) else {
            return ""
        }

        let normalizedValue = normalizeEditablePlaceholderText(currentValue)
        if normalizedValue.isEmpty || looksLikeEditablePlaceholder(normalizedValue) {
            return ""
        }

        for attribute in ["AXPlaceholderValue", "AXPlaceholder"] {
            guard let placeholder = stringValue(of: element, attribute: attribute) else {
                continue
            }

            if normalizedValue == normalizeEditablePlaceholderText(placeholder) {
                return ""
            }
        }

        return currentValue
    }

    private func editableDescendantTextValues(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 4 else {
            return []
        }

        var values: [String] = []
        for child in copyChildren(of: element) {
            if stringValue(of: child, attribute: kAXRoleAttribute) == kAXStaticTextRole as String,
               let value = stringValue(of: child, attribute: kAXValueAttribute)
                    ?? stringValue(of: child, attribute: kAXTitleAttribute)
            {
                let normalized = normalizeEditablePlaceholderText(value)
                if !normalized.isEmpty {
                    values.append(normalized)
                }
            }

            values.append(contentsOf: editableDescendantTextValues(in: child, depth: depth + 1))
        }

        return values
    }

    private func looksLikeEditablePlaceholder(_ value: String) -> Bool {
        let normalized = normalizeEditablePlaceholderText(value)
        return normalized == "沟通时请保持“公开可接受”"
    }

    private func normalizeEditablePlaceholderText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clickFrame(for record: ElementRecord, snapshot: AppSnapshot) -> CGRect? {
        guard let frame = record.localFrame else {
            return nil
        }

        guard
            !record.isSyntheticText,
            let element = record.element,
            stringValue(of: element, attribute: kAXRoleAttribute) == kAXStaticTextRole as String,
            let rowFrame = containingRowFrame(for: element, textFrame: frame, windowBounds: snapshot.windowBounds)
        else {
            return frame
        }

        return rowFrame
    }

    private func containingRowFrame(for element: AXUIElement, textFrame: CGRect, windowBounds: CGRect?) -> CGRect? {
        let textCenter = CGPoint(x: textFrame.midX, y: textFrame.midY)
        var current = element

        for _ in 0..<4 {
            guard let parent = copyParent(of: current) else {
                return nil
            }

            if let frame = localFrame(of: parent, windowBounds: windowBounds),
               frame.insetBy(dx: -2, dy: -2).contains(textCenter),
               frame.width >= textFrame.width + 40,
               frame.height >= textFrame.height,
               frame.height <= max(textFrame.height * 4, 96)
            {
                return frame
            }

            current = parent
        }

        return nil
    }

    private func copyActions(for element: AXUIElement) -> [String]? {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success else {
            return nil
        }

        return actions as? [String]
    }

    private func copyChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let value else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }

    private func copyParent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func stringValue(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return value as? String
    }

    private func localFrame(of element: AXUIElement, windowBounds: CGRect?) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard
            positionResult == .success,
            sizeResult == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position), AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }

        let frame = CGRect(origin: position, size: size)
        guard let windowBounds else {
            return frame
        }

        return windowRelativeFrame(elementFrame: frame, windowBounds: windowBounds)
    }

    private func globalPoint(for record: ElementRecord, snapshot: AppSnapshot) throws -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: CGPoint(x: frame.midX, y: frame.midY)
        )
    }

    private func clickPoint(for record: ElementRecord, snapshot: AppSnapshot) -> CGPoint? {
        clickActionPoints(for: record, snapshot: snapshot).first ?? localCenter(for: record)
    }

    private func screenshotToGlobalPoint(snapshot: AppSnapshot, x: Double, y: Double) throws -> CGPoint {
        try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: screenshotPixelToWindowPointInSnapshot(
                snapshot: snapshot,
                point: CGPoint(x: x, y: y)
            )
        )
    }

    private func screenshotPixelToWindowPointInSnapshot(snapshot: AppSnapshot, point: CGPoint) -> CGPoint {
        screenshotPixelToWindowPoint(
            point,
            screenshotPixelSize: snapshot.screenshotPixelSize,
            windowBounds: snapshot.windowBounds
        )
    }

    private func windowPointToGlobalPoint(snapshot: AppSnapshot, point: CGPoint) throws -> CGPoint {
        guard let windowBounds = snapshot.windowBounds else {
            let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
            throw ComputerUseError.stateUnavailable("No window bounds are available for \(appReference). Run get_app_state after bringing the app on screen.")
        }

        return CGPoint(x: windowBounds.minX + point.x, y: windowBounds.minY + point.y)
    }

    private func fixtureIdentifier(at point: CGPoint, snapshot: AppSnapshot) throws -> String {
        let candidates = snapshot.elements.values
            .filter { $0.identifier != nil && ($0.localFrame?.contains(point) ?? false) }
            .sorted { lhs, rhs in
                let lhsArea = (lhs.localFrame?.width ?? 0) * (lhs.localFrame?.height ?? 0)
                let rhsArea = (rhs.localFrame?.width ?? 0) * (rhs.localFrame?.height ?? 0)
                return lhsArea < rhsArea
            }

        guard let identifier = candidates.first?.identifier else {
            throw ComputerUseError.invalidArguments("No fixture element contains coordinate (\(Int(point.x)), \(Int(point.y)))")
        }

        return identifier
    }

    private func visualCursorTarget(for record: ElementRecord, snapshot: AppSnapshot) -> VisualCursorTarget? {
        makeVisualCursorTarget(
            localFrame: record.localFrame,
            windowBounds: snapshot.windowBounds,
            targetWindowID: snapshot.targetWindowID,
            targetWindowLayer: snapshot.targetWindowLayer
        )
    }

    private func fixtureVisualCursorTarget(identifier: String, snapshot: AppSnapshot) -> VisualCursorTarget? {
        let record = snapshot.elements.values.first { $0.identifier == identifier }
        return record.flatMap { visualCursorTarget(for: $0, snapshot: snapshot) }
    }

    private func debugInputFallback(tool: String, targetDescription: String, snapshot: AppSnapshot) {
        guard inputFallbackDebugEnabled(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
        fputs(
            "[overseer-computer-use] global pointer fallback tool=\(tool) app=\(appReference) target=\(targetDescription)\n",
            stderr
        )
    }

    private func debugClickDecision(_ message: String) {
        guard inputFallbackDebugEnabled(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        fputs("[overseer-computer-use] click decision \(message)\n", stderr)
    }

    private func clickDebugDescription(_ record: ElementRecord) -> String {
        let role = record.element.flatMap { stringValue(of: $0, attribute: kAXRoleAttribute) } ?? "nil"
        let actions = record.rawActions.joined(separator: ",")
        let frame = record.localFrame.map { "x=\(Int($0.minX)) y=\(Int($0.minY)) w=\(Int($0.width)) h=\(Int($0.height))" } ?? "nil"
        return "index=\(record.index) role=\(role) synthetic=\(record.isSyntheticText) actions=[\(actions)] frame=\(frame)"
    }

    private func integralScrollPageCount(_ pages: Double) -> Int? {
        let rounded = pages.rounded(.toNearestOrAwayFromZero)
        guard abs(pages - rounded) < 0.000001 else {
            return nil
        }
        return max(Int(rounded), 1)
    }

    private func performScrollEvent(
        at point: CGPoint,
        direction: String,
        pages: Double,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "scroll",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.scrollGlobally(at: eventPoint, direction: direction, pages: pages)
            return
        }

        try InputSimulation.scrollTargeted(at: eventPoint, direction: direction, pages: pages, pid: snapshot.app.pid)
    }

    private func performDragEvent(
        from start: CGPoint,
        to end: CGPoint,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        let eventStart = inputEventPoint(fromScreenStatePoint: start)
        let eventEnd = inputEventPoint(fromScreenStatePoint: end)

        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "drag",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.dragGlobally(from: eventStart, to: eventEnd)
            return
        }

        try InputSimulation.dragTargeted(from: eventStart, to: eventEnd, pid: snapshot.app.pid)
    }

    private func performNonAXClickFallback(
        at point: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "click",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.clickGlobally(at: eventPoint, button: button, clickCount: clickCount)
            return
        }

        do {
            try InputSimulation.clickTargeted(
                at: eventPoint,
                button: button,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
            return
        } catch {
            guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
                throw ComputerUseError.message(
                    "click could not be handled through accessibility, and global pointer fallback is disabled. Set OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 to allow physical-pointer fallback for this process."
                )
            }
        }
    }

    private func performExplicitMouseClick(
        method: ClickMethod,
        at point: CGPoint,
        windowPoint: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        switch method {
        case .appPost:
            debugClickDecision("requested=app_post executed=pid_post target=\(targetDescription)")
            try InputSimulation.clickTargeted(
                at: eventPoint,
                button: button,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
        case .skyClick:
            guard let windowBounds = snapshot.windowBounds, let windowID = snapshot.targetWindowID else {
                throw ComputerUseError.stateUnavailable(
                    "click_method 'sky_click' requires a current on-screen target window. Run get_app_state again."
                )
            }
            debugClickDecision("requested=sky_click executed=skylight_pid_post target=\(targetDescription)")
            try InputSimulation.clickWithSkyLight(
                at: eventPoint,
                windowPoint: windowPoint,
                windowBounds: windowBounds,
                windowID: windowID,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
        case .global:
            guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
                throw ComputerUseError.message(
                    "click_method 'global' requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 because it may move the system pointer and change foreground focus"
                )
            }
            debugClickDecision("requested=global executed=global_hid target=\(targetDescription)")
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.clickGlobally(at: eventPoint, button: button, clickCount: clickCount)
        case .auto, .accessibility:
            throw ComputerUseError.message(
                "click_method '\(method.rawValue)' is not a direct mouse event method"
            )
        }
    }

    /// Internal (not private) so tests can pin the result shape: text item,
    /// optional PNG item, and top-level state_id.
    func snapshotResult(for snapshot: AppSnapshot, style: SnapshotTextStyle) -> ToolCallResult {
        var content = [ToolResultContentItem.text(snapshot.renderedText(style: style))]
        if let screenshotPNGData = snapshot.screenshotPNGData {
            content.append(.pngImage(screenshotPNGData))
        }
        return ToolCallResult(content: content, stateID: snapshot.stateID.isEmpty ? nil : snapshot.stateID)
    }

    /// Non-disruptive inspection for the `inspect` CLI command: resolves only
    /// running apps (never launches), builds the snapshot with the read-only
    /// recovery policy (never activates), and does not touch the snapshot
    /// cache used by actions.
    public func inspectAppState(
        app query: String,
        windowTitleHint: String? = nil,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults
    ) throws -> ToolCallResult {
        let app = try AppDiscovery.resolveRunning(query)
        let snapshot = try SnapshotBuilder.build(
            for: app,
            textLimit: textLimit,
            treeLimits: treeLimits,
            recoveryPolicy: .readOnly,
            includeScreenshot: true,
            windowTitleHint: windowTitleHint
        )
        return snapshotResult(for: snapshot, style: .fullState)
    }
}
