import XCTest
@testable import ClaudeUsageBar

final class StoredCredentialsTests: XCTestCase {
    func testNeedsRefreshWhenNoRefreshToken() {
        let creds = StoredCredentials(
            accessToken: "tok",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(30),
            scopes: []
        )
        XCTAssertFalse(creds.needsRefresh())
    }

    func testNeedsRefreshWhenNotExpiring() {
        let creds = StoredCredentials(
            accessToken: "tok",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            scopes: ["user:profile"]
        )
        XCTAssertFalse(creds.needsRefresh())
    }

    func testNeedsRefreshWhenAboutToExpire() {
        let creds = StoredCredentials(
            accessToken: "tok",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(30),
            scopes: ["user:profile"]
        )
        XCTAssertTrue(creds.needsRefresh(leeway: 60))
    }

    func testNeedsRefreshWhenNoExpiry() {
        let creds = StoredCredentials(
            accessToken: "tok",
            refreshToken: "refresh",
            expiresAt: nil,
            scopes: []
        )
        XCTAssertFalse(creds.needsRefresh())
    }

    func testCodableRoundTrip() throws {
        let original = StoredCredentials(
            accessToken: "access123",
            refreshToken: "refresh456",
            expiresAt: Date(timeIntervalSince1970: 1700000000),
            scopes: ["user:profile", "user:inference"]
        )
        let data = try JSONEncoder.iso8601Encoder.encode(original)
        let decoded = try JSONDecoder.iso8601Decoder.decode(StoredCredentials.self, from: data)
        XCTAssertEqual(decoded.accessToken, original.accessToken)
        XCTAssertEqual(decoded.refreshToken, original.refreshToken)
        XCTAssertEqual(decoded.scopes, original.scopes)
    }
}
