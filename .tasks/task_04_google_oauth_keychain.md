# Task 04: Google OAuth & Keychain

## Task Overview

Implement Google OAuth 2.0 authentication flow for Gmail access and secure token storage using macOS Keychain. This enables users to authenticate their Gmail accounts and maintains persistent, secure access.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models (Account model)
- Task 03: Local Database Layer (AccountRepository)

## Architectural Guidelines

### Design Patterns
- **Service Pattern**: Encapsulate OAuth logic in a dedicated service
- **Facade Pattern**: Provide simple interface over complex OAuth flow
- **Observer Pattern**: Notify app of auth state changes

### SwiftUI/Swift Conventions
- Use `ASWebAuthenticationSession` for OAuth flow
- Use Security framework for Keychain operations
- Handle token refresh transparently

### File Organization
```
Core/Services/Authentication/
├── AuthenticationProtocols.swift   # Protocol definitions for testability
├── AuthenticationService.swift     # Main authentication orchestrator
├── GoogleOAuthClient.swift         # Google OAuth API client
├── GoogleUserProfile.swift         # User profile model
├── KeychainService.swift           # Keychain wrapper
├── OAuthTokens.swift               # Token model
└── TokenManager.swift              # Token lifecycle manager

Core/Errors/
├── AuthenticationError.swift       # OAuth error types
└── KeychainError.swift             # Keychain error types
```

## Implementation Details

### KeychainService

**Purpose**: Generic Keychain wrapper for secure storage
**Type**: Singleton class conforming to `KeychainServiceProtocol, @unchecked Sendable`

**Public Interface**:
- `save<T: Codable>(_:forKey:) throws` - Serialize and store item
- `retrieve<T: Codable>(_:forKey:) throws -> T` - Retrieve and deserialize
- `delete(forKey:) throws` - Remove item

**Key Behaviors**:
- Service identifier: `com.cluademail.tokens`
- Delete existing item before save (upsert behavior)
- Thread-safe using `NSLock`
- Keychain accessibility: `kSecAttrAccessibleAfterFirstUnlock`
- Throw `KeychainError` for failures: itemNotFound, duplicateItem, unexpectedStatus, encodingError, decodingError

---

### OAuthTokens Model

**Purpose**: Store OAuth token data
**Type**: Struct conforming to `Codable, Sendable, Equatable`

**Properties**:
- `accessToken`: String
- `refreshToken`: String
- `expiresAt`: Date
- `scope`: String

**Computed Properties**:
- `isExpired`: Bool - Returns true if current time >= expiresAt minus 5 minute buffer (300 seconds)

**Initializers**:
- `init(accessToken:refreshToken:expiresIn:scope:)` - Creates tokens from token response (calculates expiresAt)
- `init(accessToken:refreshToken:expiresAt:scope:)` - Creates tokens with explicit expiration date

---

### TokenManager

**Purpose**: Manage OAuth tokens per account
**Type**: Actor with KeychainService and OAuthClient dependencies (thread-safe)

**Public Interface**:
- `saveTokens(_:for:) async throws` - Store tokens for account email
- `getTokens(for:) async throws -> OAuthTokens` - Retrieve tokens
- `deleteTokens(for:) async throws` - Remove tokens (silent on not found)
- `getValidAccessToken(for:) async throws -> String` - Get token, refreshing if needed
- `hasTokens(for:) async -> Bool` - Check if tokens exist without throwing

**Key Behaviors**:
- Token key format: `oauth_tokens_{email}`
- Automatically refresh expired tokens via GoogleOAuthClient
- Save refreshed tokens back to Keychain
- Delete stale tokens on invalid_grant error
- Dependency injection via init for testing

---

### AuthenticationService

**Purpose**: Orchestrate complete OAuth flow
**Type**: `@Observable @MainActor` class extending `NSObject`

**Properties**:
- `isAuthenticating`: Bool (read-only)

**Dependencies** (injected via init):
- `oauthClient: OAuthClientProtocol`
- `tokenManager: TokenManagerProtocol`
- `accountRepository: AccountRepositoryProtocol`

**Public Interface**:
- `signIn(presentingFrom:context:) async throws -> Account`
- `signOut(_:context:) async throws`
- `getAccessToken(for:) async throws -> String`
- `loadAuthenticatedAccounts(context:) async throws -> [Account]`

**Sign-In Flow**:
1. Build authorization URL with PKCE via GoogleOAuthClient
2. Present `ASWebAuthenticationSession` with callback scheme `cluademail`
3. Extract authorization code and state from callback URL
4. Exchange code for tokens via GoogleOAuthClient
5. Fetch user profile (email, name, picture)
6. Check for existing account:
   - If account exists with tokens: throw `accountAlreadyExists`
   - If account exists without tokens: update and re-authenticate
   - If new account: create and save
7. Save tokens to Keychain
8. Return Account

**Sign-Out Flow**:
1. Revoke tokens via OAuth client (fire and forget)
2. Delete tokens from Keychain
3. Delete account from repository

**Presentation Context**:
- Implements `ASWebAuthenticationPresentationContextProviding`
- Handles both main thread and background thread calls
- Uses keyWindow or provided anchor for presentation

---

### GoogleOAuthClient

**Purpose**: Handle Google OAuth API calls
**Type**: Singleton class conforming to `OAuthClientProtocol, @unchecked Sendable`

**Configuration** (from AppConfiguration):
- Client ID: Loaded from Info.plist
- Client Secret: Loaded from Info.plist (required for installed apps)
- Redirect URI: `cluademail://oauth/callback`

**Required Gmail Scopes**:
```
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/gmail.compose
https://www.googleapis.com/auth/gmail.modify
https://www.googleapis.com/auth/gmail.labels
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/userinfo.profile
```

**Public Interface**:
- `buildAuthorizationURL() async -> URL?`
- `extractAuthorizationCode(from:) throws -> AuthorizationResult`
- `exchangeCodeForTokens(_:) async throws -> OAuthTokens`
- `refreshToken(_:) async throws -> OAuthTokens`
- `getUserProfile(accessToken:) async throws -> GoogleUserProfile`
- `revokeToken(_:) async throws`

**AuthorizationResult** (returned from extractAuthorizationCode):
- `code: String` - Authorization code
- `state: String` - State parameter for CSRF verification

**OAuth Endpoints**:
- Authorization: `https://accounts.google.com/o/oauth2/v2/auth`
- Token exchange: `https://oauth2.googleapis.com/token`
- User info: `https://www.googleapis.com/oauth2/v2/userinfo`

**PKCE Flow** (Proof Key for Code Exchange):
- Required for public clients (desktop apps)
- Generate `code_verifier`: 43-128 character random string (A-Z, a-z, 0-9, `-._~`)
- Generate `code_challenge`: Base64URL(SHA256(code_verifier))
- Store code_verifier temporarily during auth flow

**Authorization URL Parameters**:
- `client_id`, `redirect_uri`, `response_type=code`
- `scope` (space-separated)
- `access_type=offline` (for refresh token)
- `prompt=consent` (always show consent screen)
- `code_challenge` (PKCE)
- `code_challenge_method=S256` (PKCE)

**Token Exchange Parameters**:
- `code`, `client_id`, `client_secret`, `redirect_uri`, `grant_type=authorization_code`
- `code_verifier` (PKCE - must match the code_challenge from authorization)

**Token Refresh Parameters**:
- `refresh_token`, `client_id`, `client_secret`, `grant_type=refresh_token`
- Note: Keep original refresh token (not returned on refresh)

**Token Revocation** (for clean sign-out):
- Endpoint: `https://oauth2.googleapis.com/revoke`
- Parameter: `token={access_token or refresh_token}`
- Method: POST with `application/x-www-form-urlencoded`
- Revoke refresh token to invalidate all associated access tokens

**Rate Limiting Handling**:
- Token endpoint may return 429 Too Many Requests
- Implement exponential backoff: 1s, 2s, 4s, max 3 retries
- Cache valid tokens aggressively to minimize refresh calls

**Unverified App Considerations**:
- Google limits unverified apps to 100 users
- Refresh tokens expire after 7 days for unverified apps
- Handle `invalid_grant` error by triggering re-authentication flow
- Display user-friendly message explaining re-auth requirement
- For production: Complete Google OAuth verification process

---

### GoogleUserProfile

**Purpose**: User profile from Google API
**Type**: Struct conforming to `Codable, Sendable, Equatable`

**Properties**:
- `email`: String
- `name`: String
- `picture`: String? (URL to profile picture)

---

### Error Types

**KeychainError** (conforms to `AppError`):
- `itemNotFound` - KEYCHAIN_001
- `duplicateItem` - KEYCHAIN_002
- `unexpectedStatus(OSStatus)` - KEYCHAIN_003
- `encodingError(Error)` - KEYCHAIN_004
- `decodingError(Error)` - KEYCHAIN_005

**AuthenticationError** (conforms to `AppError`):
- `userCancelled` - OAUTH_001
- `invalidResponse` - OAUTH_002
- `tokenExchangeFailed(String?)` - OAUTH_003
- `tokenExpired` - OAUTH_004
- `refreshFailed(Error?)` - OAUTH_005
- `tokenRevoked` - OAUTH_006
- `rateLimited(retryAfter: TimeInterval)` - OAUTH_007
- `networkError(Error)` - OAUTH_008
- `accountAlreadyExists(String)` - OAUTH_009
- `invalidGrant` - OAUTH_010
- `missingConfiguration(String)` - OAUTH_011
- `invalidCallbackURL` - OAUTH_012

## Acceptance Criteria

- [x] `KeychainService` can save, retrieve, and delete Codable items
- [x] `TokenManager` stores OAuth tokens securely in Keychain
- [x] `TokenManager` automatically refreshes expired tokens
- [x] `AuthenticationService` presents OAuth flow via `ASWebAuthenticationSession`
- [x] OAuth callback URL scheme (`cluademail://`) is properly registered
- [x] User can sign in with Google account
- [x] User profile (email, name, picture) is fetched after authentication
- [x] Tokens persist across app restarts
- [x] Sign out removes tokens from Keychain and account from database
- [x] Error handling covers cancelled auth, network errors, invalid responses
- [x] Multiple accounts can be authenticated simultaneously
- [x] **PKCE flow implemented** with code_verifier and code_challenge
- [x] **Client secret** included in token exchange and refresh requests
- [x] **Token revocation** called on sign-out for clean invalidation
- [x] **Rate limiting** handled with exponential backoff on token endpoints
- [x] **Expired refresh token** (invalid_grant) triggers re-authentication prompt

## Implementation Notes

### Protocols for Testability

Three protocols were created to enable dependency injection and testing:

- `KeychainServiceProtocol` - Abstracts Keychain operations
- `OAuthClientProtocol` - Abstracts OAuth provider-specific details
- `TokenManagerProtocol` - Abstracts token lifecycle management

### State Management

- `GoogleOAuthClient` uses state parameter to correlate PKCE code_verifier with callback
- Pending auth flows expire after 5 minutes for security
- Thread-safe access using `NSLock`

### Testing Infrastructure

**Mock Objects Created**:
- `MockKeychainService` - In-memory keychain simulation
- `MockOAuthClient` - Configurable OAuth responses
- `MockTokenManager` - Token storage simulation

**Test Files Created**:
- `AuthenticationErrorTests.swift` - Error code and description tests
- `KeychainServiceTests.swift` - Keychain CRUD operation tests
- `OAuthTokensTests.swift` - Token model and expiration tests
- `TokenManagerTests.swift` - Token management flow tests
- `GoogleOAuthClientTests.swift` - OAuth client tests

### Configuration Updates

- `AppConfiguration` extended with `googleClientSecret` and `oauthCallbackScheme`
- OAuth scopes extended to include `userinfo.email` and `userinfo.profile`
- xcconfig files updated to use environment variables for secrets
- `Info.plist` updated to include `GOOGLE_CLIENT_SECRET`

### Additional Error Cases

Beyond the spec, the following error cases were added:
- `missingConfiguration` - For missing OAuth configuration
- `invalidCallbackURL` - For malformed callback URLs

## References

- [Google OAuth 2.0 for Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Gmail API Scopes](https://developers.google.com/gmail/api/auth/scopes)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
