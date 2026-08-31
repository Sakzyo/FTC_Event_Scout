import Foundation
import XCTest
@testable import FTCEventScout

final class AppUpdateServiceTests: XCTestCase {
    func testVersionComparisonHandlesTagsAndPrereleases() throws {
        let version100 = try XCTUnwrap(AppVersion("v1.0.0"))
        let version101 = try XCTUnwrap(AppVersion("1.0.1"))
        let version110Beta = try XCTUnwrap(AppVersion("v1.1.0-beta.2"))
        let version110 = try XCTUnwrap(AppVersion("1.1.0"))

        XCTAssertEqual(version100, AppVersion("1.0"))
        XCTAssertLessThan(version100, version101)
        XCTAssertLessThan(version101, version110Beta)
        XCTAssertLessThan(version110Beta, version110)
    }

    func testLatestReleaseSelectsTheOfficialDMGAndDigest() throws {
        let data = Data(
            #"""
            {
              "tag_name": "v1.0.1",
              "html_url": "https://github.com/Sakzyo/FTC_Event_Scout/releases/tag/v1.0.1",
              "assets": [
                {
                  "name": "FTC-Event-Scout-1.0.1.dmg",
                  "browser_download_url": "https://github.com/Sakzyo/FTC_Event_Scout/releases/download/v1.0.1/FTC-Event-Scout-1.0.1.dmg",
                  "digest": "sha256:fba2904bb1cc23cd9bbbbe4ccbdcf60abb513f47dea60425c4320f78f5ed665f"
                }
              ]
            }
            """#.utf8
        )

        let release = try AppUpdateService.decodeRelease(data)

        XCTAssertEqual(release.version, AppVersion("1.0.1"))
        XCTAssertEqual(release.installer.name, "FTC-Event-Scout-1.0.1.dmg")
        XCTAssertEqual(
            AppUpdateService.normalizedSHA256(try XCTUnwrap(release.installer.digest)),
            "fba2904bb1cc23cd9bbbbe4ccbdcf60abb513f47dea60425c4320f78f5ed665f"
        )
    }

    func testReleaseRejectsAnInstallerHostedOutsideGitHub() {
        let data = Data(
            #"""
            {
              "tag_name": "v2.0.0",
              "html_url": "https://github.com/Sakzyo/FTC_Event_Scout/releases/tag/v2.0.0",
              "assets": [
                {
                  "name": "FTC-Event-Scout-2.0.0.dmg",
                  "browser_download_url": "https://example.com/FTC-Event-Scout-2.0.0.dmg",
                  "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                }
              ]
            }
            """#.utf8
        )

        XCTAssertThrowsError(try AppUpdateService.decodeRelease(data)) { error in
            guard case AppUpdateError.installerUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSHA256UsesStreamingFileHashing() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTCEventScoutUpdateTests-\(UUID().uuidString)")
        try Data("FTC Event Scout".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(
            try AppUpdateService.sha256(of: fileURL),
            "e49c46408672ed3b0f321385a3ad6439f2f176f83126dee2c791f0a176f94b37"
        )
    }
}
