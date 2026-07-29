import XCTest
@testable import OpenComputerUseKit

/// Structured error contract: stable codes, phases, retryability, hints,
/// candidate lists, and CLI exit status mapping.
final class StructuredErrorsContractTests: XCTestCase {
    func testErrorDescriptionsKeepOfficialShape() {
        XCTAssertEqual(ComputerUseError.message("plain").errorDescription, "plain")
        XCTAssertEqual(ComputerUseError.unsupportedTool("nope").errorDescription, "unsupportedTool(\"nope\")")
        XCTAssertEqual(ComputerUseError.invalidArguments("bad").errorDescription, "invalidArguments(\"bad\")")
        XCTAssertEqual(ComputerUseError.appNotFound("App").errorDescription, "appNotFound(\"App\")")
        XCTAssertEqual(
            ComputerUseError.ambiguousApp("Saf", candidates: ["Safari — com.apple.Safari (pid 1)"]).errorDescription,
            "ambiguousApp(\"Saf\", candidates: Safari — com.apple.Safari (pid 1))"
        )
        XCTAssertEqual(ComputerUseError.permissionDenied("denied").errorDescription, "denied")
        XCTAssertEqual(ComputerUseError.stateUnavailable("gone").errorDescription, "gone")
        XCTAssertEqual(ComputerUseError.staleState("old").errorDescription, "old")
        XCTAssertEqual(
            ComputerUseError.missingArgument("app").errorDescription,
            "Missing required argument: app"
        )
    }

    func testErrorPhaseRawValuesAreStable() {
        XCTAssertEqual(ComputerUseErrorPhase.parse.rawValue, "parse")
        XCTAssertEqual(ComputerUseErrorPhase.preflight.rawValue, "preflight")
        XCTAssertEqual(ComputerUseErrorPhase.resolve.rawValue, "resolve")
        XCTAssertEqual(ComputerUseErrorPhase.execute.rawValue, "execute")
    }

    func testUnsupportedToolInfoCarriesToolNameCandidates() {
        let info = computerUseErrorInfo(for: ComputerUseError.unsupportedTool("nope"), phase: .preflight, callIndex: 2)

        XCTAssertEqual(info.code, "unsupported_tool")
        XCTAssertEqual(info.phase, .preflight)
        XCTAssertEqual(info.callIndex, 2)
        XCTAssertFalse(info.retryable)
        XCTAssertEqual(info.candidates, ToolDefinitions.all.map(\.name))
        XCTAssertEqual(info.hint, "run `open-computer-use tools` to list supported tools")
    }

    func testInvalidArgumentsInfoIsNotRetryable() {
        let info = computerUseErrorInfo(for: ComputerUseError.invalidArguments("bad"), phase: .execute)

        XCTAssertEqual(info.code, "invalid_arguments")
        XCTAssertFalse(info.retryable)
        XCTAssertEqual(info.message, "invalidArguments(\"bad\")")
        XCTAssertNil(info.callIndex)
        XCTAssertTrue(info.candidates.isEmpty)
    }

    func testAppNotFoundInfoIsRetryableWithTargetsHint() {
        let info = computerUseErrorInfo(for: ComputerUseError.appNotFound("App"), phase: .resolve)

        XCTAssertEqual(info.code, "app_not_found")
        XCTAssertTrue(info.retryable)
        XCTAssertEqual(info.hint, "run `open-computer-use targets --running-only` to list running apps, then retry")
        XCTAssertEqual(info.message, "appNotFound(\"App\")")
    }

    func testAmbiguousAppInfoCarriesCandidatesAndDisambiguationHint() {
        let candidates = ["Safari — com.apple.Safari (pid 1)", "Safari — com.apple.Safari (pid 2)"]
        let info = computerUseErrorInfo(
            for: ComputerUseError.ambiguousApp("Safari", candidates: candidates),
            phase: .resolve
        )

        XCTAssertEqual(info.code, "ambiguous_app")
        XCTAssertFalse(info.retryable)
        XCTAssertEqual(info.candidates, candidates)
        XCTAssertEqual(info.hint, "target an exact candidate with `pid:<pid>` or a bundle identifier")
    }

    func testPermissionDeniedInfoPointsAtDoctor() {
        let info = computerUseErrorInfo(for: ComputerUseError.permissionDenied("denied"), phase: .resolve)

        XCTAssertEqual(info.code, "permission_denied")
        XCTAssertFalse(info.retryable)
        XCTAssertEqual(info.hint, "run `open-computer-use doctor` to review permissions")
    }

    func testStateUnavailableInfoIsRetryable() {
        let info = computerUseErrorInfo(for: ComputerUseError.stateUnavailable("gone"), phase: .execute)

        XCTAssertEqual(info.code, "state_unavailable")
        XCTAssertTrue(info.retryable)
        XCTAssertEqual(info.hint, "call get_app_state to capture fresh state, then retry")
    }

    func testStaleStateInfoIsRetryableWithRefreshHint() {
        let info = computerUseErrorInfo(for: ComputerUseError.staleState("old"), phase: .execute, callIndex: 1)

        XCTAssertEqual(info.code, "stale_state")
        XCTAssertTrue(info.retryable)
        XCTAssertEqual(info.callIndex, 1)
        XCTAssertEqual(info.hint, "call get_app_state to refresh state_id, then retry")
    }

    func testGenericAndUnknownErrorsMapToErrorCode() {
        let messageInfo = computerUseErrorInfo(for: ComputerUseError.message("plain"), phase: .execute)
        XCTAssertEqual(messageInfo.code, "error")
        XCTAssertFalse(messageInfo.retryable)

        struct ForeignError: Error {}
        let foreignInfo = computerUseErrorInfo(for: ForeignError(), phase: .parse)
        XCTAssertEqual(foreignInfo.code, "error")
        XCTAssertEqual(foreignInfo.phase, .parse)
    }

    func testCLIErrorMapsToUsageCodeWithHelpHint() {
        let info = computerUseErrorInfo(
            for: OpenComputerUseCLIError(message: "bad flag", helpCommand: "call"),
            phase: .parse
        )

        XCTAssertEqual(info.code, "usage")
        XCTAssertFalse(info.retryable)
        XCTAssertEqual(info.hint, "run `open-computer-use help call`")
        XCTAssertEqual(info.message, "bad flag")
    }

    func testErrorInfoDictionaryOmitsUnsetOptionalKeys() {
        let minimal = ComputerUseErrorInfo(code: "error", phase: .execute, retryable: false, message: "m")
        let dictionary = minimal.asDictionary

        XCTAssertEqual(dictionary["code"] as? String, "error")
        XCTAssertEqual(dictionary["phase"] as? String, "execute")
        XCTAssertEqual(dictionary["retryable"] as? Bool, false)
        XCTAssertEqual(dictionary["message"] as? String, "m")
        XCTAssertNil(dictionary["call_index"])
        XCTAssertNil(dictionary["hint"])
        XCTAssertNil(dictionary["candidates"])

        let full = ComputerUseErrorInfo(
            code: "ambiguous_app",
            phase: .resolve,
            callIndex: 3,
            retryable: true,
            hint: "h",
            candidates: ["a"],
            message: "m"
        ).asDictionary
        XCTAssertEqual(full["call_index"] as? Int, 3)
        XCTAssertEqual(full["hint"] as? String, "h")
        XCTAssertEqual(full["candidates"] as? [String], ["a"])
    }

    func testExitStatusRawValuesAreStable() {
        XCTAssertEqual(OpenComputerUseExitStatus.allCases.count, 8)
        XCTAssertEqual(OpenComputerUseExitStatus.success.rawValue, 0)
        XCTAssertEqual(OpenComputerUseExitStatus.failure.rawValue, 1)
        XCTAssertEqual(OpenComputerUseExitStatus.usage.rawValue, 2)
        XCTAssertEqual(OpenComputerUseExitStatus.permissionDenied.rawValue, 3)
        XCTAssertEqual(OpenComputerUseExitStatus.appNotFound.rawValue, 4)
        XCTAssertEqual(OpenComputerUseExitStatus.ambiguousTarget.rawValue, 5)
        XCTAssertEqual(OpenComputerUseExitStatus.stateUnavailable.rawValue, 6)
        XCTAssertEqual(OpenComputerUseExitStatus.staleState.rawValue, 7)
    }

    func testExitStatusMappingCoversEveryErrorCase() {
        XCTAssertEqual(openComputerUseExitStatus(for: OpenComputerUseCLIError(message: "x")), .usage)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.message("x")), .failure)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.unsupportedTool("x")), .usage)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.invalidArguments("x")), .usage)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.appNotFound("x")), .appNotFound)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.ambiguousApp("x", candidates: [])), .ambiguousTarget)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.permissionDenied("x")), .permissionDenied)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.stateUnavailable("x")), .stateUnavailable)
        XCTAssertEqual(openComputerUseExitStatus(for: ComputerUseError.staleState("x")), .staleState)

        struct ForeignError: Error {}
        XCTAssertEqual(openComputerUseExitStatus(for: ForeignError()), .failure)
    }
}
