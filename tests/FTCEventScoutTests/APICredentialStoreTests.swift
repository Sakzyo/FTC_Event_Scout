import Foundation
import XCTest
@testable import FTCEventScout

final class APICredentialStoreTests: XCTestCase {
    func testTokenRoundTripUsesUserOnlyFilePermissions() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FTCEventScoutTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = APICredentialStore(
            fileManager: fileManager,
            directoryProvider: { directory }
        )

        XCTAssertNil(try store.loadToken())
        try store.saveToken("first-token")
        XCTAssertEqual(try store.loadToken(), "first-token")

        try store.saveToken("updated-token")
        XCTAssertEqual(try store.loadToken(), "updated-token")

        let tokenURL = directory.appendingPathComponent(APICredentialStore.tokenFileName)
        let attributes = try fileManager.attributesOfItem(atPath: tokenURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)

        let directoryAttributes = try fileManager.attributesOfItem(atPath: directory.path)
        let directoryPermissions = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(directoryPermissions, 0o700)
    }
}
