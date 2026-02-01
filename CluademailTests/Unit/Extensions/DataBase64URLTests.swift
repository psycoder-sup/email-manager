import XCTest
@testable import Cluademail

final class DataBase64URLTests: XCTestCase {

    // MARK: - Encoding Tests

    func testBase64URLEncodedString_Simple() {
        let data = "Hello, World!".data(using: .utf8)!
        let encoded = data.base64URLEncodedString()

        // Base64URL should not have + or / or =
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testBase64URLEncodedString_MatchesExpected() {
        // "test" in base64 is "dGVzdA=="
        // In base64URL should be "dGVzdA" (no padding)
        let data = "test".data(using: .utf8)!
        let encoded = data.base64URLEncodedString()
        XCTAssertEqual(encoded, "dGVzdA")
    }

    func testBase64URLEncodedString_ReplacesPlusWithMinus() {
        // Data that produces + in standard base64
        // 0xFB = 251, which in base64 gives characters with +
        let data = Data([0xFB, 0xEF])
        let standardBase64 = data.base64EncodedString()
        let base64URL = data.base64URLEncodedString()

        // If there was a + in standard, it should be - in URL safe
        if standardBase64.contains("+") {
            XCTAssertTrue(base64URL.contains("-"))
        }
    }

    func testBase64URLEncodedString_ReplacesSlashWithUnderscore() {
        // Data that produces / in standard base64
        // 0xFF typically produces /
        let data = Data([0xFF, 0xFF])
        let standardBase64 = data.base64EncodedString()
        let base64URL = data.base64URLEncodedString()

        // If there was a / in standard, it should be _ in URL safe
        if standardBase64.contains("/") {
            XCTAssertTrue(base64URL.contains("_"))
        }
    }

    // MARK: - Decoding Tests

    func testBase64URLDecoded_Simple() {
        let encoded = "dGVzdA"
        let data = Data(base64URLEncoded: encoded)

        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "test")
    }

    func testBase64URLDecoded_WithMinus() {
        // Encode something that uses - (was +)
        let original = Data([0xFB, 0xEF])
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, original)
    }

    func testBase64URLDecoded_WithUnderscore() {
        // Encode something that uses _ (was /)
        let original = Data([0xFF, 0xFF])
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, original)
    }

    func testBase64URLDecoded_AddsCorrectPadding() {
        // "a" = "YQ==" in base64, "YQ" in base64URL
        let decoded = Data(base64URLEncoded: "YQ")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "a")

        // "ab" = "YWI=" in base64, "YWI" in base64URL
        let decoded2 = Data(base64URLEncoded: "YWI")
        XCTAssertNotNil(decoded2)
        XCTAssertEqual(String(data: decoded2!, encoding: .utf8), "ab")

        // "abc" = "YWJj" in base64, same in base64URL (no padding needed)
        let decoded3 = Data(base64URLEncoded: "YWJj")
        XCTAssertNotNil(decoded3)
        XCTAssertEqual(String(data: decoded3!, encoding: .utf8), "abc")
    }

    func testBase64URLDecoded_InvalidInput() {
        // Invalid base64 should return nil
        let decoded = Data(base64URLEncoded: "!!!invalid!!!")
        XCTAssertNil(decoded)
    }

    // MARK: - Round-Trip Tests

    func testRoundTrip_ShortString() {
        let original = "Hello".data(using: .utf8)!
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_LongString() {
        let original = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 100).data(using: .utf8)!
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_BinaryData() {
        let original = Data((0..<256).map { UInt8($0) })
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_EmptyData() {
        let original = Data()
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - String Extension Tests

    func testStringBase64URLDecoded() {
        let encoded = "SGVsbG8gV29ybGQ"
        let decoded = encoded.base64URLDecodedString()

        XCTAssertEqual(decoded, "Hello World")
    }

    func testStringBase64URLDecodedString_Invalid() {
        let decoded = "!!!".base64URLDecodedString()
        XCTAssertNil(decoded)
    }
}
