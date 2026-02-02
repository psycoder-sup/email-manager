import Foundation
import os.log

/// Manages the policy for loading external images in emails.
/// Provides a whitelist of trusted domains and user preferences.
@Observable
@MainActor
final class ExternalImagePolicy {

    // MARK: - Singleton

    static let shared = ExternalImagePolicy()

    // MARK: - Configuration

    /// Default trusted domains (major email providers, common CDNs)
    private static let defaultTrustedDomains: Set<String> = [
        // Email providers
        "gmail.com",
        "googleusercontent.com",
        "gstatic.com",
        "outlook.com",
        "office365.com",
        "microsoft.com",
        "icloud.com",
        "apple.com",
        "yahoo.com",

        // Common CDNs
        "cloudflare.com",
        "cloudfront.net",
        "amazonaws.com",
        "fastly.net",
        "akamai.net",
        "akamaized.net",

        // Social media
        "facebook.com",
        "twitter.com",
        "linkedin.com",

        // Common email services
        "mailchimp.com",
        "sendgrid.net",
        "mailgun.org",
        "constantcontact.com",
        "campaign-archive.com"
    ]

    // MARK: - State

    /// User-added trusted domains
    private(set) var userTrustedDomains: Set<String> = []

    /// Domains that should never be trusted
    private(set) var blockedDomains: Set<String> = []

    /// Global setting to always load images
    var alwaysLoadImages: Bool = false {
        didSet {
            savePreferences()
        }
    }

    /// Per-sender settings
    private var senderSettings: [String: Bool] = [:]

    // MARK: - Persistence Keys

    private let userTrustedDomainsKey = "ExternalImagePolicy.userTrustedDomains"
    private let blockedDomainsKey = "ExternalImagePolicy.blockedDomains"
    private let alwaysLoadImagesKey = "ExternalImagePolicy.alwaysLoadImages"
    private let senderSettingsKey = "ExternalImagePolicy.senderSettings"

    // MARK: - Initialization

    private init() {
        loadPreferences()
    }

    // MARK: - Public Methods

    /// Checks if images from a given URL should be loaded.
    /// - Parameter url: The image URL to check
    /// - Returns: True if the image should be loaded
    func shouldLoadImage(from url: URL) -> Bool {
        if alwaysLoadImages {
            return true
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        // Check blocked domains first
        if isBlocked(domain: host) {
            return false
        }

        // Check trusted domains
        return isTrusted(domain: host)
    }

    /// Checks if images from a given sender should be loaded.
    /// - Parameter sender: The sender email address
    /// - Returns: True if images should be loaded, nil if no preference set
    func shouldLoadImagesFromSender(_ sender: String) -> Bool? {
        senderSettings[sender.lowercased()]
    }

    /// Checks if a domain is trusted.
    /// - Parameter domain: The domain to check
    /// - Returns: True if the domain is trusted
    func isTrusted(domain: String) -> Bool {
        let lowercased = domain.lowercased()

        // Check exact matches first
        if Self.defaultTrustedDomains.contains(lowercased) ||
           userTrustedDomains.contains(lowercased) {
            return true
        }

        // Check if it's a subdomain of a trusted domain
        for trusted in Self.defaultTrustedDomains.union(userTrustedDomains) {
            if lowercased.hasSuffix(".\(trusted)") {
                return true
            }
        }

        return false
    }

    /// Checks if a domain is blocked.
    /// - Parameter domain: The domain to check
    /// - Returns: True if the domain is blocked
    func isBlocked(domain: String) -> Bool {
        let lowercased = domain.lowercased()

        if blockedDomains.contains(lowercased) {
            return true
        }

        // Check if it's a subdomain of a blocked domain
        for blocked in blockedDomains {
            if lowercased.hasSuffix(".\(blocked)") {
                return true
            }
        }

        return false
    }

    /// Adds a domain to the trusted list.
    /// - Parameter domain: The domain to trust
    func trustDomain(_ domain: String) {
        userTrustedDomains.insert(domain.lowercased())
        blockedDomains.remove(domain.lowercased())
        savePreferences()
        Logger.ui.info("Trusted domain: \(domain)")
    }

    /// Adds a domain to the blocked list.
    /// - Parameter domain: The domain to block
    func blockDomain(_ domain: String) {
        blockedDomains.insert(domain.lowercased())
        userTrustedDomains.remove(domain.lowercased())
        savePreferences()
        Logger.ui.info("Blocked domain: \(domain)")
    }

    /// Removes a domain from custom settings.
    /// - Parameter domain: The domain to reset
    func resetDomain(_ domain: String) {
        userTrustedDomains.remove(domain.lowercased())
        blockedDomains.remove(domain.lowercased())
        savePreferences()
    }

    /// Sets the image loading preference for a sender.
    /// - Parameters:
    ///   - sender: The sender email address
    ///   - allow: Whether to allow images from this sender
    func setSenderPreference(_ sender: String, allow: Bool) {
        senderSettings[sender.lowercased()] = allow
        savePreferences()
    }

    /// Removes the image loading preference for a sender.
    /// - Parameter sender: The sender email address
    func resetSenderPreference(_ sender: String) {
        senderSettings.removeValue(forKey: sender.lowercased())
        savePreferences()
    }

    // MARK: - Persistence

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        if let domains = defaults.array(forKey: userTrustedDomainsKey) as? [String] {
            userTrustedDomains = Set(domains)
        }

        if let domains = defaults.array(forKey: blockedDomainsKey) as? [String] {
            blockedDomains = Set(domains)
        }

        alwaysLoadImages = defaults.bool(forKey: alwaysLoadImagesKey)

        if let settings = defaults.dictionary(forKey: senderSettingsKey) as? [String: Bool] {
            senderSettings = settings
        }
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard

        defaults.set(Array(userTrustedDomains), forKey: userTrustedDomainsKey)
        defaults.set(Array(blockedDomains), forKey: blockedDomainsKey)
        defaults.set(alwaysLoadImages, forKey: alwaysLoadImagesKey)
        defaults.set(senderSettings, forKey: senderSettingsKey)
    }
}
