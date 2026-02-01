import XCTest
@testable import Cluademail

/// Tests for KeychainService.
/// Note: These tests use the actual Keychain, so they require proper entitlements.
/// For CI environments, consider using MockKeychainService instead.
final class KeychainServiceTests: XCTestCase {

    private var sut: KeychainService!
    private let testKey = "test_keychain_item_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        sut = KeychainService.shared
        // Clean up any leftover items
        try? sut.delete(forKey: testKey)
    }

    override func tearDown() {
        // Clean up test items
        try? sut.delete(forKey: testKey)
        sut = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSaveAndRetrieveTokens() throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()

        // When
        try sut.save(tokens, forKey: testKey)
        let retrieved = try sut.retrieve(OAuthTokens.self, forKey: testKey)

        // Then
        XCTAssertEqual(retrieved.accessToken, tokens.accessToken)
        XCTAssertEqual(retrieved.refreshToken, tokens.refreshToken)
        XCTAssertEqual(retrieved.scope, tokens.scope)
    }

    func testSaveOverwritesExistingItem() throws {
        // Given
        let originalTokens = TestFixtures.makeOAuthTokens(accessToken: "original")
        let newTokens = TestFixtures.makeOAuthTokens(accessToken: "updated")

        // When
        try sut.save(originalTokens, forKey: testKey)
        try sut.save(newTokens, forKey: testKey)
        let retrieved = try sut.retrieve(OAuthTokens.self, forKey: testKey)

        // Then
        XCTAssertEqual(retrieved.accessToken, "updated")
    }

    // MARK: - Retrieve Tests

    func testRetrieveNonExistentItemThrowsItemNotFound() throws {
        // Given
        let nonExistentKey = "non_existent_key_\(UUID().uuidString)"

        // When/Then
        do {
            _ = try sut.retrieve(OAuthTokens.self, forKey: nonExistentKey)
            XCTFail("Expected KeychainError.itemNotFound")
        } catch let error as KeychainError {
            XCTAssertEqual(error.errorCode, "KEYCHAIN_001")
        }
    }

    // MARK: - Delete Tests

    func testDeleteExistingItem() throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        try sut.save(tokens, forKey: testKey)

        // When
        try sut.delete(forKey: testKey)

        // Then
        do {
            _ = try sut.retrieve(OAuthTokens.self, forKey: testKey)
            XCTFail("Expected KeychainError.itemNotFound after deletion")
        } catch let error as KeychainError {
            XCTAssertEqual(error.errorCode, "KEYCHAIN_001")
        }
    }

    func testDeleteNonExistentItemDoesNotThrow() throws {
        // Given
        let nonExistentKey = "non_existent_key_\(UUID().uuidString)"

        // When/Then - should not throw
        try sut.delete(forKey: nonExistentKey)
    }

    // MARK: - Error Code Tests

    func testKeychainErrorCodes() {
        XCTAssertEqual(KeychainError.itemNotFound.errorCode, "KEYCHAIN_001")
        XCTAssertEqual(KeychainError.duplicateItem.errorCode, "KEYCHAIN_002")
        XCTAssertEqual(KeychainError.unexpectedStatus(0).errorCode, "KEYCHAIN_003")
        XCTAssertEqual(KeychainError.encodingError(NSError(domain: "", code: 0)).errorCode, "KEYCHAIN_004")
        XCTAssertEqual(KeychainError.decodingError(NSError(domain: "", code: 0)).errorCode, "KEYCHAIN_005")
    }

    func testKeychainErrorRecoverability() {
        XCTAssertFalse(KeychainError.itemNotFound.isRecoverable)
        XCTAssertFalse(KeychainError.duplicateItem.isRecoverable)
        XCTAssertTrue(KeychainError.unexpectedStatus(0).isRecoverable)
        XCTAssertTrue(KeychainError.encodingError(NSError(domain: "", code: 0)).isRecoverable)
        XCTAssertTrue(KeychainError.decodingError(NSError(domain: "", code: 0)).isRecoverable)
    }
}
