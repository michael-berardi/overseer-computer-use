import AppKit
import Darwin
import Foundation
import OpenComputerUseKit

private let appAgentCommand = "__open-computer-use-app-agent"
private let appAgentDisableEnvironmentKey = "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY"
private let appAgentProcessStartDate = Date()

enum MacOSAppAgentProxy {
    static func isAgentInvocation(arguments: [String]) -> Bool {
        arguments.first == appAgentCommand
    }

    @MainActor
    static func runAgent(arguments: [String]) throws {
        guard arguments.count == 2 else {
            throw OpenComputerUseCLIError(message: "\(appAgentCommand) requires a socket path")
        }

        try MacOSAppAgentRuntime.run(socketPath: arguments[1])
    }

    static func shouldProxy(command: OpenComputerUseCLICommand) -> Bool {
        shouldUseMacOSAppAgentProxy(
            command: command,
            proxyDisabled: proxyDisabled,
            appBundleAvailable: PermissionSupport.currentAppBundleURL() != nil,
            runningFromLaunchServicesAppInstance: isRunningFromLaunchServicesAppInstance
        )
    }

    @MainActor
    static func runProxy(command: OpenComputerUseCLICommand, arguments: [String]) throws -> Int32 {
        let socketPath = defaultSocketPath()
        let client = try connectOrLaunchAgent(socketPath: socketPath)

        switch command {
        case .mcp:
            try proxyMCP(client: client)
            return EXIT_SUCCESS
        default:
            let response = try sendCLIRequest(arguments: arguments, client: client)
            if !response.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(response.stdout.utf8))
            }
            if !response.stderr.isEmpty {
                FileHandle.standardError.write(Data(response.stderr.utf8))
            }
            return response.exitCode
        }
    }

    private static var proxyDisabled: Bool {
        let value = ProcessInfo.processInfo.environment[appAgentDisableEnvironmentKey]?.lowercased()
        return value == "1" || value == "true" || value == "yes" || value == "on"
    }

    private static var isRunningFromOpenComputerUseAppBundle: Bool {
        Bundle.main.bundleURL.standardizedFileURL.pathExtension == "app"
            && PermissionSupport.isOpenComputerUseBundleIdentifier(Bundle.main.bundleIdentifier)
    }

    private static var isRunningFromLaunchServicesAppInstance: Bool {
        isRunningFromOpenComputerUseAppBundle && getppid() == 1
    }

    private static func defaultSocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-computer-use-agent.sock")
            .standardizedFileURL
            .path
    }

    @MainActor
    private static func connectOrLaunchAgent(socketPath: String) throws -> AppAgentSocketClient {
        guard let appURL = PermissionSupport.currentAppBundleURL() else {
            throw OpenComputerUseCLIError(message: "Unable to locate Overseer Computer Use.app for app-scoped macOS permissions.")
        }

        // Serialize probe/terminate-stale/unlink/launch/wait across every proxy
        // process, so two concurrent invocations cannot both launch an agent or
        // unlink a socket another launcher just bound.
        return try withAgentStartupLock(socketPath: socketPath) {
            if let client = AppAgentSocketClient.connect(path: socketPath) {
                if (try? client.isCurrentAgent(for: appURL)) == true {
                    return client
                }

                _ = try? client.request(["kind": "terminate"])
                unlink(socketPath)
            } else {
                unlink(socketPath)
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [appAgentCommand, socketPath]
            configuration.activates = false
            configuration.createsNewApplicationInstance = true

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }

            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let client = AppAgentSocketClient.connect(path: socketPath) {
                    return client
                }
                Thread.sleep(forTimeInterval: 0.05)
            }

            throw OpenComputerUseCLIError(message: "Timed out waiting for Overseer Computer Use.app agent to start.")
        }
    }

    private static func withAgentStartupLock<T>(socketPath: String, _ body: () throws -> T) throws -> T {
        let lockPath = socketPath + ".startup.lock"
        let lockFD = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else {
            // The lock file is a best-effort guard; never fail the command over it.
            return try body()
        }
        defer { close(lockFD) }

        // The agent itself never takes this lock, so holding it while waiting
        // for the agent to come up cannot deadlock.
        flock(lockFD, LOCK_EX)
        defer { flock(lockFD, LOCK_UN) }
        return try body()
    }

    private static func proxyMCP(client: AppAgentSocketClient) throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let response = try client.request([
                "kind": "mcp",
                "line": line,
                "environment": proxiedEnvironment(),
            ])

            if let responseLine = response["response"] as? String {
                FileHandle.standardOutput.write(Data((responseLine + "\n").utf8))
            }
        }
    }

    private static func sendCLIRequest(arguments: [String], client: AppAgentSocketClient) throws -> CLIProxyResponse {
        let response = try client.request([
            "kind": "cli",
            "arguments": arguments,
            "environment": proxiedEnvironment(),
        ])

        return CLIProxyResponse(
            stdout: response["stdout"] as? String ?? "",
            stderr: response["stderr"] as? String ?? "",
            exitCode: Int32(response["exitCode"] as? Int ?? 1)
        )
    }

    private static func proxiedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { key, _ in
            key.hasPrefix("OPEN_COMPUTER_USE_")
        }
    }
}

private struct CLIProxyResponse {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

@MainActor
private final class MacOSAppAgentRuntime: NSObject, NSApplicationDelegate {
    private let socketPath: String
    private var listener: AppAgentSocketListener?
    private var turnEndedObserver: NSObjectProtocol?

    private init(socketPath: String) {
        self.socketPath = socketPath
    }

    static func run(socketPath: String) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = MacOSAppAgentRuntime(socketPath: socketPath)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        turnEndedObserver = DistributedNotificationCenter.default().addObserver(
            forName: openComputerUseTurnEndedNotificationName,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                resetOpenComputerUseVisualCursor()
            }
        }

        do {
            let listener = try AppAgentSocketListener(path: socketPath)
            self.listener = listener
            listener.start()
        } catch {
            writeAgentError(error)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let turnEndedObserver {
            DistributedNotificationCenter.default().removeObserver(turnEndedObserver)
        }
        listener?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func writeAgentError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private enum AppAgentConcurrency {
    /// Maximum simultaneous client connections; excess connections queue in the
    /// kernel listen backlog instead of spawning unbounded detached threads.
    static let maxConcurrentClients = 8
    static let clientSlots = DispatchSemaphore(value: maxConcurrentClients)

    private static let automationLock = NSLock()

    /// Automation (`mcp` / `cli`) requests are serialized per app-agent so
    /// concurrent clients cannot interleave UI actions. Informational requests
    /// (`agentInfo`, `terminate`) stay unsynchronized.
    static func withAutomationSerialization<T>(_ body: () -> T) -> T {
        automationLock.lock()
        defer { automationLock.unlock() }
        return body()
    }
}

private final class AppAgentSocketListener: @unchecked Sendable {
    private let path: String
    private let socketFD: Int32
    private let boundSocketIdentity: (device: dev_t, inode: ino_t)?
    private let tokenPath: String
    private let capabilityToken: String
    private var running = true
    init(path: String) throws {
        self.path = path
        self.tokenPath = path + ".token"
        self.capabilityToken = UUID().uuidString.lowercased()

        // Never replace a socket that a live agent still owns; refuse to start
        // instead of orphaning the running agent's clients.
        if AppAgentSocketClient.probe(path: path) {
            throw OpenComputerUseCLIError(message: "Another Overseer Computer Use.app agent already owns the socket at \(path)")
        }
        unlink(path)

        try Data(capabilityToken.utf8).write(to: URL(fileURLWithPath: tokenPath), options: .atomic)
        guard chmod(tokenPath, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            unlink(tokenPath)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let createdSocketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard createdSocketFD >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        try withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            try pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer in
                let bytes = Array(path.utf8)
                guard bytes.count < pathCapacity else {
                    throw OpenComputerUseCLIError(message: "Socket path is too long: \(path)")
                }
                for index in 0..<bytes.count {
                    buffer[index] = CChar(bitPattern: bytes[index])
                }
                buffer[bytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(createdSocketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(createdSocketFD)
            unlink(tokenPath)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard listen(createdSocketFD, 16) == 0 else {
            close(createdSocketFD)
            unlink(tokenPath)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            close(createdSocketFD)
            unlink(path)
            unlink(tokenPath)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var socketInfo = stat()
        self.socketFD = createdSocketFD
        self.boundSocketIdentity = lstat(path, &socketInfo) == 0
            ? (device: socketInfo.st_dev, inode: socketInfo.st_ino)
            : nil
    }

    func start() {
        Thread.detachNewThread {
            self.acceptLoop()
        }
    }

    func stop() {
        unlink(tokenPath)
        close(socketFD)
        // Wake a slot-waiting accept loop so it can observe `running == false`
        // and exit instead of lingering until process teardown.
        AppAgentConcurrency.clientSlots.signal()
        unlinkIfStillOwned()
    }

    private func unlinkIfStillOwned() {
        guard let boundSocketIdentity else {
            return
        }

        // Only remove the path if it still refers to the socket this listener
        // bound; a replacement agent may have bound its own socket at the same
        // path after this one closed.
        var currentInfo = stat()
        guard lstat(path, &currentInfo) == 0,
              currentInfo.st_dev == boundSocketIdentity.device,
              currentInfo.st_ino == boundSocketIdentity.inode
        else {
            return
        }

        unlink(path)
    }

    private func acceptLoop() {
        while running {
            AppAgentConcurrency.clientSlots.wait()
            guard running else {
                AppAgentConcurrency.clientSlots.signal()
                break
            }

            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else {
                AppAgentConcurrency.clientSlots.signal()
                if running {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                continue
            }

                let connection = AppAgentConnection(fileDescriptor: clientFD, capabilityToken: capabilityToken)
                connection.run()
                AppAgentConcurrency.clientSlots.signal()
            }
        }
    }
private final class AppAgentConnection: @unchecked Sendable {
    private let channel: LineDelimitedSocketChannel
    private let capabilityToken: String
    private let server = StdioMCPServer()

    init(fileDescriptor: Int32, capabilityToken: String) {
        channel = LineDelimitedSocketChannel(fileDescriptor: fileDescriptor)
        self.capabilityToken = capabilityToken
    }

    func run() {
        while let line = channel.readLine() {
            let response = handle(requestLine: line)
            channel.writeJSONLine(response)
        }
    }

    private func handle(requestLine: String) -> [String: Any] {
        do {
            guard let request = try JSONSerialization.jsonObject(with: Data(requestLine.utf8)) as? [String: Any],
                  let kind = request["kind"] as? String
            else {
                return ["error": "Invalid app-agent request"]
            }
            guard request["nonce"] as? String == capabilityToken else {
                return ["error": "Unauthenticated app-agent request"]
            }
            switch kind {
            case "agentInfo":
                return [
                    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                    "bundleURL": Bundle.main.bundleURL.standardizedFileURL.path,
                    "executableURL": Bundle.main.executableURL?.standardizedFileURL.path ?? "",
                    "processStartTime": appAgentProcessStartDate.timeIntervalSince1970,
                ]
            case "terminate":
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
                return ["ok": true]
            case "mcp":
                return AppAgentConcurrency.withAutomationSerialization {
                    let line = request["line"] as? String ?? ""
                    let environment = request["environment"] as? [String: String] ?? [:]
                    let response = AppAgentEnvironment.withOverrides(environment) {
                        server.handle(line: line)
                    }
                    if let response {
                        return ["response": response]
                    }
                    return ["response": NSNull()]
                }
            case "cli":
                return AppAgentConcurrency.withAutomationSerialization {
                    let arguments = request["arguments"] as? [String] ?? []
                    let environment = request["environment"] as? [String: String] ?? [:]
                    let response = AppAgentEnvironment.withOverrides(environment) {
                        runCLI(arguments: arguments)
                    }
                    return [
                        "stdout": response.stdout,
                        "stderr": response.stderr,
                        "exitCode": Int(response.exitCode),
                    ]
                }
            default:
                return ["error": "Unknown app-agent request kind: \(kind)"]
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return ["error": message]
        }
    }

    private func runCLI(arguments: [String]) -> CLIProxyResponse {
        do {
            let command = try parseOpenComputerUseCLI(arguments: arguments)

            switch command {
            case .launchOnboarding:
                let permissions = PermissionDiagnostics.current()
                if !permissions.allGranted {
                    Task { @MainActor in
                        PermissionOnboardingApp.present()
                    }
                }
                return CLIProxyResponse(stdout: "", stderr: "", exitCode: EXIT_SUCCESS)

            case let .doctor(statusOnly, json):
                let permissions = PermissionDiagnostics.current()
                if !statusOnly, !permissions.missingPermissions.isEmpty {
                    Task { @MainActor in
                        PermissionOnboardingApp.present()
                    }
                }
                let stdout: String
                if json {
                    stdout = try openComputerUseJSONText(openComputerUseDoctorPayload(permissions)) + "\n"
                } else {
                    stdout = permissions.summary + "\n"
                }
                return CLIProxyResponse(stdout: stdout, stderr: "", exitCode: EXIT_SUCCESS)

            case .listApps:
                let service = ComputerUseService()
                return CLIProxyResponse(stdout: (service.listApps().primaryText ?? "") + "\n", stderr: "", exitCode: EXIT_SUCCESS)

            case let .targets(runningOnly, json):
                let stdout: String
                if json {
                    stdout = try openComputerUseJSONText(openComputerUseTargetsPayload(runningOnly: runningOnly)) + "\n"
                } else {
                    stdout = openComputerUseTargetsText(runningOnly: runningOnly) + "\n"
                }
                return CLIProxyResponse(stdout: stdout, stderr: "", exitCode: EXIT_SUCCESS)

            case let .tools(name, json):
                do {
                    let stdout: String
                    if json {
                        stdout = try openComputerUseJSONText(openComputerUseToolsPayload(name: name)) + "\n"
                    } else {
                        stdout = try openComputerUseToolsText(name: name) + "\n"
                    }
                    return CLIProxyResponse(stdout: stdout, stderr: "", exitCode: EXIT_SUCCESS)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    return CLIProxyResponse(
                        stdout: "",
                        stderr: message + "\n",
                        exitCode: openComputerUseExitStatus(for: error).rawValue
                    )
                }

            case let .inspect(app, windowTitle, json, mediaDir):
                do {
                    let service = ComputerUseService()
                    var result = try service.inspectAppState(app: app, windowTitleHint: windowTitle)
                    if let mediaDir {
                        result = try externalizeToolResultImages(result, mediaDir: mediaDir, stem: "\(app)-inspect")
                    }
                    var stdout: String
                    if json {
                        stdout = try openComputerUseJSONText(result.asDictionary) + "\n"
                    } else {
                        stdout = (result.primaryText ?? "") + "\n"
                        for item in result.content where item.dictionary["type"] as? String == "image_path" {
                            if let path = item.dictionary["path"] as? String {
                                stdout += "image: \(path)\n"
                            }
                        }
                    }
                    return CLIProxyResponse(stdout: stdout, stderr: "", exitCode: EXIT_SUCCESS)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    return CLIProxyResponse(
                        stdout: "",
                        stderr: message + "\n",
                        exitCode: openComputerUseExitStatus(for: error).rawValue
                    )
                }

            case let .snapshot(app, textLimit, treeLimits):
                let service = ComputerUseService()
                let text = try service.getAppState(app: app, textLimit: textLimit, treeLimits: treeLimits).primaryText ?? ""
                return CLIProxyResponse(stdout: text + "\n", stderr: "", exitCode: EXIT_SUCCESS)

            case let .call(invocation):
                let output = try runOpenComputerUseCall(invocation)
                return CLIProxyResponse(
                    stdout: try output.jsonText() + "\n",
                    stderr: "",
                    exitCode: output.hasToolError
                        ? (output.errorInfo.map { openComputerUseExitStatus(forStructuredCode: $0.code).rawValue } ?? EXIT_FAILURE)
                        : EXIT_SUCCESS
                )

            default:
                return CLIProxyResponse(stdout: "", stderr: "Unsupported proxied command.\n", exitCode: EXIT_FAILURE)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return CLIProxyResponse(
                stdout: "",
                stderr: message + "\n",
                exitCode: openComputerUseExitStatus(for: error).rawValue
            )
        }
    }
}

private enum AppAgentEnvironment {
    private static let lock = NSLock()

    static func withOverrides<T>(_ overrides: [String: String], _ body: () throws -> T) rethrows -> T {
        guard !overrides.isEmpty else {
            return try body()
        }

        lock.lock()
        defer { lock.unlock() }

        let previousValues = Dictionary(
            uniqueKeysWithValues: overrides.keys.map { key in
                (key, ProcessInfo.processInfo.environment[key])
            }
        )
        for (key, value) in overrides {
            setenv(key, value, 1)
        }

        defer {
            for (key, previousValue) in previousValues {
                if let previousValue {
                    setenv(key, previousValue, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        return try body()
    }
}

private func openConnectedSocket(path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        return nil
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    let copied = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer -> Bool in
            let bytes = Array(path.utf8)
            guard bytes.count < pathCapacity else {
                return false
            }
            for index in 0..<bytes.count {
                buffer[index] = CChar(bitPattern: bytes[index])
            }
            buffer[bytes.count] = 0
            return true
        }
    }

    guard copied else {
        close(fd)
        return nil
    }

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        close(fd)
        return nil
    }

    return fd
}

private final class AppAgentSocketClient: @unchecked Sendable {
    private let channel: LineDelimitedSocketChannel
    private let tokenPath: String

    private init(fileDescriptor: Int32, tokenPath: String) {
        channel = LineDelimitedSocketChannel(fileDescriptor: fileDescriptor)
        self.tokenPath = tokenPath
    }

    static func connect(path: String) -> AppAgentSocketClient? {
        guard let fd = openConnectedSocket(path: path) else {
            return nil
        }

        return AppAgentSocketClient(fileDescriptor: fd, tokenPath: path + ".token")
    }

    /// Returns true when a peer accepts connections at `path`, i.e. a live
    /// agent owns the socket. Used to avoid replacing another agent's socket.
    static func probe(path: String) -> Bool {
        guard let fd = openConnectedSocket(path: path) else {
            return false
        }

        close(fd)
        return true
    }

    func request(_ object: [String: Any]) throws -> [String: Any] {
        var authenticatedObject = object
        authenticatedObject["nonce"] = try String(contentsOfFile: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try JSONSerialization.data(withJSONObject: authenticatedObject, options: [.withoutEscapingSlashes])
        guard let line = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode app-agent request.")
        }

        channel.writeLine(line)

        guard let responseLine = channel.readLine(),
              let response = try JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any]
        else {
            throw ComputerUseError.message("Overseer Computer Use.app agent closed the connection.")
        }

        if let error = response["error"] as? String {
            throw ComputerUseError.message(error)
        }

        return response
    }

    func isCurrentAgent(for appURL: URL) throws -> Bool {
        let response = try request(["kind": "agentInfo"])
        let expectedBundleURL = appURL.standardizedFileURL

        guard response["bundleURL"] as? String == expectedBundleURL.path else {
            return false
        }

        guard let processStartTime = response["processStartTime"] as? TimeInterval else {
            return false
        }

        guard let executableURL = executableURL(for: expectedBundleURL),
              let modifiedAt = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else {
            return true
        }

        return processStartTime + 0.5 >= modifiedAt.timeIntervalSince1970
    }

    private func executableURL(for appURL: URL) -> URL? {
        guard let bundle = Bundle(url: appURL),
              let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String,
              !executableName.isEmpty
        else {
            return nil
        }

        return appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .standardizedFileURL
    }
}

