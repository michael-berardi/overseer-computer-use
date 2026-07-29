import Foundation

public enum OpenComputerUseCLICommand: Equatable {
    case launchOnboarding
    case mcp
    case doctor(statusOnly: Bool, json: Bool)
    case listApps
    case targets(runningOnly: Bool, json: Bool)
    case tools(name: String?, json: Bool)
    case inspect(app: String, windowTitle: String?, json: Bool, mediaDir: String?)
    case snapshot(app: String, textLimit: SnapshotTextLimit = .defaults, treeLimits: AccessibilityTreeLimits = .defaults)
    case call(OpenComputerUseCallInvocation)
    case preview(app: String, options: PreviewCaptureOptions)
    case record(app: String, options: RecordingCaptureOptions)
    case turnEnded(payload: String?)
    case help(command: String?)
    case version
}

public enum OpenComputerUseCallInvocation: Equatable {
    case single(toolName: String, argumentsJSON: String?, argumentsFile: String?)
    case sequence(callsJSON: String?, callsFile: String?, interCallDelay: TimeInterval)
}

public let openComputerUseDefaultInterCallDelay: TimeInterval = 1

public func shouldUseMacOSAppAgentProxy(
    command: OpenComputerUseCLICommand,
    proxyDisabled: Bool,
    appBundleAvailable: Bool,
    runningFromLaunchServicesAppInstance: Bool
) -> Bool {
    guard !proxyDisabled, appBundleAvailable else {
        return false
    }

    switch command {
    case .launchOnboarding:
        return !runningFromLaunchServicesAppInstance
    case let .doctor(statusOnly, _):
        // Status-only doctor only prints diagnostics; it must never touch
        // the app agent (which may present onboarding UI).
        return !statusOnly
    case .tools:
        // Static catalog; never needs the app agent.
        return false
    case .mcp, .listApps, .targets, .inspect, .snapshot, .call:
        return true
    // preview/record run long-lived ScreenCaptureKit sessions in the CLI
    // process so signals cancel them cleanly and no viewer UI ever opens.
    case .preview, .record, .turnEnded, .help, .version:
        return false
    }
}

public struct OpenComputerUseCLIError: LocalizedError, Equatable {
    public let message: String
    public let helpCommand: String?

    public init(message: String, helpCommand: String? = nil) {
        self.message = message
        self.helpCommand = helpCommand
    }

    public var errorDescription: String? {
        var lines = [message]
        lines.append("")
        lines.append(openComputerUseHelpText(command: helpCommand))
        return lines.joined(separator: "\n")
    }
}

public func parseOpenComputerUseCLI(arguments: [String]) throws -> OpenComputerUseCLICommand {
    guard let first = arguments.first else {
        return .launchOnboarding
    }

    switch first {
    case "-h", "--help", "help":
        if arguments.count > 2 {
            throw OpenComputerUseCLIError(message: "help accepts at most one command", helpCommand: nil)
        }

        return .help(command: arguments.dropFirst().first)
    case "-v", "--version", "version":
        guard arguments.count == 1 else {
            throw OpenComputerUseCLIError(message: "version does not accept any arguments", helpCommand: nil)
        }

        return .version
    case "mcp":
        return try parseSimpleCommand(name: "mcp", arguments: Array(arguments.dropFirst()), result: .mcp)
    case "doctor":
        return try parseDoctor(arguments: Array(arguments.dropFirst()))
    case "list-apps":
        return try parseSimpleCommand(name: "list-apps", arguments: Array(arguments.dropFirst()), result: .listApps)
    case "targets":
        return try parseTargets(arguments: Array(arguments.dropFirst()))
    case "tools":
        return try parseTools(arguments: Array(arguments.dropFirst()))
    case "inspect":
        return try parseInspect(arguments: Array(arguments.dropFirst()))
    case "call":
        return try parseCall(arguments: Array(arguments.dropFirst()))
    case "turn-ended":
        return try parseTurnEnded(arguments: Array(arguments.dropFirst()))
    case "snapshot":
        return try parseSnapshot(arguments: Array(arguments.dropFirst()))
    case "preview":
        return try parsePreview(arguments: Array(arguments.dropFirst()))
    case "record":
        return try parseRecord(arguments: Array(arguments.dropFirst()))
    default:
        if first.hasPrefix("-") {
            throw OpenComputerUseCLIError(message: "Unknown option: \(first)", helpCommand: nil)
        }

        throw OpenComputerUseCLIError(message: "Unknown command: \(first)", helpCommand: nil)
    }
}

public func openComputerUseHelpText(command: String? = nil) -> String {
    switch command {
    case nil:
        return """
        Open Computer Use

        Usage:
          open-computer-use [command] [options]
          open-computer-use

        Commands:
          mcp                  Start the stdio MCP server.
          doctor               Print permission status and launch onboarding if needed.
          list-apps            Print running or recently used apps.
          targets              Print targetable apps (JSON-capable, running-only filter).
          tools [name]         Print tool definitions or one tool's schema.
          inspect <app>        Print a non-disruptive accessibility snapshot of a running app.
          snapshot <app>       Print the current accessibility snapshot for an app.
          call <tool>           Call one tool, or run a JSON array of tool calls.
          preview <app>        Write a live JPEG preview (latest.jpg + manifest.json) of an app's window.
          record <app>         Record an app's window to a bounded H.264 MP4.
          turn-ended           Notify the running MCP process that the host turn ended.
          help [command]       Show general or command-specific help.
          version              Print the CLI version.

        Global options:
          -h, --help           Show help.
          -v, --version        Show version.

        Notes:
          Running without a command launches the permission onboarding app.
          Use `open-computer-use help <command>` for command-specific help.
        """
    case "mcp":
        return """
        Usage:
          open-computer-use mcp

        Start the stdio MCP server.
        """
    case "doctor":
        return """
        Usage:
          open-computer-use doctor [--status-only] [--json]

        Options:
          --status-only        Only print the permission state. Never launches the
                               onboarding app and never prompts.
          --json               Print the permission state as JSON.

        Print the current Accessibility and Screen Recording permission state.
        Without --status-only, missing permissions also launch the onboarding app.
        """
    case "targets":
        return """
        Usage:
          open-computer-use targets [--running-only] [--json]

        Options:
          --running-only       Only include apps that are currently running.
          --json               Print targets as a JSON array with name, bundle_id,
                               pid, running, and frontmost fields.

        Print targetable apps. Read-only: never launches, activates, or prompts.
        """
    case "tools":
        return """
        Usage:
          open-computer-use tools [--json]
          open-computer-use tools <name> [--json]

        Arguments:
          <name>               Optional tool name to inspect (for example click).

        Options:
          --json               Print the full tool definition JSON (name,
                               description, inputSchema, annotations).

        Print the Computer Use tool catalog. Read-only and offline.
        """
    case "inspect":
        return """
        Usage:
          open-computer-use inspect [--json] [--window <title>] [--media-dir <path>] [--no-launch] [--no-activate] <app>

        Arguments:
          <app>                App name, bundle identifier, pid:<pid>, or a bare pid.

        Options:
          --window <title>     Target the window whose title contains <title>.
          --media-dir <path>   Write the screenshot to <path> as a PNG file and
                               reference it with an image_path content item instead
                               of embedding base64.
          --json               Print the full tool-result JSON.
          --no-launch          Do not launch the app (always guaranteed).
          --no-activate        Do not activate the app (always guaranteed).

        Print the accessibility snapshot of a running app without launching,
        activating, prompting, or mutating anything.
        """
    case "list-apps":
        return """
        Usage:
          open-computer-use list-apps

        Print running apps plus recently used apps that can be targeted by Computer Use.
        """
    case "snapshot":
        return """
        Usage:
          open-computer-use snapshot [--text-limit <positive-int|max>] [--max-tree-nodes <positive-int>] [--max-tree-depth <positive-int>] <app>

        Arguments:
          <app>                App name or bundle identifier to inspect.

        Options:
          --text-limit         Override the default 500 character text limit. Use `max` for full text.
          --max-tree-nodes     Override the default 1200 node accessibility tree budget.
          --max-tree-depth     Override the default 64 level accessibility tree depth.

        Print the current accessibility snapshot for the target app.
        """
    case "call":
        return """
        Usage:
          open-computer-use call <tool> [--args '<json-object>']
          open-computer-use call <tool> [--args-file <path>]
          open-computer-use call --calls '<json-array>' [--sleep <seconds>]
          open-computer-use call --calls-file <path> [--sleep <seconds>]

        Examples:
          open-computer-use call list_apps
          open-computer-use call get_app_state --args '{"app":"TextEdit"}'
          open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
          open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

        The JSON array form keeps all calls in one process so follow-up actions
        can reuse the app state and element indices captured by get_app_state.
        Sequence execution stops after the first tool result with isError=true.
        Sequence runs sleep \(formatOpenComputerUseDelay(openComputerUseDefaultInterCallDelay)) between successful operations by default.
        """
    case "preview":
        return """
        Usage:
          open-computer-use preview [--output-dir <path>] [--duration <seconds>] [--fps <1-60>] [--max-width <px>] [--quality <0.05-1>] [--include-cursor] <app>

        Arguments:
          <app>                App name or bundle identifier to capture. The app must already be
                               running; preview never launches, activates, or unhides it.

        Options:
          --output-dir         Directory receiving latest.jpg and manifest.json (required).
          --duration           Capture length in seconds, up to 3600. Default 30.
          --fps                Maximum published frames per second. Default 8.
          --max-width          Longest published frame width in pixels. Default 960.
          --quality            JPEG quality between 0.05 and 1. Default 0.8.
          --include-cursor     Composite the system cursor into frames (explicit opt-in).

        Writes a real-time file-backed preview: latest.jpg is atomically replaced at
        the requested fps and manifest.json tracks dimensions, timestamps, and
        frame/drop counters. Prints a machine-readable JSON summary and never
        opens a viewer.
        """
    case "record":
        return """
        Usage:
          open-computer-use record [--output <path>] [--duration <seconds>] [--fps <1-60>] [--max-width <px>] [--bitrate <bps>] [--include-cursor] <app>

        Arguments:
          <app>                App name or bundle identifier to capture. The app must already be
                               running; record never launches, activates, or unhides it.

        Options:
          --output             Destination .mp4 path (required).
          --duration           Recording length in seconds, hard-capped at 600. Default 60.
          --fps                Frames per second. Default 15.
          --max-width          Longest encoded frame width in pixels. Default 1920.
          --bitrate            H.264 average bitrate in bits per second. Default 4000000.
          --include-cursor     Composite the system cursor into frames (explicit opt-in).

        Records a bounded H.264 MP4 with monotonic timestamps and no audio. The
        output is hard-capped at 600 seconds and 300 MB; partial outputs are
        removed on failure. Prints a machine-readable JSON summary and never
        opens a viewer.
        """
    case "turn-ended":
        return """
        Usage:
          open-computer-use turn-ended [--previous-notify <argv>] [payload]

        Notify a running local MCP process that the current host turn has ended.
        Codex legacy notify appends the after-agent JSON payload as the last argument.
        """
    case "version":
        return """
        Usage:
          open-computer-use version
          open-computer-use --version
          open-computer-use -v

        Print the CLI version.
        """
    case "help":
        return """
        Usage:
          open-computer-use help [command]

        Show general help or help for a specific command.
        """
    default:
        return """
        Unknown help topic: \(command ?? "")

        \(openComputerUseHelpText())
        """
    }
}

private func parseSimpleCommand(
    name: String,
    arguments: [String],
    result: OpenComputerUseCLICommand
) throws -> OpenComputerUseCLICommand {
    if arguments.isEmpty {
        return result
    }

    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: name)
    }

    throw OpenComputerUseCLIError(message: "\(name) does not accept any arguments", helpCommand: name)
}

private func parseDoctor(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "doctor")
    }

    var statusOnly = false
    var json = false

    for argument in arguments {
        switch argument {
        case "--status-only":
            statusOnly = true
        case "--json":
            json = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "doctor help must be requested as `open-computer-use doctor --help`", helpCommand: "doctor")
        default:
            throw OpenComputerUseCLIError(message: "Unknown doctor option: \(argument)", helpCommand: "doctor")
        }
    }

    return .doctor(statusOnly: statusOnly, json: json)
}

private func parseTargets(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "targets")
    }

    var runningOnly = false
    var json = false

    for argument in arguments {
        switch argument {
        case "--running-only":
            runningOnly = true
        case "--json":
            json = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "targets help must be requested as `open-computer-use targets --help`", helpCommand: "targets")
        default:
            throw OpenComputerUseCLIError(message: "Unknown targets option: \(argument)", helpCommand: "targets")
        }
    }

    return .targets(runningOnly: runningOnly, json: json)
}

private func parseTools(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "tools")
    }

    var name: String?
    var json = false

    for argument in arguments {
        switch argument {
        case "--json":
            json = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "tools help must be requested as `open-computer-use tools --help`", helpCommand: "tools")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown tools option: \(argument)", helpCommand: "tools")
            }

            guard name == nil else {
                throw OpenComputerUseCLIError(message: "tools accepts at most one tool name", helpCommand: "tools")
            }

            name = argument
        }
    }

    return .tools(name: name, json: json)
}

private func parseInspect(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.isEmpty {
        throw OpenComputerUseCLIError(message: "inspect requires an app name, bundle identifier, or pid:<pid> target", helpCommand: "inspect")
    }

    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "inspect")
    }

    var app: String?
    var windowTitle: String?
    var mediaDir: String?
    var json = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--no-launch", "--no-activate":
            // Non-launching, non-activating is inspect's guaranteed behavior;
            // the flags are accepted so scripts can state the requirement
            // explicitly.
            break
        case "--json":
            json = true
        case "--media-dir":
            mediaDir = try parseOptionValue("--media-dir", arguments: arguments, index: &index, helpCommand: "inspect")
        case "--window":
            windowTitle = try parseOptionValue("--window", arguments: arguments, index: &index, helpCommand: "inspect")
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "inspect help must be requested as `open-computer-use inspect --help`", helpCommand: "inspect")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown inspect option: \(argument)", helpCommand: "inspect")
            }

            guard app == nil else {
                throw OpenComputerUseCLIError(message: "inspect accepts exactly one <app> argument", helpCommand: "inspect")
            }

            app = argument
        }

        index += 1
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "inspect requires an app name, bundle identifier, or pid:<pid> target", helpCommand: "inspect")
    }

    return .inspect(app: app, windowTitle: windowTitle, json: json, mediaDir: mediaDir)
}

private func parseTurnEnded(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "turn-ended")
    }

    var payload: String?
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--previous-notify":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw OpenComputerUseCLIError(message: "--previous-notify requires a value", helpCommand: "turn-ended")
            }
            index = valueIndex
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "turn-ended help must be requested as `open-computer-use turn-ended --help`", helpCommand: "turn-ended")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown turn-ended option: \(argument)", helpCommand: "turn-ended")
            }

            guard payload == nil else {
                throw OpenComputerUseCLIError(message: "turn-ended accepts at most one payload argument", helpCommand: "turn-ended")
            }

            payload = argument
        }

        index += 1
    }

    return .turnEnded(payload: payload)
}

private func parseSnapshot(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.isEmpty {
        throw OpenComputerUseCLIError(message: "snapshot requires an app name or bundle identifier", helpCommand: "snapshot")
    }

    if arguments.count == 1, let value = arguments.first, value == "-h" || value == "--help" {
        return .help(command: "snapshot")
    }

    var app: String?
    var textLimit = SnapshotTextLimit.defaults
    var maxTreeNodes: Int?
    var maxTreeDepth: Int?

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--text-limit":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--text-limit requires a positive integer or max value", helpCommand: "snapshot")
            }
            textLimit = try parseTextLimitOption(arguments[index], option: "--text-limit")
        case "--max-tree-nodes":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--max-tree-nodes requires a positive integer value", helpCommand: "snapshot")
            }
            maxTreeNodes = try parsePositiveIntegerOption(arguments[index], option: "--max-tree-nodes")
        case "--max-tree-depth":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--max-tree-depth requires a positive integer value", helpCommand: "snapshot")
            }
            maxTreeDepth = try parsePositiveIntegerOption(arguments[index], option: "--max-tree-depth")
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "snapshot help must be requested as `open-computer-use snapshot --help`", helpCommand: "snapshot")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown snapshot option: \(argument)", helpCommand: "snapshot")
            }

            guard app == nil else {
                throw OpenComputerUseCLIError(message: "snapshot accepts exactly one <app> argument", helpCommand: "snapshot")
            }

            app = argument
        }
        index += 1
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "snapshot requires an app name or bundle identifier", helpCommand: "snapshot")
    }

    return .snapshot(
        app: app,
        textLimit: textLimit,
        treeLimits: AccessibilityTreeLimits.defaults.replacing(
            maxNodeCount: maxTreeNodes,
            maxDepth: maxTreeDepth
        )
    )
}

private func parsePreview(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "preview")
    }

    var app: String?
    var outputDirectory: String?
    var duration = 30.0
    var framesPerSecond = 8
    var maxWidth = 960
    var jpegQuality = 0.8
    var includeCursor = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--output-dir":
            outputDirectory = try parseCaptureOptionValue("--output-dir", arguments: arguments, index: &index, helpCommand: "preview")
        case "--duration":
            duration = try parseCapturePositiveDouble("--duration", arguments: arguments, index: &index, helpCommand: "preview")
        case "--fps":
            framesPerSecond = try parseCapturePositiveInteger("--fps", arguments: arguments, index: &index, helpCommand: "preview")
        case "--max-width":
            maxWidth = try parseCapturePositiveInteger("--max-width", arguments: arguments, index: &index, helpCommand: "preview")
        case "--quality":
            jpegQuality = try parseCapturePositiveDouble("--quality", arguments: arguments, index: &index, helpCommand: "preview")
        case "--include-cursor":
            includeCursor = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "preview help must be requested as `open-computer-use preview --help`", helpCommand: "preview")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown preview option: \(argument)", helpCommand: "preview")
            }

            guard app == nil else {
                throw OpenComputerUseCLIError(message: "preview accepts exactly one <app> argument", helpCommand: "preview")
            }

            app = argument
        }
        index += 1
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "preview requires an app name or bundle identifier", helpCommand: "preview")
    }
    guard let outputDirectory else {
        throw OpenComputerUseCLIError(message: "preview requires --output-dir <path>", helpCommand: "preview")
    }

    return .preview(
        app: app,
        options: PreviewCaptureOptions(
            outputDirectory: outputDirectory,
            duration: duration,
            framesPerSecond: framesPerSecond,
            maxWidth: maxWidth,
            jpegQuality: jpegQuality,
            includeCursor: includeCursor
        )
    )
}

private func parseRecord(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "record")
    }

    var app: String?
    var outputPath: String?
    var duration = 60.0
    var framesPerSecond = 15
    var maxWidth = 1920
    var bitrate = 4_000_000
    var includeCursor = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--output":
            outputPath = try parseCaptureOptionValue("--output", arguments: arguments, index: &index, helpCommand: "record")
        case "--duration":
            duration = try parseCapturePositiveDouble("--duration", arguments: arguments, index: &index, helpCommand: "record")
        case "--fps":
            framesPerSecond = try parseCapturePositiveInteger("--fps", arguments: arguments, index: &index, helpCommand: "record")
        case "--max-width":
            maxWidth = try parseCapturePositiveInteger("--max-width", arguments: arguments, index: &index, helpCommand: "record")
        case "--bitrate":
            bitrate = try parseCapturePositiveInteger("--bitrate", arguments: arguments, index: &index, helpCommand: "record")
        case "--include-cursor":
            includeCursor = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "record help must be requested as `open-computer-use record --help`", helpCommand: "record")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown record option: \(argument)", helpCommand: "record")
            }

            guard app == nil else {
                throw OpenComputerUseCLIError(message: "record accepts exactly one <app> argument", helpCommand: "record")
            }

            app = argument
        }
        index += 1
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "record requires an app name or bundle identifier", helpCommand: "record")
    }
    guard let outputPath else {
        throw OpenComputerUseCLIError(message: "record requires --output <path>", helpCommand: "record")
    }

    return .record(
        app: app,
        options: RecordingCaptureOptions(
            outputPath: outputPath,
            duration: duration,
            framesPerSecond: framesPerSecond,
            maxWidth: maxWidth,
            bitrate: bitrate,
            includeCursor: includeCursor
        )
    )
}

private func parseCaptureOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String
) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw OpenComputerUseCLIError(message: "\(option) requires a value", helpCommand: helpCommand)
    }

    index = valueIndex
    return arguments[valueIndex]
}

private func parseCapturePositiveInteger(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String
) throws -> Int {
    let rawValue = try parseCaptureOptionValue(option, arguments: arguments, index: &index, helpCommand: helpCommand)
    guard let value = Int(rawValue), value > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive integer", helpCommand: helpCommand)
    }
    return value
}

private func parseCapturePositiveDouble(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String
) throws -> Double {
    let rawValue = try parseCaptureOptionValue(option, arguments: arguments, index: &index, helpCommand: helpCommand)
    guard let value = Double(rawValue), value.isFinite, value > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive number", helpCommand: helpCommand)
    }
    return value
}

private func parseTextLimitOption(_ value: String, option: String) throws -> SnapshotTextLimit {
    if value.lowercased() == SnapshotTextLimit.maxKeyword {
        return .max
    }

    guard let integer = Int(value), integer > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive integer or max", helpCommand: "snapshot")
    }
    return SnapshotTextLimit(maxCount: integer)
}

private func parsePositiveIntegerOption(_ value: String, option: String) throws -> Int {
    guard let integer = Int(value), integer > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive integer", helpCommand: "snapshot")
    }
    return integer
}

private func parseCall(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "call")
    }

    var toolName: String?
    var argumentsJSON: String?
    var argumentsFile: String?
    var callsJSON: String?
    var callsFile: String?
    var interCallDelay = openComputerUseDefaultInterCallDelay

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--args":
            argumentsJSON = try parseOptionValue("--args", arguments: arguments, index: &index)
        case "--args-file":
            argumentsFile = try parseOptionValue("--args-file", arguments: arguments, index: &index)
        case "--calls":
            callsJSON = try parseOptionValue("--calls", arguments: arguments, index: &index)
        case "--calls-file":
            callsFile = try parseOptionValue("--calls-file", arguments: arguments, index: &index)
        case "--sleep":
            interCallDelay = try parseTimeIntervalOptionValue("--sleep", arguments: arguments, index: &index)
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "call help must be requested as `open-computer-use call --help`", helpCommand: "call")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown call option: \(argument)", helpCommand: "call")
            }

            guard toolName == nil else {
                throw OpenComputerUseCLIError(message: "call accepts at most one tool name", helpCommand: "call")
            }

            toolName = argument
        }

        index += 1
    }

    let hasSequenceInput = callsJSON != nil || callsFile != nil
    if hasSequenceInput {
        if callsJSON != nil, callsFile != nil {
            throw OpenComputerUseCLIError(message: "Use either --calls or --calls-file, not both", helpCommand: "call")
        }

        if toolName != nil || argumentsJSON != nil || argumentsFile != nil {
            throw OpenComputerUseCLIError(
                message: "call sequence does not accept a tool name, --args, or --args-file",
                helpCommand: "call"
            )
        }

        return .call(.sequence(
            callsJSON: callsJSON,
            callsFile: callsFile,
            interCallDelay: interCallDelay
        ))
    }

    if argumentsJSON != nil, argumentsFile != nil {
        throw OpenComputerUseCLIError(message: "Use either --args or --args-file, not both", helpCommand: "call")
    }

    if interCallDelay != openComputerUseDefaultInterCallDelay {
        throw OpenComputerUseCLIError(
            message: "--sleep is only supported with --calls or --calls-file",
            helpCommand: "call"
        )
    }

    guard let toolName else {
        throw OpenComputerUseCLIError(message: "call requires a tool name or --calls/--calls-file", helpCommand: "call")
    }

    return .call(.single(toolName: toolName, argumentsJSON: argumentsJSON, argumentsFile: argumentsFile))
}

private func parseOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String = "call"
) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw OpenComputerUseCLIError(message: "\(option) requires a value", helpCommand: helpCommand)
    }

    index = valueIndex
    return arguments[valueIndex]
}

private func parseTimeIntervalOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int
) throws -> TimeInterval {
    let rawValue = try parseOptionValue(option, arguments: arguments, index: &index)
    guard let value = Double(rawValue), value.isFinite, value >= 0 else {
        throw OpenComputerUseCLIError(
            message: "\(option) requires a non-negative number of seconds",
            helpCommand: "call"
        )
    }

    return value
}

private func formatOpenComputerUseDelay(_ delay: TimeInterval) -> String {
    if delay.rounded() == delay {
        return "\(Int(delay))s"
    }

    return "\(delay)s"
}

/// JSON payload for `doctor --json`.
public func openComputerUseDoctorPayload(_ diagnostics: PermissionDiagnostics) -> [String: Any] {
    [
        "permissions": [
            "accessibility": diagnostics.accessibilityTrusted,
            "screen_recording": diagnostics.screenCaptureGranted,
        ],
        "all_granted": diagnostics.allGranted,
        "missing": diagnostics.missingPermissions.map(\.rawValue),
    ]
}

/// Serialize a JSON-compatible object graph for CLI stdout.
public func openComputerUseJSONText(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .withoutEscapingSlashes]
    )
    guard let text = String(data: data, encoding: .utf8) else {
        throw ComputerUseError.message("Failed to encode CLI output as JSON.")
    }
    return text
}
