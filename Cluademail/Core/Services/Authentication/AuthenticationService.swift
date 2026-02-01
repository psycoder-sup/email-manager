import Foundation
import AuthenticationServices
import SwiftData
import os.log

/// Orchestrates the OAuth authentication flow for Gmail accounts.
/// Uses ASWebAuthenticationSession for secure browser-based authentication.
@Observable
@MainActor
final class AuthenticationService: NSObject {

    // MARK: - Observable State

    /// Whether an authentication flow is currently in progress
    private(set) var isAuthenticating: Bool = false

    // MARK: - Dependencies

    /// OAuth client for Google API calls
    private let oauthClient: any OAuthClientProtocol

    /// Token manager for secure token storage
    private let tokenManager: any TokenManagerProtocol

    /// Account repository for database operations
    private let accountRepository: any AccountRepositoryProtocol

    /// Window anchor for presenting the authentication session
    private weak var presentationAnchor: NSWindow?

    // MARK: - Initialization

    /// Creates an AuthenticationService with default dependencies.
    init(
        oauthClient: any OAuthClientProtocol = GoogleOAuthClient.shared,
        tokenManager: any TokenManagerProtocol = TokenManager.shared,
        accountRepository: any AccountRepositoryProtocol = AccountRepository()
    ) {
        self.oauthClient = oauthClient
        self.tokenManager = tokenManager
        self.accountRepository = accountRepository
        super.init()
    }

    // MARK: - Public Methods

    /// Signs in with a Google account.
    /// - Parameters:
    ///   - window: The window to present the authentication session from
    ///   - context: The SwiftData model context for database operations
    /// - Returns: The authenticated Account
    func signIn(presentingFrom window: NSWindow?, context: ModelContext) async throws -> Account {
        guard !isAuthenticating else {
            Logger.auth.warning("Sign-in already in progress")
            throw AuthenticationError.userCancelled
        }

        isAuthenticating = true
        presentationAnchor = window

        defer {
            isAuthenticating = false
            presentationAnchor = nil
        }

        Logger.auth.info("Starting OAuth sign-in flow")

        // Build authorization URL with PKCE
        guard let authURL = await oauthClient.buildAuthorizationURL() else {
            Logger.auth.error("Failed to build authorization URL")
            throw AuthenticationError.invalidResponse
        }

        // Present authentication session
        let callbackURL = try await presentAuthSession(url: authURL)

        // Extract authorization code and state
        let authResult = try oauthClient.extractAuthorizationCode(from: callbackURL)

        // Exchange code for tokens
        let tokens = try await oauthClient.exchangeCodeForTokens(authResult)

        // Fetch user profile
        let profile = try await oauthClient.getUserProfile(accessToken: tokens.accessToken)

        // Check for existing account and tokens
        let existingAccount = try await accountRepository.fetch(byEmail: profile.email, context: context)
        let hasExistingTokens = await tokenManager.hasTokens(for: profile.email)

        // Handle existing account with existing tokens (already signed in)
        if existingAccount != nil && hasExistingTokens {
            Logger.auth.warning("Account already signed in: \(profile.email, privacy: .private(mask: .hash))")
            throw AuthenticationError.accountAlreadyExists(profile.email)
        }

        // Handle existing account without tokens (re-authentication)
        if let existingAccount = existingAccount {
            Logger.auth.info("Updating existing account: \(profile.email, privacy: .private(mask: .hash))")
            existingAccount.displayName = profile.name
            existingAccount.profileImageURL = profile.picture
            existingAccount.isEnabled = true
            try await accountRepository.save(existingAccount, context: context)
            try await tokenManager.saveTokens(tokens, for: profile.email)
            return existingAccount
        }

        // Create new account
        let account = Account(email: profile.email, displayName: profile.name)
        account.profileImageURL = profile.picture

        // Save account to database
        try await accountRepository.save(account, context: context)

        // Save tokens to Keychain
        try await tokenManager.saveTokens(tokens, for: profile.email)

        Logger.auth.info("Successfully signed in: \(profile.email, privacy: .private(mask: .hash))")
        return account
    }

    /// Signs out an account.
    /// - Parameters:
    ///   - account: The account to sign out
    ///   - context: The SwiftData model context for database operations
    func signOut(_ account: Account, context: ModelContext) async throws {
        Logger.auth.info("Signing out account: \(account.email, privacy: .private(mask: .hash))")

        // Try to revoke tokens (fire and forget - don't fail if this fails)
        do {
            let tokens = try await tokenManager.getTokens(for: account.email)
            try await oauthClient.revokeToken(tokens.refreshToken)
        } catch {
            Logger.auth.warning("Failed to revoke tokens: \(error.localizedDescription)")
            // Continue with sign-out even if revocation fails
        }

        // Delete tokens from Keychain
        try await tokenManager.deleteTokens(for: account.email)

        // Delete account from database
        try await accountRepository.delete(account, context: context)

        Logger.auth.info("Successfully signed out: \(account.email, privacy: .private(mask: .hash))")
    }

    /// Gets a valid access token for an account, refreshing if necessary.
    /// - Parameter account: The account to get a token for
    /// - Returns: A valid access token
    func getAccessToken(for account: Account) async throws -> String {
        try await tokenManager.getValidAccessToken(for: account.email)
    }

    /// Fetches all authenticated accounts from the database.
    /// - Parameter context: The SwiftData model context
    /// - Returns: Array of accounts with valid tokens
    func loadAuthenticatedAccounts(context: ModelContext) async throws -> [Account] {
        let allAccounts = try await accountRepository.fetchAll(context: context)

        // Filter to only accounts with valid tokens
        var authenticatedAccounts: [Account] = []
        for account in allAccounts {
            if await tokenManager.hasTokens(for: account.email) {
                authenticatedAccounts.append(account)
            } else {
                Logger.auth.debug("Account without tokens: \(account.email, privacy: .private(mask: .hash))")
            }
        }

        return authenticatedAccounts
    }

    // MARK: - Private Methods

    /// Presents the authentication session and waits for the callback.
    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfiguration.oauthCallbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        Logger.auth.info("User cancelled authentication")
                        continuation.resume(throwing: AuthenticationError.userCancelled)
                    } else {
                        Logger.auth.error("Authentication session error: \(error.localizedDescription)")
                        continuation.resume(throwing: AuthenticationError.networkError(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    Logger.auth.error("No callback URL received")
                    continuation.resume(throwing: AuthenticationError.invalidCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                Logger.auth.error("Failed to start authentication session")
                continuation.resume(throwing: AuthenticationError.invalidResponse)
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthenticationService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the stored anchor or the key window
        // Must handle both main thread and background thread calls
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                presentationAnchor ?? NSApplication.shared.keyWindow ?? NSWindow()
            }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    self.presentationAnchor ?? NSApplication.shared.keyWindow ?? NSWindow()
                }
            }
        }
    }
}
