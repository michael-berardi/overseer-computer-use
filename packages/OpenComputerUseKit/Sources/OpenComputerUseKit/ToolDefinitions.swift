import Foundation

public struct ToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let annotations: [String: Any]
    public let inputSchema: [String: Any]

    public init(name: String, description: String, annotations: [String: Any], inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.annotations = annotations
        self.inputSchema = inputSchema
    }

    public var asDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]

        if !annotations.isEmpty {
            dictionary["annotations"] = annotations
        }

        return dictionary
    }
}

public enum ToolDefinitions {
    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "click",
            description: "Click an element by index or pixel coordinates from screenshot. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element index to click"),
                    "x": numberProperty(description: "X coordinate in screenshot pixel coordinates"),
                    "y": numberProperty(description: "Y coordinate in screenshot pixel coordinates"),
                    "click_count": positiveIntegerProperty(description: "Number of clicks. Defaults to 1"),
                    "mouse_button": stringProperty(
                        description: "Mouse button to click. Defaults to left.",
                        enumValues: ["left", "right", "middle"]
                    ),
                    "click_method": stringProperty(
                        description: "Click implementation: auto (default), accessibility, app_post, sky_click, or global. Accessibility requires element_index. app_post sends a public event directly to the target app. sky_click uses the macOS SkyLight background window path. Global may move the system pointer and requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1.",
                        enumValues: ClickMethod.allCases.map(\.rawValue)
                    ),
                    "state_id": stateIDProperty(),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "drag",
            description: "Drag from one point to another using pixel coordinates. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "from_x": numberProperty(description: "Start X coordinate"),
                    "from_y": numberProperty(description: "Start Y coordinate"),
                    "to_x": numberProperty(description: "End X coordinate"),
                    "to_y": numberProperty(description: "End Y coordinate"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "from_x", "from_y", "to_x", "to_y"]
            )
        ),
        ToolDefinition(
            name: "get_app_state",
            description: "Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app. This tool is part of plugin `Computer Use`.",
            annotations: readOnlyAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "text_limit": textLimitProperty(description: "Maximum text characters to return. Use \"max\" for full text. Defaults to 500."),
                    "max_tree_nodes": positiveIntegerProperty(description: "Maximum accessibility tree nodes to render. Defaults to 1200."),
                    "max_tree_depth": positiveIntegerProperty(description: "Maximum accessibility tree depth to render. Defaults to 64."),
                    "include_screenshot": booleanProperty(description: "Include a screenshot image in the result. Defaults to true."),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "list_apps",
            description: "List the apps on this computer. Returns the set of apps that are currently running, as well as any that have been used in the last 14 days, including details on usage frequency. This tool is part of plugin `Computer Use`.",
            annotations: readOnlyAnnotations(),
            inputSchema: objectSchema(properties: [:], required: [])
        ),
        ToolDefinition(
            name: "perform_secondary_action",
            description: "Invoke a secondary accessibility action exposed by an element. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "action": stringProperty(description: "Secondary accessibility action name"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "element_index", "action"]
            )
        ),
        ToolDefinition(
            name: "press_key",
            description: "Press a key or key-combination on the keyboard, including modifier and navigation keys.\n  - This supports xdotool's `key` syntax.\n  - Examples: \"a\", \"Return\", \"Tab\", \"super+c\", \"Up\", \"KP_0\" (for the numpad 0 key). This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "key": stringProperty(description: "Key or key combination to press"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "key"]
            )
        ),
        ToolDefinition(
            name: "scroll",
            description: "Scroll an element in a direction by a number of pages. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "direction": stringProperty(description: "Scroll direction: up, down, left, or right"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "pages": numberProperty(description: "Number of pages to scroll. Fractional values are supported. Defaults to 1"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "element_index", "direction"]
            )
        ),
        ToolDefinition(
            name: "set_value",
            description: "Set the value of a settable accessibility element. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "value": stringProperty(description: "Value to assign"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "element_index", "value"]
            )
        ),
        ToolDefinition(
            name: "type_text",
            description: "Type literal text using keyboard input. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "text": stringProperty(description: "Literal text to type"),
                    "state_id": stateIDProperty(),
                ],
                required: ["app", "text"]
            )
        ),
    ]
}

private func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties,
        "additionalProperties": false,
    ]

    if !required.isEmpty {
        schema["required"] = required
    }

    return schema
}

private func defaultAnnotations() -> [String: Any] {
    [
        "destructiveHint": false,
        "openWorldHint": false,
    ]
}

private func readOnlyAnnotations() -> [String: Any] {
    [
        "destructiveHint": false,
        "idempotentHint": true,
        "openWorldHint": false,
        "readOnlyHint": true,
    ]
}

private func stringProperty(description: String, enumValues: [String]? = nil) -> [String: Any] {
    var property: [String: Any] = [
        "type": "string",
        "description": description,
    ]

    if let enumValues {
        property["enum"] = enumValues
    }

    return property
}

private func positiveIntegerProperty(description: String) -> [String: Any] {
    [
        "type": "integer",
        "minimum": 1,
        "description": description,
    ]
}

private func textLimitProperty(description: String) -> [String: Any] {
    [
        "anyOf": [
            [
                "type": "integer",
                "minimum": 1,
            ],
            [
                "type": "string",
                "enum": [SnapshotTextLimit.maxKeyword],
            ],
        ],
        "description": description,
    ]
}

private func numberProperty(description: String) -> [String: Any] {
    [
        "type": "number",
        "description": description,
    ]
}

private func booleanProperty(description: String) -> [String: Any] {
    [
        "type": "boolean",
        "description": description,
    ]
}

private func stateIDProperty() -> [String: Any] {
    stringProperty(
        description: "Optional state_id from the last get_app_state result. When provided, the action fails with a stale_state error before mutating if the app's state has changed."
    )
}

/// JSON payload for the `tools` CLI command: one tool's definition when
/// `name` is given, otherwise the full catalog.
public func openComputerUseToolsPayload(name: String?) throws -> Any {
    if let name {
        guard let definition = ToolDefinitions.all.first(where: { $0.name == name }) else {
            throw ComputerUseError.unsupportedTool(name)
        }
        return definition.asDictionary
    }

    return ToolDefinitions.all.map(\.asDictionary)
}

/// Human-readable listing for the `tools` CLI command.
public func openComputerUseToolsText(name: String?) throws -> String {
    if let name {
        guard let definition = ToolDefinitions.all.first(where: { $0.name == name }) else {
            throw ComputerUseError.unsupportedTool(name)
        }

        var lines = ["\(definition.name) — \(definition.description)"]
        let schema = definition.inputSchema
        let required = schema["required"] as? [String] ?? []
        let properties = schema["properties"] as? [String: Any] ?? [:]
        if !properties.isEmpty {
            lines.append("arguments:")
            for key in properties.keys.sorted() {
                let requiredMark = required.contains(key) ? " (required)" : ""
                lines.append("  \(key)\(requiredMark)")
            }
        }
        return lines.joined(separator: "\n")
    }

    return ToolDefinitions.all
        .map { "\($0.name) — \($0.description)" }
        .joined(separator: "\n")
}

/// Validates tool call arguments against the declared input schemas before
/// any tool executes. Used for CLI sequence preflight so an invalid later call
/// produces zero prior mutations.
///
/// Coercions intentionally mirror the dispatcher's runtime normalization:
/// numbers are accepted for number/integer properties, and `element_index`
/// accepts a string or a whole number.
public enum ToolSchemaValidator {
    public static func isKnownTool(_ name: String) -> Bool {
        ToolDefinitions.all.contains { $0.name == name }
    }

    /// Throws `ComputerUseError.unsupportedTool` for an unknown tool and
    /// `ComputerUseError.invalidArguments` for the first schema violation.
    public static func validate(tool: String, arguments: [String: Any]) throws {
        guard let definition = ToolDefinitions.all.first(where: { $0.name == tool }) else {
            throw ComputerUseError.unsupportedTool(tool)
        }

        let schema = definition.inputSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let required = schema["required"] as? [String] ?? []
        let additionalPropertiesAllowed = schema["additionalProperties"] as? Bool ?? true

        for key in required {
            guard let value = arguments[key], !(value is NSNull) else {
                throw ComputerUseError.invalidArguments("missing required argument '\(key)' for tool '\(tool)'")
            }
        }

        for (key, value) in arguments {
            if value is NSNull {
                continue
            }

            guard let property = properties[key] as? [String: Any] else {
                if !additionalPropertiesAllowed {
                    throw ComputerUseError.invalidArguments("unknown argument '\(key)' for tool '\(tool)'")
                }
                continue
            }

            try validateValue(value, forKey: key, property: property, tool: tool)
        }
    }

    private static func validateValue(
        _ value: Any,
        forKey key: String,
        property: [String: Any],
        tool: String
    ) throws {
        if let anyOf = property["anyOf"] as? [[String: Any]] {
            var lastError: ComputerUseError?
            for option in anyOf {
                do {
                    try validateValue(value, forKey: key, property: option, tool: tool)
                    return
                } catch let error as ComputerUseError {
                    lastError = error
                }
            }
            throw lastError ?? ComputerUseError.invalidArguments("'\(key)' is invalid for tool '\(tool)'")
        }

        if let allowed = property["enum"] as? [String] {
            guard let string = value as? String, allowed.contains(string) else {
                throw ComputerUseError.invalidArguments(
                    "'\(key)' must be one of \(allowed.joined(separator: ", ")) for tool '\(tool)'"
                )
            }
            return
        }

        switch property["type"] as? String {
        case "string":
            if key == "element_index", normalizedElementIndexArgument(value) != nil {
                return
            }
            guard value is String else {
                throw ComputerUseError.invalidArguments("'\(key)' must be a string for tool '\(tool)'")
            }
        case "boolean":
            guard isBoolean(value) else {
                throw ComputerUseError.invalidArguments("'\(key)' must be a boolean for tool '\(tool)'")
            }
        case "integer":
            guard let integer = numericValue(value) else {
                throw ComputerUseError.invalidArguments("'\(key)' must be an integer for tool '\(tool)'")
            }
            guard integer.rounded(.towardZero) == integer else {
                throw ComputerUseError.invalidArguments("'\(key)' must be an integer for tool '\(tool)'")
            }
            if let minimum = property["minimum"] as? Double, integer < minimum {
                throw ComputerUseError.invalidArguments("'\(key)' must be >= \(Int(minimum)) for tool '\(tool)'")
            }
            if let minimum = property["minimum"] as? Int, integer < Double(minimum) {
                throw ComputerUseError.invalidArguments("'\(key)' must be >= \(minimum) for tool '\(tool)'")
            }
        case "number":
            guard numericValue(value) != nil else {
                throw ComputerUseError.invalidArguments("'\(key)' must be a number for tool '\(tool)'")
            }
        default:
            return
        }
    }

    private static func isBoolean(_ value: Any) -> Bool {
        if value is Bool {
            return true
        }
        if let number = value as? NSNumber {
            return CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
        }
        return false
    }

    private static func numericValue(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let integer = value as? Int {
            return Double(integer)
        }
        return nil
    }
}
