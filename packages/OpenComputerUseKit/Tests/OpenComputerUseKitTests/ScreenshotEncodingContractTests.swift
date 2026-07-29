import ImageIO
import XCTest
@testable import OpenComputerUseKit

/// Hard screenshot PNG limits: dimension cap, byte cap, bounded encode attempts.
/// All inputs are synthetic CGImages; no screen capture is involved.
final class ScreenshotEncodingContractTests: XCTestCase {
    func testRequestedScreenshotRequiresScreenRecordingPermission() {
        let permissions = PermissionDiagnostics(
            accessibilityTrusted: true,
            screenCaptureGranted: false
        )

        XCTAssertThrowsError(
            try validateSnapshotPermissions(permissions, includeScreenshot: true)
        ) { error in
            guard case let ComputerUseError.permissionDenied(message) = error else {
                return XCTFail("expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(message.contains("Screen Recording permission is required"))
        }
    }

    func testTextOnlySnapshotDoesNotRequireScreenRecordingPermission() {
        let permissions = PermissionDiagnostics(
            accessibilityTrusted: true,
            screenCaptureGranted: false
        )

        XCTAssertNoThrow(
            try validateSnapshotPermissions(permissions, includeScreenshot: false)
        )
    }

    func testEncodingLimitsDefaultsMatchContract() {
        XCTAssertEqual(ScreenshotEncodingLimits.defaultMaxBytes, 900_000)
        XCTAssertEqual(ScreenshotEncodingLimits.defaultMaxDimension, 1280)
        XCTAssertEqual(ScreenshotEncodingLimits.defaultMaxEncodeAttempts, 3)
        XCTAssertEqual(ScreenshotEncodingLimits.defaultScaleStep, 0.7)

        let defaults = ScreenshotEncodingLimits.defaults
        XCTAssertEqual(defaults.maxBytes, 900_000)
        XCTAssertEqual(defaults.maxDimension, 1280)
        XCTAssertEqual(defaults.maxEncodeAttempts, 3)
        XCTAssertEqual(defaults.scaleStep, 0.7)
    }

    func testFittingScaleOnlyShrinksOversizedImages() {
        let limits = ScreenshotEncodingLimits(maxBytes: 1_000, maxDimension: 1280)

        XCTAssertEqual(limits.fittingScale(forPixelSize: CGSize(width: 640, height: 480)), 1)
        XCTAssertEqual(limits.fittingScale(forPixelSize: CGSize(width: 1280, height: 720)), 1)
        XCTAssertEqual(limits.fittingScale(forPixelSize: .zero), 1)
        XCTAssertEqual(limits.fittingScale(forPixelSize: CGSize(width: 2560, height: 1440)), 0.5)
        // Long edge rules: a tall image scales by height.
        XCTAssertEqual(limits.fittingScale(forPixelSize: CGSize(width: 100, height: 5120)), 0.25)
    }

    func testOversizedSolidScreenshotIsScaledToDimensionCap() throws {
        let image = try ContractTestImages.solidCGImage(width: 2000, height: 1000)
        let encoded = try encodeBoundedScreenshotPNG(for: image)

        XCTAssertEqual(encoded.pixelSize, CGSize(width: 1280, height: 640))
        XCTAssertLessThanOrEqual(encoded.pngData.count, ScreenshotEncodingLimits.defaultMaxBytes)
        // The on-disk payload really is the advertised size.
        XCTAssertEqual(try ContractTestImages.encodedPixelSize(encoded.pngData), encoded.pixelSize)
    }

    func testSmallScreenshotKeepsOriginalSize() throws {
        let image = try ContractTestImages.solidCGImage(width: 32, height: 24)
        let encoded = try encodeBoundedScreenshotPNG(for: image)

        XCTAssertEqual(encoded.pixelSize, CGSize(width: 32, height: 24))
    }

    func testNoisyScreenshotWiderThan5120PixelsIsBoundedOnBothAxes() throws {
        // 5128 > 5120: the encoder must downscale before the first encode and
        // still satisfy the byte cap, rather than shipping a multi-megabyte PNG.
        let image = try ContractTestImages.noisyCGImage(width: 5128, height: 2884)
        let encoded = try encodeBoundedScreenshotPNG(for: image)

        XCTAssertLessThanOrEqual(max(encoded.pixelSize.width, encoded.pixelSize.height), 1280)
        XCTAssertLessThanOrEqual(encoded.pngData.count, ScreenshotEncodingLimits.defaultMaxBytes)
        XCTAssertEqual(try ContractTestImages.encodedPixelSize(encoded.pngData), encoded.pixelSize)
    }

    func testEncodeAttemptsAreExhaustedBeforeFailing() throws {
        let image = try ContractTestImages.noisyCGImage(width: 1600, height: 1200)
        let limits = ScreenshotEncodingLimits(maxBytes: 10_000, maxDimension: 1280)

        XCTAssertThrowsError(try encodeBoundedScreenshotPNG(for: image, limits: limits)) { error in
            guard case let ScreenshotEncodingError.exceedsByteLimit(bytes, maxBytes, attempts) = error else {
                return XCTFail("expected exceedsByteLimit, got \(error)")
            }
            XCTAssertEqual(attempts, 3)
            XCTAssertEqual(maxBytes, 10_000)
            XCTAssertGreaterThan(bytes, maxBytes)
        }
    }

    func testEncodeAttemptCountIsRespected() throws {
        let image = try ContractTestImages.noisyCGImage(width: 1600, height: 1200)
        let limits = ScreenshotEncodingLimits(maxBytes: 10_000, maxDimension: 1280, maxEncodeAttempts: 1)

        XCTAssertThrowsError(try encodeBoundedScreenshotPNG(for: image, limits: limits)) { error in
            guard case let ScreenshotEncodingError.exceedsByteLimit(_, _, attempts) = error else {
                return XCTFail("expected exceedsByteLimit, got \(error)")
            }
            XCTAssertEqual(attempts, 1)
        }
    }

    func testSuccessfulEncodeNeverReturnsOversizedData() throws {
        // Even when only the final attempt fits, the returned payload respects
        // the byte cap exactly.
        let image = try ContractTestImages.noisyCGImage(width: 800, height: 600)
        let limits = ScreenshotEncodingLimits(maxBytes: 40_000, maxDimension: 800, maxEncodeAttempts: 6, scaleStep: 0.35)
        let encoded = try encodeBoundedScreenshotPNG(for: image, limits: limits)

        XCTAssertLessThanOrEqual(encoded.pngData.count, 40_000)
    }

    func testEncodingErrorMessagesAreStable() {
        XCTAssertEqual(
            screenshotEncodingErrorMessage(.emptyImage),
            "Screenshot capture produced an empty image."
        )
        XCTAssertEqual(
            screenshotEncodingErrorMessage(.encodingFailed),
            "Screenshot PNG encoding failed."
        )
        XCTAssertEqual(
            screenshotEncodingErrorMessage(.exceedsByteLimit(bytes: 1234, maxBytes: 1000, attempts: 3)),
            "Screenshot PNG is 1234 bytes, exceeding the 1000-byte limit after 3 encode attempts."
        )
    }

    func testEncodingErrorIsEquatable() {
        XCTAssertEqual(ScreenshotEncodingError.emptyImage, .emptyImage)
        XCTAssertEqual(
            ScreenshotEncodingError.exceedsByteLimit(bytes: 1, maxBytes: 2, attempts: 3),
            .exceedsByteLimit(bytes: 1, maxBytes: 2, attempts: 3)
        )
        XCTAssertNotEqual(
            ScreenshotEncodingError.exceedsByteLimit(bytes: 1, maxBytes: 2, attempts: 3),
            .exceedsByteLimit(bytes: 1, maxBytes: 2, attempts: 4)
        )
    }
}
