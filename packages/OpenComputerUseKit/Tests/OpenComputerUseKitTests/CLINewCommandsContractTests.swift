import XCTest
@testable import OpenComputerUseKit

/// CLI parsing contract for the new commands: doctor --status-only, tools,
/// targets, inspect (no-launch/no-activate), preview, record. Pure argv
/// parsing — nothing is launched or executed.
final class CLINewCommandsContractTests: XCTestCase {
    // MARK: doctor

    func testDoctorParsesStatusOnlyAndJSON() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["doctor"]),
            .doctor(statusOnly: false, json: false)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["doctor", "--status-only"]),
            .doctor(statusOnly: true, json: false)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["doctor", "--status-only", "--json"]),
            .doctor(statusOnly: true, json: true)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["doctor", "--json", "--status-only"]),
            .doctor(statusOnly: true, json: true)
        )
    }

    func testDoctorRejectsUnknownOptions() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["doctor", "--verbose"])) { error in
            XCTAssertEqual((error as? OpenComputerUseCLIError)?.helpCommand, "doctor")
        }
    }

    func testStatusOnlyDoctorNeverProxiesToAppAgent() {
        XCTAssertFalse(shouldUseMacOSAppAgentProxy(
            command: .doctor(statusOnly: true, json: true),
            proxyDisabled: false,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: false
        ))
        XCTAssertTrue(shouldUseMacOSAppAgentProxy(
            command: .doctor(statusOnly: false, json: false),
            proxyDisabled: false,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: false
        ))
    }

    // MARK: tools

    func testToolsParsesOptionalNameAndJSON() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["tools"]), .tools(name: nil, json: false))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["tools", "--json"]), .tools(name: nil, json: true))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["tools", "click"]), .tools(name: "click", json: false))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["tools", "click", "--json"]), .tools(name: "click", json: true))
    }

    func testToolsRejectsExtraNamesAndUnknownOptions() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["tools", "click", "scroll"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["tools", "--verbose"]))
    }

    func testToolsCommandNeverProxiesToAppAgent() {
        XCTAssertFalse(shouldUseMacOSAppAgentProxy(
            command: .tools(name: "click", json: true),
            proxyDisabled: false,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: false
        ))
    }

    // MARK: targets

    func testTargetsParsesRunningOnlyAndJSON() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["targets"]), .targets(runningOnly: false, json: false))
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["targets", "--running-only", "--json"]),
            .targets(runningOnly: true, json: true)
        )
    }

    func testTargetsRejectsUnknownOptions() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["targets", "--all"])) { error in
            XCTAssertEqual((error as? OpenComputerUseCLIError)?.helpCommand, "targets")
        }
    }

    // MARK: inspect

    func testInspectParsesAppAndOptions() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["inspect", "TextEdit"]),
            .inspect(app: "TextEdit", windowTitle: nil, json: false, mediaDir: nil)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: [
                "inspect", "com.apple.TextEdit",
                "--no-launch", "--no-activate",
                "--window", "Draft",
                "--json",
                "--media-dir", "/tmp/media",
            ]),
            .inspect(app: "com.apple.TextEdit", windowTitle: "Draft", json: true, mediaDir: "/tmp/media")
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["inspect", "pid:4242"]),
            .inspect(app: "pid:4242", windowTitle: nil, json: false, mediaDir: nil)
        )
    }

    func testInspectRequiresAppAndRejectsExtras() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["inspect"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["inspect", "A", "B"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["inspect", "A", "--media-dir"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["inspect", "A", "--window"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["inspect", "A", "--launch"]))
    }

    // MARK: preview

    func testPreviewParsesRequiredAndOptionalFlags() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit", "--output-dir", "/tmp/prev"]),
            .preview(app: "TextEdit", options: PreviewCaptureOptions(outputDirectory: "/tmp/prev"))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: [
                "preview", "TextEdit",
                "--output-dir", "/tmp/prev",
                "--duration", "5",
                "--fps", "12",
                "--max-width", "640",
                "--quality", "0.5",
                "--include-cursor",
            ]),
            .preview(app: "TextEdit", options: PreviewCaptureOptions(
                outputDirectory: "/tmp/prev",
                duration: 5,
                framesPerSecond: 12,
                maxWidth: 640,
                jpegQuality: 0.5,
                includeCursor: true
            ))
        )
    }

    func testPreviewRequiresAppAndOutputDir() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "--output-dir", "/tmp/prev"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit", "--output-dir"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit", "--output-dir", "/tmp/p", "--fps", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit", "--output-dir", "/tmp/p", "--duration", "-1"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["preview", "TextEdit", "--output-dir", "/tmp/p", "--quality", "abc"]))
    }

    // MARK: record

    func testRecordParsesRequiredAndOptionalFlags() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["record", "TextEdit", "--output", "/tmp/rec.mp4"]),
            .record(app: "TextEdit", options: RecordingCaptureOptions(outputPath: "/tmp/rec.mp4"))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: [
                "record", "TextEdit",
                "--output", "/tmp/rec.mp4",
                "--duration", "10",
                "--fps", "30",
                "--max-width", "1280",
                "--bitrate", "8000000",
                "--include-cursor",
            ]),
            .record(app: "TextEdit", options: RecordingCaptureOptions(
                outputPath: "/tmp/rec.mp4",
                duration: 10,
                framesPerSecond: 30,
                maxWidth: 1280,
                bitrate: 8_000_000,
                includeCursor: true
            ))
        )
    }

    func testRecordRequiresAppAndOutput() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["record"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["record", "TextEdit"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["record", "TextEdit", "--output"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["record", "TextEdit", "--output", "/tmp/r.mp4", "--bitrate", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["record", "TextEdit", "--output", "/tmp/r.mp4", "--max-width", "wide"]))
    }

    func testPreviewAndRecordNeverProxyToAppAgent() {
        for command in [
            OpenComputerUseCLICommand.preview(app: "A", options: PreviewCaptureOptions(outputDirectory: "/tmp/p")),
            .record(app: "A", options: RecordingCaptureOptions(outputPath: "/tmp/r.mp4")),
        ] {
            XCTAssertFalse(shouldUseMacOSAppAgentProxy(
                command: command,
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            ))
        }
    }

    func testHelpTopicsExistForNewCommands() {
        for topic in ["doctor", "tools", "targets", "inspect", "preview", "record"] {
            XCTAssertEqual(
                try parseOpenComputerUseCLI(arguments: [topic, "--help"]),
                .help(command: topic)
            )
            let help = openComputerUseHelpText(command: topic)
            XCTAssertFalse(help.isEmpty, "help text missing for \(topic)")
        }
    }
}
