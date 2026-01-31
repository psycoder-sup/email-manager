import Foundation
@testable import Cluademail

/// Factory methods for creating test data.
/// Use these to create consistent test fixtures across tests.
enum TestFixtures {

    // MARK: - Account Fixtures

    /// Creates a test Account with optional customization.
    /// - Parameters:
    ///   - id: Account ID (default: new UUID)
    ///   - email: Email address (default: "test@gmail.com")
    ///   - displayName: Display name (default: "Test User")
    /// - Returns: A configured Account
    static func makeAccount(
        id: UUID = UUID(),
        email: String = "test@gmail.com",
        displayName: String = "Test User"
    ) -> Account {
        Account(
            id: id,
            email: email,
            displayName: displayName
        )
    }

    /// Creates multiple test accounts.
    /// - Parameter count: Number of accounts to create
    /// - Returns: Array of accounts with sequential email addresses
    static func makeAccounts(count: Int) -> [Account] {
        (0..<count).map { index in
            makeAccount(
                email: "user\(index)@gmail.com",
                displayName: "User \(index)"
            )
        }
    }

    // MARK: - Email Fixtures

    /// Creates a test Email with optional customization.
    /// - Parameters:
    ///   - id: Gmail message ID (default: generated)
    ///   - subject: Email subject (default: "Test Subject")
    ///   - snippet: Email snippet (default: "Test email content...")
    /// - Returns: A configured Email
    static func makeEmail(
        id: String = UUID().uuidString,
        subject: String = "Test Subject",
        snippet: String = "Test email content..."
    ) -> Email {
        Email(
            id: id,
            subject: subject,
            snippet: snippet
        )
    }

    /// Creates multiple test emails.
    /// - Parameter count: Number of emails to create
    /// - Returns: Array of emails with sequential subjects
    static func makeEmails(count: Int) -> [Email] {
        (0..<count).map { index in
            makeEmail(
                subject: "Email \(index)",
                snippet: "This is email number \(index)"
            )
        }
    }

    // MARK: - Error Fixtures

    /// Sample auth errors for testing
    static let sampleAuthErrors: [AuthError] = [
        .userCancelled,
        .invalidCredentials,
        .tokenExpired,
        .tokenRefreshFailed(nil),
        .keychainError(nil),
        .networkError(nil)
    ]

    /// Sample sync errors for testing
    static let sampleSyncErrors: [SyncError] = [
        .networkUnavailable,
        .historyExpired,
        .quotaExceeded,
        .syncInProgress,
        .partialFailure(successCount: 5, failureCount: 2),
        .databaseError(nil)
    ]

    /// Sample API errors for testing
    static let sampleAPIErrors: [APIError] = [
        .unauthorized,
        .notFound,
        .rateLimited(retryAfter: 30),
        .invalidResponse,
        .serverError(statusCode: 500),
        .networkError(nil),
        .decodingError(nil)
    ]
}

// MARK: - Date Extensions for Testing

extension TestFixtures {

    /// Creates a date relative to now.
    /// - Parameter daysAgo: Number of days in the past
    /// - Returns: A Date
    static func dateAgo(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    /// Creates a date at a specific time today.
    /// - Parameters:
    ///   - hour: Hour (0-23)
    ///   - minute: Minute (0-59)
    /// - Returns: A Date
    static func today(at hour: Int, minute: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}
