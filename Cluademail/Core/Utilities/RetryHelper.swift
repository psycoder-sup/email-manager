import Foundation
import os.log

/// Decisions for retry behavior.
enum RetryDecision: Sendable {
    /// Retry after a delay
    case retry(after: TimeInterval)
    /// Retry immediately after refreshing authentication
    case retryWithRefresh
    /// Do not retry, propagate error
    case doNotRetry
}

/// Helper for retry logic with exponential backoff.
enum RetryHelper {

    /// Default base delay for exponential backoff (1 second)
    static let defaultBaseDelay: TimeInterval = 1.0

    /// Maximum delay cap (60 seconds)
    static let maxDelay: TimeInterval = 60.0

    /// Jitter factor for randomization (±10%)
    static let jitterFactor: Double = 0.1

    /// Determines if an error should be retried based on error type and attempt count.
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - attempt: Current attempt number (0-based)
    ///   - maxAttempts: Maximum number of retry attempts
    /// - Returns: Retry decision
    static func shouldRetry(_ error: Error, attempt: Int, maxAttempts: Int) -> RetryDecision {
        guard attempt < maxAttempts - 1 else {
            return .doNotRetry
        }

        if let apiError = error as? APIError {
            return shouldRetryAPIError(apiError, attempt: attempt)
        }

        // Network errors are generally retryable
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let retryableCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet
            ]
            if retryableCodes.contains(nsError.code) {
                let delay = calculateDelay(attempt: attempt)
                return .retry(after: delay)
            }
        }

        return .doNotRetry
    }

    /// Determines retry decision for API errors.
    private static func shouldRetryAPIError(_ error: APIError, attempt: Int) -> RetryDecision {
        switch error {
        case .unauthorized:
            // Retry once after token refresh
            return attempt == 0 ? .retryWithRefresh : .doNotRetry

        case .rateLimited(let retryAfter):
            // Use Retry-After header if available, otherwise calculate
            let delay = retryAfter ?? calculateDelay(attempt: attempt)
            return .retry(after: delay)

        case .serverError(let statusCode):
            // Retry 5xx errors except 501 (Not Implemented)
            if statusCode != 501 {
                let delay = calculateDelay(attempt: attempt)
                return .retry(after: delay)
            }
            return .doNotRetry

        case .networkError:
            let delay = calculateDelay(attempt: attempt)
            return .retry(after: delay)

        case .notFound, .invalidResponse, .decodingError:
            // Permanent failures
            return .doNotRetry
        }
    }

    /// Calculates exponential backoff delay with jitter.
    /// - Parameters:
    ///   - attempt: Current attempt number (0-based)
    ///   - baseDelay: Base delay in seconds
    /// - Returns: Delay in seconds
    static func calculateDelay(
        attempt: Int,
        baseDelay: TimeInterval = defaultBaseDelay
    ) -> TimeInterval {
        // Calculate exponential delay: base * 2^attempt
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))

        // Cap at maximum delay
        let cappedDelay = min(exponentialDelay, maxDelay)

        // Add jitter (±10%)
        let jitter = cappedDelay * jitterFactor * Double.random(in: -1...1)

        return max(0, cappedDelay + jitter)
    }

    /// Executes an async operation with retry logic.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    static func executeWithRetry<T>(
        maxAttempts: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                let decision = shouldRetry(error, attempt: attempt, maxAttempts: maxAttempts)

                switch decision {
                case .retry(let delay):
                    Logger.api.debug("Retry attempt \(attempt + 1)/\(maxAttempts) after \(String(format: "%.2f", delay))s delay")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                case .retryWithRefresh:
                    Logger.api.debug("Retry with token refresh, attempt \(attempt + 1)/\(maxAttempts)")
                    // Caller should handle token refresh before retry
                    continue

                case .doNotRetry:
                    throw error
                }
            }
        }

        throw lastError ?? APIError.networkError(nil)
    }
}
