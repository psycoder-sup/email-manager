import Foundation

// MARK: - Base64URL Encoding/Decoding

extension Data {
    /// Returns a Base64URL encoded string (RFC 4648 Section 5).
    /// Used for Gmail API message encoding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Creates Data from a Base64URL encoded string.
    /// - Parameter base64URLEncoded: The Base64URL encoded string
    init?(base64URLEncoded: String) {
        var base64 = base64URLEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let paddingLength = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingLength)

        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        self = data
    }
}

extension String {
    /// Decodes a Base64URL encoded string to Data.
    func base64URLDecoded() -> Data? {
        Data(base64URLEncoded: self)
    }

    /// Decodes a Base64URL encoded string to a UTF-8 string.
    func base64URLDecodedString() -> String? {
        guard let data = base64URLDecoded() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
