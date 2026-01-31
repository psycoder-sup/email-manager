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
Core/Services/
├── AuthenticationService.swift
├── KeychainService.swift
├── TokenManager.swift
└── GoogleOAuthClient.swift
```

## Implementation Details

### KeychainService

**Purpose**: Generic Keychain wrapper for secure storage
**Type**: Singleton class

**Public Interface**:
- `save<T: Codable>(_:forKey:) throws` - Serialize and store item
- `retrieve<T: Codable>(_:forKey:) throws -> T` - Retrieve and deserialize
- `delete(forKey:) throws` - Remove item

**Key Behaviors**:
- Service identifier: `com.cluademail.tokens`
- Delete existing item before save (upsert behavior)
- Throw `KeychainError` for failures: itemNotFound, duplicateItem, unexpectedStatus, encodingError, decodingError

---

### OAuthTokens Model

**Purpose**: Store OAuth token data
**Type**: Struct conforming to `Codable`

**Properties**:
- `accessToken`: String
- `refreshToken`: String
- `expiresAt`: Date
- `scope`: String

**Computed Properties**:
- `isExpired`: Bool - Returns true if current time >= expiresAt minus 5 minute buffer

---

### TokenManager

**Purpose**: Manage OAuth tokens per account
**Type**: Class with KeychainService dependency

**Public Interface**:
- `saveTokens(_:for:) throws` - Store tokens for account email
- `getTokens(for:) throws -> OAuthTokens` - Retrieve tokens
- `deleteTokens(for:) throws` - Remove tokens
- `getValidAccessToken(for:) async throws -> String` - Get token, refreshing if needed

**Key Behaviors**:
- Token key format: `oauth_tokens_{email}`
- Automatically refresh expired tokens via GoogleOAuthClient
- Save refreshed tokens back to Keychain

---

### AuthenticationService

**Purpose**: Orchestrate complete OAuth flow
**Type**: `@Observable` class

**Properties**:
- `isAuthenticating`: Bool
- `authenticatedAccounts`: [Account]

**Public Interface**:
- `signIn(presentingFrom:) async throws -> Account`
- `signOut(_:) async throws`
- `getAccessToken(for:) async throws -> String`

**Sign-In Flow**:
1. Build authorization URL with GoogleOAuthClient
2. Present `ASWebAuthenticationSession` with callback scheme `cluademail`
3. Extract authorization code from callback URL
4. Exchange code for tokens via GoogleOAuthClient
5. Fetch user profile (email, name, picture)
6. Check if account exists - update tokens if yes, create new if no
7. Save tokens to Keychain
8. Return Account

**Sign-Out Flow**:
1. Delete tokens from Keychain
2. Delete account from repository

**Presentation Context**:
- Implement `ASWebAuthenticationPresentationContextProviding`
- Use keyWindow or provided anchor for presentation

---

### GoogleOAuthClient

**Purpose**: Handle Google OAuth API calls
**Type**: Singleton class

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
- `buildAuthorizationURL() -> URL`
- `exchangeCodeForTokens(_:) async throws -> OAuthTokens`
- `refreshToken(_:) async throws -> OAuthTokens`
- `getUserProfile(accessToken:) async throws -> GoogleUserProfile`

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
**Type**: Struct conforming to `Codable`

**Properties**:
- `email`: String
- `name`: String
- `pictureURL`: String? (coded as "picture")

---

### Error Types

**KeychainError**:
- itemNotFound, duplicateItem, unexpectedStatus(OSStatus), encodingError, decodingError

**AuthenticationError**:
- userCancelled, invalidResponse, tokenExchangeFailed, networkError(Error), accountAlreadyExists
- tokenExpired, refreshFailed, tokenRevoked, rateLimited(retryAfter: TimeInterval)

## Acceptance Criteria

- [ ] `KeychainService` can save, retrieve, and delete Codable items
- [ ] `TokenManager` stores OAuth tokens securely in Keychain
- [ ] `TokenManager` automatically refreshes expired tokens
- [ ] `AuthenticationService` presents OAuth flow via `ASWebAuthenticationSession`
- [ ] OAuth callback URL scheme (`cluademail://`) is properly registered
- [ ] User can sign in with Google account
- [ ] User profile (email, name, picture) is fetched after authentication
- [ ] Tokens persist across app restarts
- [ ] Sign out removes tokens from Keychain and account from database
- [ ] Error handling covers cancelled auth, network errors, invalid responses
- [ ] Multiple accounts can be authenticated simultaneously
- [ ] **PKCE flow implemented** with code_verifier and code_challenge
- [ ] **Client secret** included in token exchange and refresh requests
- [ ] **Token revocation** called on sign-out for clean invalidation
- [ ] **Rate limiting** handled with exponential backoff on token endpoints
- [ ] **Expired refresh token** (invalid_grant) triggers re-authentication prompt

## References

- [Google OAuth 2.0 for Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Gmail API Scopes](https://developers.google.com/gmail/api/auth/scopes)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
