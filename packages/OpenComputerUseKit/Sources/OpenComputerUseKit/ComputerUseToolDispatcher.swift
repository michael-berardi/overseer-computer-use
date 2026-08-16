import Foundation

func normalizedElementIndexArgument(_ value: Any?) -> String? {
    if let string = value as? String {
        return string.isEmpty ? nil : string
    }

    // CFBoolean NSNumbers (JSON true/false) bridge-cast to Int/Double, so the
    // boolean check must run before any numeric branch.
    if let number = value as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
        return nil
    }

    if let integer = value as? Int {
        return String(integer)
    }

    if let number = value as? NSNumber {
        return normalizedElementIndexNumber(number.doubleValue)
    }

    if let double = value as? Double {
        return normalizedElementIndexNumber(double)
    }

    return nil
}

private func normalizedElementIndexNumber(_ value: Double) -> String? {
    guard value.isFinite, value.rounded(.towardZero) == value else {
        return nil
    }

    guard value >= Double(Int.min), value <= Double(Int.max) else {
        return nil
    }

    return String(Int(value))
}

public final class ComputerUseToolDispatcher {
    private let service: ComputerUseService
    private let telemetry: TelemetryCoordinator

    public init(
        service: ComputerUseService = ComputerUseService(),
        telemetry: TelemetryCoordinator = TelemetryCoordinator()
    ) {
        self.service = service
        self.telemetry = telemetry
    }

    public func callTool(name: String, arguments: [String: Any]) throws -> ToolCallResult {
        try ToolSchemaValidator.validate(tool: name, arguments: arguments)
        let stateID = optionalString("state_id", in: arguments)

        switch name {
        case "list_apps":
            return service.listApps()
        case "get_app_state":
            return try service.getAppState(
                app: requireString("app", in: arguments),
                textLimit: try optionalTextLimit("text_limit", in: arguments) ?? .defaults,
                treeLimits: AccessibilityTreeLimits.defaults.replacing(
                    maxNodeCount: try optionalPositiveInt("max_tree_nodes", in: arguments),
                    maxDepth: try optionalPositiveInt("max_tree_depth", in: arguments)
                ),
                includeScreenshot: try optionalBool("include_screenshot", in: arguments) ?? true
            )
        case "click":
            return try service.click(
                app: requireString("app", in: arguments),
                elementIndex: optionalElementIndex(in: arguments),
                x: try optionalDouble("x", in: arguments),
                y: try optionalDouble("y", in: arguments),
                clickCount: try optionalPositiveInt("click_count", in: arguments) ?? 1,
                mouseButton: try optionalMouseButton(in: arguments) ?? MouseButtonKind.left.rawValue,
                clickMethod: try parseClickMethod(optionalString("click_method", in: arguments)),
                stateID: stateID
            )
        case "perform_secondary_action":
            return try service.performSecondaryAction(
                app: requireString("app", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                action: requireString("action", in: arguments),
                stateID: stateID
            )
        case "scroll":
            return try service.scroll(
                app: requireString("app", in: arguments),
                direction: requireString("direction", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                pages: try optionalDouble("pages", in: arguments) ?? 1,
                stateID: stateID
            )
        case "drag":
            return try service.drag(
                app: requireString("app", in: arguments),
                fromX: requireDouble("from_x", in: arguments),
                fromY: requireDouble("from_y", in: arguments),
                toX: requireDouble("to_x", in: arguments),
                toY: requireDouble("to_y", in: arguments),
                stateID: stateID
            )
        case "type_text":
            return try service.typeText(
                app: requireString("app", in: arguments),
                text: requireString("text", in: arguments),
                stateID: stateID
            )
        case "press_key":
            return try service.pressKey(
                app: requireString("app", in: arguments),
                key: requireString("key", in: arguments),
                stateID: stateID
            )
        case "set_value":
            return try service.setValue(
                app: requireString("app", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                value: requireString("value", in: arguments),
                stateID: stateID
            )
        default:
            throw ComputerUseError.unsupportedTool(name)
        }
    }

    public func callToolAsResult(name: String, arguments: [String: Any]) -> ToolCallResult {
        callToolAsResult(name: name, arguments: arguments, callIndex: nil)
    }

    func callToolAsResult(name: String, arguments: [String: Any], callIndex: Int?) -> ToolCallResult {
        do {
            try ToolSchemaValidator.validate(tool: name, arguments: arguments)
        } catch {
            let info = computerUseErrorInfo(for: error, phase: .preflight, callIndex: callIndex)
            let result = ToolCallResult.text(info.message, errorInfo: info)
            telemetry.recordToolResult(toolName: name, succeeded: false)
            return result
        }

        let result: ToolCallResult
        do {
            result = try callTool(name: name, arguments: arguments)
        } catch {
            let info = computerUseErrorInfo(for: error, phase: .execute, callIndex: callIndex)
            result = ToolCallResult.text(info.message, errorInfo: info)
        }
        telemetry.recordToolResult(toolName: name, succeeded: !result.isError)
        return result
    }

    private func requireString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ComputerUseError.missingArgument(key)
        }

        return value
    }

    private func optionalString(_ key: String, in arguments: [String: Any]) -> String? {
        arguments[key] as? String
    }

    private func optionalBool(_ key: String, in arguments: [String: Any]) throws -> Bool? {
        guard let value = arguments[key] else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return number.boolValue
        }

        throw ComputerUseError.invalidArguments("\(key) must be a boolean")
    }

    private func optionalTextLimit(_ key: String, in arguments: [String: Any]) throws -> SnapshotTextLimit? {
        guard let value = arguments[key] else {
            return nil
        }

        if let string = value as? String {
            guard string.lowercased() == SnapshotTextLimit.maxKeyword else {
                throw ComputerUseError.invalidArguments("\(key) must be a positive integer or max")
            }
            return .max
        }

        let maxCount = try positiveInt(from: value, key: key, expectedDescription: "a positive integer or max")
        return SnapshotTextLimit(maxCount: maxCount)
    }

    private func requireElementIndex(in arguments: [String: Any]) throws -> String {
        guard let value = optionalElementIndex(in: arguments) else {
            throw ComputerUseError.missingArgument("element_index")
        }

        return value
    }

    private func optionalElementIndex(in arguments: [String: Any]) -> String? {
        normalizedElementIndexArgument(arguments["element_index"])
    }

    private func requireDouble(_ key: String, in arguments: [String: Any]) throws -> Double {
        guard let value = try optionalDouble(key, in: arguments) else {
            throw ComputerUseError.missingArgument(key)
        }

        return value
    }

    private func optionalDouble(_ key: String, in arguments: [String: Any]) throws -> Double? {
        guard let raw = arguments[key] else {
            return nil
        }

        if let number = raw as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            throw ComputerUseError.invalidArguments("\(key) must be a number")
        }

        if let double = raw as? Double {
            return double
        }

        if let integer = raw as? Int {
            return Double(integer)
        }

        if let number = raw as? NSNumber {
            return number.doubleValue
        }

        return nil
    }

    private func optionalMouseButton(in arguments: [String: Any]) throws -> String? {
        guard let raw = optionalString("mouse_button", in: arguments) else {
            return nil
        }

        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard MouseButtonKind(rawValue: normalized) != nil else {
            throw ComputerUseError.invalidArguments(
                "mouse_button must be one of \(MouseButtonKind.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        return normalized
    }

    private func optionalPositiveInt(_ key: String, in arguments: [String: Any]) throws -> Int? {
        guard let value = arguments[key] else {
            return nil
        }

        return try positiveInt(from: value, key: key, expectedDescription: "a positive integer")
    }

    private func positiveInt(from value: Any, key: String, expectedDescription: String) throws -> Int {
        // CFBoolean NSNumbers (JSON true/false) bridge-cast to Int/Double, so
        // the boolean check must run before any numeric branch.
        if let number = value as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
        }

        if let integer = value as? Int {
            return try validatePositiveInt(integer, key: key, expectedDescription: expectedDescription)
        }

        if let double = value as? Double {
            return try validatePositiveWholeNumber(double, key: key, expectedDescription: expectedDescription)
        }

        if let number = value as? NSNumber {
            return try validatePositiveWholeNumber(number.doubleValue, key: key, expectedDescription: expectedDescription)
        }

        throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
    }

    private func validatePositiveWholeNumber(_ value: Double, key: String, expectedDescription: String) throws -> Int {
        guard value.isFinite, value.rounded(.towardZero) == value else {
            throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
        }

        guard value >= Double(Int.min), value <= Double(Int.max) else {
            throw ComputerUseError.invalidArguments("\(key) is outside the supported integer range")
        }

        return try validatePositiveInt(Int(value), key: key, expectedDescription: expectedDescription)
    }

    private func validatePositiveInt(_ value: Int, key: String, expectedDescription: String) throws -> Int {
        guard value > 0 else {
            throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
        }
        return value
    }
}

public struct OpenComputerUseCallSpec {
    public let tool: String
    public let arguments: [String: Any]

    public init(tool: String, arguments: [String: Any]) {
        self.tool = tool
        self.arguments = arguments
    }
}

public struct OpenComputerUseCallOutput {
    public let jsonObject: Any
    public let hasToolError: Bool
    public let errorInfo: ComputerUseErrorInfo?

    public init(jsonObject: Any, hasToolError: Bool, errorInfo: ComputerUseErrorInfo? = nil) {
        self.jsonObject = jsonObject
        self.hasToolError = hasToolError
        self.errorInfo = errorInfo
    }

    public func jsonText() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode call output as JSON.")
        }
        return text
    }
}

public typealias OpenComputerUseSleepHandler = (TimeInterval) -> Void

/// Validate every call in a sequence against the tool schemas before any
/// call executes. Returns nil when all calls are valid; otherwise the
/// structured failure for the first invalid call (0-based `callIndex`).
public func preflightOpenComputerUseCalls(_ calls: [OpenComputerUseCallSpec]) -> ComputerUseErrorInfo? {
    for (index, call) in calls.enumerated() {
        do {
            try ToolSchemaValidator.validate(tool: call.tool, arguments: call.arguments)
        } catch {
            return computerUseErrorInfo(for: error, phase: .preflight, callIndex: index)
        }
    }

    return nil
}

public func runOpenComputerUseCall(
    _ invocation: OpenComputerUseCallInvocation,
    service: ComputerUseService = ComputerUseService(),
    sleepHandler: OpenComputerUseSleepHandler = { Thread.sleep(forTimeInterval: $0) }
) throws -> OpenComputerUseCallOutput {
    let dispatcher = ComputerUseToolDispatcher(service: service)

    switch invocation {
    case let .single(toolName, argumentsJSON, argumentsFile):
        let arguments = try readOpenComputerUseToolArguments(
            json: argumentsJSON,
            file: argumentsFile
        )

        if let preflightError = preflightOpenComputerUseCalls([
            OpenComputerUseCallSpec(tool: toolName, arguments: arguments),
        ]) {
            return OpenComputerUseCallOutput(
                jsonObject: [
                    "error": preflightError.asDictionary,
                    "calls_executed": 0,
                ],
                hasToolError: true,
                errorInfo: preflightError
            )
        }

        let result = dispatcher.callToolAsResult(name: toolName, arguments: arguments)
        return OpenComputerUseCallOutput(
            jsonObject: result.asDictionary,
            hasToolError: result.isError,
            errorInfo: result.errorInfo
        )

    case let .sequence(callsJSON, callsFile, interCallDelay):
        let calls = try readOpenComputerUseCallSequence(json: callsJSON, file: callsFile)

        if let preflightError = preflightOpenComputerUseCalls(calls) {
            return OpenComputerUseCallOutput(
                jsonObject: [
                    "error": preflightError.asDictionary,
                    "calls_executed": 0,
                ],
                hasToolError: true,
                errorInfo: preflightError
            )
        }

        var outputs: [[String: Any]] = []
        var hasToolError = false
        var firstErrorInfo: ComputerUseErrorInfo?

        for (index, call) in calls.enumerated() {
            let result = dispatcher.callToolAsResult(name: call.tool, arguments: call.arguments, callIndex: index)
            outputs.append([
                "tool": call.tool,
                "result": result.asDictionary,
            ])

            if result.isError {
                hasToolError = true
                firstErrorInfo = result.errorInfo
                break
            }

            if index < calls.count - 1, interCallDelay > 0 {
                sleepHandler(interCallDelay)
            }
        }

        return OpenComputerUseCallOutput(
            jsonObject: outputs,
            hasToolError: hasToolError,
            errorInfo: firstErrorInfo
        )
    }
}

public func readOpenComputerUseToolArguments(
    json: String?,
    file: String?
) throws -> [String: Any] {
    guard let source = try readOpenComputerUseJSONSource(json: json, file: file) else {
        return [:]
    }

    let object = try decodeOpenComputerUseJSONObject(source)
    guard let arguments = object as? [String: Any] else {
        throw OpenComputerUseCLIError(message: "--args must be a JSON object", helpCommand: "call")
    }

    return arguments
}

public func readOpenComputerUseCallSequence(
    json: String?,
    file: String?
) throws -> [OpenComputerUseCallSpec] {
    guard let source = try readOpenComputerUseJSONSource(json: json, file: file) else {
        throw OpenComputerUseCLIError(message: "call sequence requires --calls or --calls-file", helpCommand: "call")
    }

    let object = try decodeOpenComputerUseJSONObject(source)
    guard let array = object as? [Any] else {
        throw OpenComputerUseCLIError(message: "--calls must be a JSON array", helpCommand: "call")
    }

    return try array.enumerated().map { index, item in
        guard let dictionary = item as? [String: Any] else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) must be a JSON object",
                helpCommand: "call"
            )
        }

        guard let tool = (dictionary["tool"] ?? dictionary["name"]) as? String, !tool.isEmpty else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) requires a non-empty tool",
                helpCommand: "call"
            )
        }

        let rawArguments = dictionary["args"] ?? dictionary["arguments"] ?? [:]
        guard let arguments = rawArguments as? [String: Any] else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) args must be a JSON object",
                helpCommand: "call"
            )
        }

        return OpenComputerUseCallSpec(tool: tool, arguments: arguments)
    }
}

private func readOpenComputerUseJSONSource(json: String?, file: String?) throws -> String? {
    if json != nil, file != nil {
        throw OpenComputerUseCLIError(message: "Use either inline JSON or a JSON file, not both", helpCommand: "call")
    }

    if let json {
        return json
    }

    guard let file else {
        return nil
    }

    do {
        return try String(contentsOfFile: file, encoding: .utf8)
    } catch {
        throw OpenComputerUseCLIError(
            message: "Unable to read JSON file \(file): \(error.localizedDescription)",
            helpCommand: "call"
        )
    }
}

private func decodeOpenComputerUseJSONObject(_ source: String) throws -> Any {
    guard let data = source.data(using: .utf8) else {
        throw OpenComputerUseCLIError(message: "JSON input must be UTF-8 text", helpCommand: "call")
    }

    do {
        return try JSONSerialization.jsonObject(with: data)
    } catch {
        throw OpenComputerUseCLIError(
            message: "Invalid JSON input: \(error.localizedDescription)",
            helpCommand: "call"
        )
    }
}
