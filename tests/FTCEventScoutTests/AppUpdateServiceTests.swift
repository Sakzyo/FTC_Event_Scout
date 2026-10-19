import Foundation
import XCTest
@testable import FTCEventScout

final class AppUpdateServiceTests: XCTestCase {
    func testPackagedApplicationAcceptsSignedHTTPSUpdateConfiguration() throws {
        let bundle = try makeBundle()
        XCTAssertNoThrow(try AppUpdateConfiguration(bundle: bundle))
    }

    func testMissingOrMalformedPublicKeyPreventsUpdates() throws {
        for key in ["", "not-a-public-key", Data(repeating: 1, count: 31).base64EncodedString()] {
            let bundle = try makeBundle(publicKey: key)
            XCTAssertThrowsError(try AppUpdateConfiguration(bundle: bundle)) { error in
                XCTAssertEqual(error as? AppUpdateConfigurationError, .invalidPublicKey)
            }
        }
    }

    func testRemoteHTTPFeedIsRejected() throws {
        let bundle = try makeBundle(feed: "http://example.com/appcast.xml")
        XCTAssertThrowsError(try AppUpdateConfiguration(bundle: bundle)) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .insecureFeed)
        }
    }

    func testMissingBuildNumberPreventsUpdates() throws {
        let bundle = try makeBundle(build: "")
        XCTAssertThrowsError(try AppUpdateConfiguration(bundle: bundle)) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .missingBuildNumber)
        }
    }

    func testUnsignedUpdateExtractionIsRejected() throws {
        let bundle = try makeBundle(verifyBeforeExtraction: false)
        XCTAssertThrowsError(try AppUpdateConfiguration(bundle: bundle)) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .signatureVerificationRequired)
        }
    }

    private func makeBundle(
        feed: String = "https://github.com/Sakzyo/FTC_Event_Scout/releases/latest/download/appcast.xml",
        publicKey: String = Data(repeating: 1, count: 32).base64EncodedString(),
        build: String = "6",
        verifyBeforeExtraction: Bool = true
    ) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = root.appendingPathComponent("FTC Event Scout.app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.ftceventscout.update-tests.\(UUID().uuidString)",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": build,
            "SUFeedURL": feed,
            "SUPublicEDKey": publicKey,
            "SUVerifyUpdateBeforeExtraction": verifyBeforeExtraction,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: appURL))
    }
}
