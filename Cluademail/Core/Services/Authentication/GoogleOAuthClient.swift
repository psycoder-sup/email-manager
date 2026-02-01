import Foundation
import CryptoKit
import os.log

/// Client for handling Google OAuth 2.0 authentication flow.
/// Implements PKCE (Proof Key for Code Exchange) for secure authorization.
final class GoogleOAuthClient: OAuthClientProtocol, @unchecked Sendable {

    /// Shared singleton instance
    static let shared = GoogleOAuthClient()

    // MARK: - Configuration

    /// Google OAuth authorization endpoint
    private let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"

    /// Google OAuth token endpoint
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"

    /// Google user info endpoint
    private let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"

    /// Google token revocation endpoint
    private let revocationEndpoint = "https://oauth2.googleapis.com/revoke"

    // MARK: - PKCE State

    /// Lock for thread-safe PKCE state access
    private let lock = NSLock()

    /// Metadata for a pending OAuth authorization flow
    private struct PendingAuthFlow {
        let codeVerifier: String
        let createdAt: Date

        /// Flow expiration interval (5 minutes)
        static let expirationInterval: TimeInterval = 5 * 60

        /// Whether this flow has expired
        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > Self.expirationInterval
        }
    }

    /// Stores pending auth flows keyed by state parameter
    /// Using state parameter ensures the correct verifier is matched to the correct callback
    private var pendingAuthFlows: [String: PendingAuthFlow] = [:]

    // MARK: - Rate Limiting

    /// Maximum retry attempts for rate-limited requests
    private let maxRetries = 3

    /// Base delay for exponential backoff (in seconds)
    private let baseDelay: TimeInterval = 1.0

    private init() {}

    // MARK: - OAuthClientProtocol Implementation

    /// Builds the authorization URL with PKCE challenge.
    /// - Returns: The authorization URL, or nil if URL construction fails
    func buildAuthorizationURL() async -> URL? {
        // Clean up any expired flows before starting a new one
        cleanupExpiredFlows()

        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Generate unique state parameter to correlate callback with this flow
        let state = generateStateParameter()

        // Store verifier keyed by state for later use in token exchange
        lock.lock()
        pendingAuthFlows[state] = PendingAuthFlow(codeVerifier: codeVerifier, createdAt: Date())
        lock.unlock()

        // Build URL components
        guard var components = URLComponents(string: authorizationEndpoint) else {
            Logger.auth.error("Failed to create URL components from authorization endpoint")
            return nil
        }

        let scopes = AppConfiguration.oauthScopes.joined(separator: " ")

        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfiguration.googleClientId),
            URLQueryItem(name: "redirect_uri", value: AppConfiguration.oauthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            Logger.auth.error("Failed to construct authorization URL")
            // Clean up the pending flow
            lock.lock()
            pendingAuthFlows.removeValue(forKey: state)
            lock.unlock()
            return nil
        }

        Logger.auth.info("Built authorization URL with PKCE and state parameter")
        return url
    }

    /// Extracts the authorization code and state from the callback URL.
    /// - Returns: An AuthorizationResult containing the code and state
    func extractAuthorizationCode(from callbackURL: URL) throws -> AuthorizationResult {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            Logger.auth.error("Failed to parse callback URL")
            throw AuthenticationError.invalidCallbackURL
        }

        // Check for error in callback
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value
            Logger.auth.error("OAuth callback error: \(error)")
            // Clean up any pending flows on error
            cleanupAllPendingFlows()
            throw AuthenticationError.tokenExchangeFailed(description ?? error)
        }

        // Extract state parameter
        guard let state = queryItems.first(where: { $0.name == "state" })?.value else {
            Logger.auth.error("No state parameter in callback URL - potential CSRF attack")
            cleanupAllPendingFlows()
            throw AuthenticationError.invalidCallbackURL
        }

        // Verify we have a valid, non-expired pending flow for this state
        lock.lock()
        let pendingFlow = pendingAuthFlows[state]
        lock.unlock()

        guard let flow = pendingFlow else {
            Logger.auth.error("No matching auth flow for state parameter - potential CSRF attack")
            throw AuthenticationError.invalidCallbackURL
        }

        guard !flow.isExpired else {
            Logger.auth.error("Auth flow expired for state parameter")
            lock.lock()
            pendingAuthFlows.removeValue(forKey: state)
            lock.unlock()
            throw AuthenticationError.invalidCallbackURL
        }

        // Extract authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            Logger.auth.error("No authorization code in callback URL")
            throw AuthenticationError.invalidCallbackURL
        }

        Logger.auth.info("Extracted authorization code from callback with valid state")
        return AuthorizationResult(code: code, state: state)
    }

    /// Cleans up all pending auth flows.
    private func cleanupAllPendingFlows() {
        lock.lock()
        pendingAuthFlows.removeAll()
        lock.unlock()
    }

    /// Removes expired auth flows from the pending flows dictionary.
    private func cleanupExpiredFlows() {
        lock.lock()
        defer { lock.unlock() }

        let expiredStates = pendingAuthFlows.filter { $0.value.isExpired }.map { $0.key }
        for state in expiredStates {
            pendingAuthFlows.removeValue(forKey: state)
        }

        if !expiredStates.isEmpty {
            Logger.auth.debug("Cleaned up \(expiredStates.count) expired auth flows")
        }
    }

    /// Exchanges an authorization code for tokens.
    /// - Parameter result: The authorization result containing code and state
    func exchangeCodeForTokens(_ result: AuthorizationResult) async throws -> OAuthTokens {
        // Retrieve and remove the code verifier for this specific auth flow
        lock.lock()
        let pendingFlow = pendingAuthFlows.removeValue(forKey: result.state)
        lock.unlock()

        guard let flow = pendingFlow else {
            Logger.auth.error("No pending code verifier for state: \(result.state, privacy: .private)")
            throw AuthenticationError.invalidResponse
        }

        guard !flow.isExpired else {
            Logger.auth.error("Auth flow expired during token exchange")
            throw AuthenticationError.invalidResponse
        }

        let codeVerifier = flow.codeVerifier

        // Build request body with proper URL encoding
        let parameters = [
            "code": result.code,
            "client_id": AppConfiguration.googleClientId,
            "client_secret": AppConfiguration.googleClientSecret,
            "redirect_uri": AppConfiguration.oauthRedirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]

        // Execute request with retry
        let response: TokenResponse = try await executeTokenRequest(parameters: parameters)

        guard let refreshToken = response.refreshToken else {
            Logger.auth.error("No refresh token in token response")
            throw AuthenticationError.invalidResponse
        }

        let tokens = OAuthTokens(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresIn: TimeInterval(response.expiresIn),
            scope: response.scope ?? AppConfiguration.oauthScopes.joined(separator: " ")
        )

        Logger.auth.info("Successfully exchanged code for tokens")
        return tokens
    }

    /// Refreshes an expired access token.
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokens {
        let parameters = [
            "refresh_token": refreshToken,
            "client_id": AppConfiguration.googleClientId,
            "client_secret": AppConfiguration.googleClientSecret,
            "grant_type": "refresh_token"
        ]

        // Execute request with retry
        let response: TokenResponse = try await executeTokenRequest(parameters: parameters)

        // Preserve the original refresh token (not returned in refresh response)
        let tokens = OAuthTokens(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresIn: TimeInterval(response.expiresIn),
            scope: response.scope ?? AppConfiguration.oauthScopes.joined(separator: " ")
        )

        Logger.auth.info("Successfully refreshed access token")
        return tokens
    }

    /// Fetches the user's profile information.
    func getUserProfile(accessToken: String) async throws -> GoogleUserProfile {
        var request = URLRequest(url: URL(string: userInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        Logger.api.logRequest(method: "GET", url: userInfoEndpoint)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }

        Logger.api.logResponse(statusCode: httpResponse.statusCode, url: userInfoEndpoint)

        guard httpResponse.statusCode == 200 else {
            throw AuthenticationError.invalidResponse
        }

        do {
            let profile = try JSONDecoder().decode(GoogleUserProfile.self, from: data)
            Logger.auth.logEmail("Fetched user profile for", email: profile.email)
            return profile
        } catch {
            Logger.auth.error("Failed to decode user profile: \(error.localizedDescription)")
            throw AuthenticationError.invalidResponse
        }
    }

    /// Revokes a token for clean sign-out.
    func revokeToken(_ token: String) async throws {
        var components = URLComponents(string: revocationEndpoint)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        Logger.api.logRequest(method: "POST", url: revocationEndpoint)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }

        Logger.api.logResponse(statusCode: httpResponse.statusCode, url: revocationEndpoint)

        // Google returns 200 for successful revocation
        // Other status codes indicate the token may already be invalid, which is acceptable
        if httpResponse.statusCode == 200 {
            Logger.auth.info("Successfully revoked token")
        } else {
            Logger.auth.warning("Token revocation returned status \(httpResponse.statusCode)")
        }
    }

    // MARK: - Private Methods

    // MARK: Base64URL Encoding

    /// Encodes data using Base64URL encoding (RFC 4648 Section 5).
    /// This encoding is safe for use in URLs and filenames.
    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: PKCE Helpers

    /// Generates a cryptographically random code verifier for PKCE.
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    /// Generates the code challenge from the code verifier using SHA256.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return base64URLEncode(Data(hash))
    }

    /// Generates a unique state parameter for CSRF protection.
    private func generateStateParameter() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    /// Properly encodes a string for application/x-www-form-urlencoded content type.
    /// Per RFC 3986, this encodes all characters except unreserved characters.
    private func formURLEncode(_ string: String) -> String {
        // Characters allowed in form data (unreserved + space encoded as +)
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")

        // First encode using percent encoding
        guard let encoded = string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return string
        }

        // Then replace spaces with + (form encoding convention)
        return encoded.replacingOccurrences(of: " ", with: "+")
    }

    /// Executes a token endpoint request with exponential backoff for rate limiting.
    private func executeTokenRequest<T: Decodable>(parameters: [String: String]) async throws -> T {
        var lastError: Error = AuthenticationError.invalidResponse
        let maxRetryCount = self.maxRetries
        let baseDelayValue = self.baseDelay

        for attempt in 0..<maxRetryCount {
            do {
                return try await performTokenRequest(parameters: parameters)
            } catch let error as AuthenticationError {
                lastError = error

                // Only retry on rate limiting
                if case .rateLimited(let retryAfter) = error {
                    let delay = retryAfter > 0 ? retryAfter : baseDelayValue * pow(2.0, Double(attempt))
                    Logger.auth.warning("Rate limited, retrying after \(delay) seconds (attempt \(attempt + 1)/\(maxRetryCount))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                throw error
            }
        }

        throw lastError
    }

    /// Performs a single token endpoint request.
    private func performTokenRequest<T: Decodable>(parameters: [String: String]) async throws -> T {
        guard let url = URL(string: tokenEndpoint) else {
            Logger.auth.error("Invalid token endpoint URL")
            throw AuthenticationError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Use proper form URL encoding (RFC 3986 section 2.1)
        // x-www-form-urlencoded requires encoding spaces as '+' and special chars properly
        let body = parameters
            .map { key, value in
                let encodedKey = formURLEncode(key)
                let encodedValue = formURLEncode(value)
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        Logger.api.logRequest(method: "POST", url: tokenEndpoint, hasBody: true)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Logger.auth.error("Network error during token request: \(error.localizedDescription)")
            throw AuthenticationError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }

        Logger.api.logResponse(statusCode: httpResponse.statusCode, url: tokenEndpoint)

        // Handle error responses
        if httpResponse.statusCode != 200 {
            return try handleTokenError(data: data, statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields)
        }

        // Decode successful response
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.auth.error("Failed to decode token response: \(error.localizedDescription)")
            throw AuthenticationError.invalidResponse
        }
    }

    /// Handles error responses from the token endpoint.
    private func handleTokenError<T>(data: Data, statusCode: Int, headers: [AnyHashable: Any]) throws -> T {
        // Try to parse error response
        if let errorResponse = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) {
            Logger.auth.error("Token error: \(errorResponse.error) - \(errorResponse.errorDescription ?? "no description")")

            // Handle specific error types
            switch errorResponse.error {
            case "invalid_grant":
                throw AuthenticationError.invalidGrant
            case "invalid_client":
                throw AuthenticationError.missingConfiguration("Invalid client credentials")
            default:
                throw AuthenticationError.tokenExchangeFailed(errorResponse.errorDescription ?? errorResponse.error)
            }
        }

        // Handle rate limiting
        if statusCode == 429 {
            let retryAfter = (headers["Retry-After"] as? String).flatMap { TimeInterval($0) } ?? 0
            throw AuthenticationError.rateLimited(retryAfter: retryAfter)
        }

        throw AuthenticationError.tokenExchangeFailed("HTTP \(statusCode)")
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Resets all internal state. Only available in DEBUG builds for testing.
    func reset() {
        lock.lock()
        pendingAuthFlows.removeAll()
        lock.unlock()
        Logger.auth.debug("GoogleOAuthClient state reset (testing)")
    }
    #endif
}

// MARK: - Response Types

/// Response from Google's token endpoint
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

/// Error response from Google's token endpoint
private struct TokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
