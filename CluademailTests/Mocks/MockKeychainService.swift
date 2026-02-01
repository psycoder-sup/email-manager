import Foundation
@testable import Cluademail

/// Mock implementation of KeychainServiceProtocol for testing.
final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {

    // MARK: - State

    /// In-memory storage for items
    private var storage: [String: Data] = [:]

    /// Errors to throw for specific keys
    private var errorsToThrow: [String: KeychainError] = [:]

    /// Lock for thread-safe access.
    /// Retained for safety during concurrent async test operations.
    private let lock = NSLock()

    /// Tracking for method calls
    private(set) var saveCallCount: Int = 0
    private(set) var retrieveCallCount: Int = 0
    private(set) var deleteCallCount: Int = 0

    // MARK: - Configuration

    /// Configure an error to be thrown for a specific key.
    func setError(_ error: KeychainError, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        errorsToThrow[key] = error
    }

    /// Clear all configuration and storage.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        errorsToThrow.removeAll()
        saveCallCount = 0
        retrieveCallCount = 0
        deleteCallCount = 0
    }

    // MARK: - KeychainServiceProtocol

    func save<T: Codable>(_ item: T, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        saveCallCount += 1

        if let error = errorsToThrow[key] {
            throw error
        }

        let data = try JSONEncoder().encode(item)
        storage[key] = data
    }

    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        retrieveCallCount += 1

        if let error = errorsToThrow[key] {
            throw error
        }

        guard let data = storage[key] else {
            throw KeychainError.itemNotFound
        }

        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        deleteCallCount += 1

        if let error = errorsToThrow[key] {
            throw error
        }

        storage.removeValue(forKey: key)
    }
}
