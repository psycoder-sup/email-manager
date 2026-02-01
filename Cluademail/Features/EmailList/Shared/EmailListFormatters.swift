import Foundation

/// Shared formatters and utilities for email list views.
enum EmailListFormatters {

    /// Cached relative date formatter for performance.
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Formats a date as a relative string (e.g., "2h ago").
    static func relativeDate(from date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Extracts username from email address.
    static func username(from email: String) -> String {
        email.components(separatedBy: "@").first ?? email
    }

    /// Provides fallback for empty subjects.
    static func displaySubject(_ subject: String) -> String {
        subject.isEmpty ? "(No Subject)" : subject
    }
}
