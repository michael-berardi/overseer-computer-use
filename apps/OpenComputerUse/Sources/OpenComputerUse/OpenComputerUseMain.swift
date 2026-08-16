import AppKit
import Darwin
import Foundation
import OpenComputerUseKit

@main
enum OpenComputerUseMain {
    @MainActor
    static func main() {
        do {
            try run()
        } catch let error as OpenComputerUseCLIError {
            writeToStandardError(error.errorDescription ?? error.message)
            exit(openComputerUseExitStatus(for: error).rawValue)
        } catch let error as ComputerUseError {
            writeToStandardError(error.errorDescription ?? String(describing: error))
            exit(openComputerUseExitStatus(for: error).rawValue)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            writeToStandardError(message)
            exit(openComputerUseExitStatus(for: error).rawValue)
        }
    }

    @MainActor
    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if MacOSAppAgentProxy.isAgentInvocation(arguments: arguments) {
            TelemetryCoordinator().start()
            if TelemetryStore().consent != .undecided {
                NativeUpdatePrompt.checkAtLaunch()
            }
            OverseerUpdater.confirmSuccessfulLaunch()
            try MacOSAppAgentProxy.runAgent(arguments: arguments)
            return
        }

        let command = try parseOpenComputerUseCLI(arguments: arguments)
        if case let .telemetry(action) = command {
            let store = TelemetryStore()
            switch action {
            case .status:
                print(store.consent.rawValue)
            case .enable:
                _ = store.optIn()
                print("optedIn")
            case .disable:
                store.disable()
                print("declined")
            }
            return
        }

        TelemetryCoordinator().start()


        if MacOSAppAgentProxy.shouldProxy(command: command) {
            exit(try MacOSAppAgentProxy.runProxy(command: command, arguments: arguments))
        }

        switch command {
        case .mcp:
            let service = ComputerUseService()
            let server = StdioMCPServer(service: service)
            if VisualCursorSupport.isEnabled {
                try MainActor.assumeIsolated {
                    try MCPAppRuntime.run(server: server)
                }
            } else {
                try server.run()
            }
        case let .doctor(statusOnly, json):
            let permissions = PermissionDiagnostics.current()
            if json {
                print(try openComputerUseJSONText(openComputerUseDoctorPayload(permissions)))
            } else {
                print(permissions.summary)
            }
            if !statusOnly, !permissions.missingPermissions.isEmpty {
                PermissionOnboardingApp.launch()
            }
        case .telemetry:
            break
        case .listApps:
            let service = ComputerUseService()
            print(service.listApps().primaryText ?? "")
        case let .targets(runningOnly, json):
            if json {
                print(try openComputerUseJSONText(openComputerUseTargetsPayload(runningOnly: runningOnly)))
            } else {
                print(openComputerUseTargetsText(runningOnly: runningOnly))
            }
        case let .tools(name, json):
            if json {
                print(try openComputerUseJSONText(openComputerUseToolsPayload(name: name)))
            } else {
                print(try openComputerUseToolsText(name: name))
            }
        case let .inspect(app, windowTitle, json, mediaDir):
            let service = ComputerUseService()
            var result = try service.inspectAppState(app: app, windowTitleHint: windowTitle)
            if let mediaDir {
                result = try externalizeToolResultImages(result, mediaDir: mediaDir, stem: "\(app)-inspect")
            }
            if json {
                print(try openComputerUseJSONText(result.asDictionary))
            } else {
                print(result.primaryText ?? "")
                for item in result.content where item.dictionary["type"] as? String == "image_path" {
                    if let path = item.dictionary["path"] as? String {
                        print("image: \(path)")
                    }
                }
            }
        case let .snapshot(app, textLimit, treeLimits):
            let service = ComputerUseService()
            print(try service.getAppState(app: app, textLimit: textLimit, treeLimits: treeLimits).primaryText ?? "")
        case let .call(invocation):
            if VisualCursorSupport.isEnabled {
                _ = NSApplication.shared.setActivationPolicy(.accessory)
            }
            let output = try runOpenComputerUseCall(invocation)
            print(try output.jsonText())
            if output.hasToolError {
                exit(output.errorInfo.map { openComputerUseExitStatus(forStructuredCode: $0.code).rawValue } ?? EXIT_FAILURE)
            }
        case let .preview(app, options):
            let summary = try PreviewCaptureCommand.run(app: app, options: options)
            print(try summary.jsonText())
            if summary.status == .failed {
                exit(EXIT_FAILURE)
            }
        case let .record(app, options):
            let summary = try RecordingCaptureCommand.run(app: app, options: options)
            print(try summary.jsonText())
            if summary.status == .failed {
                exit(EXIT_FAILURE)
            }
        case .turnEnded:
            postOpenComputerUseTurnEndedNotification()
            print("turn-ended acknowledged")
        case let .help(command):
            print(openComputerUseHelpText(command: command))
        case .version:
            print(resolvedOpenComputerUseVersion())
        case .launchOnboarding:
            if !PermissionDiagnostics.current().allGranted {
                PermissionOnboardingApp.launch()
            }
        }
    }

    private static func writeToStandardError(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else {
            return
        }

        FileHandle.standardError.write(data)
    }
}
