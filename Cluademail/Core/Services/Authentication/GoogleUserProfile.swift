import Foundation

/// User profile information returned from Google's userinfo endpoint.
/// Used to populate Account model after successful authentication.
struct GoogleUserProfile: Codable, Sendable, Equatable {

    /// The user's email address
    let email: String

    /// The user's display name
    let name: String

    /// URL to the user's profile picture (optional)
    let picture: String?
}
