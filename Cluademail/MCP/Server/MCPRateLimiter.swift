import Foundation

/// Actor for rate limiting MCP requests.
actor MCPRateLimiter {

    private var requestTimestamps: [Date] = []
    private let maxPerMinute: Int
    private let maxPerHour: Int

    init(maxPerMinute: Int = MCPConfiguration.maxRequestsPerMinute,
         maxPerHour: Int = MCPConfiguration.maxRequestsPerHour) {
        self.maxPerMinute = maxPerMinute
        self.maxPerHour = maxPerHour
    }

    /// Checks if the rate limit allows another request.
    /// - Throws: MCPError.rateLimitExceeded if limit is exceeded
    func checkLimit() throws {
        let now = Date()

        // Clean old timestamps (older than 1 hour)
        let oneHourAgo = now.addingTimeInterval(-3600)
        requestTimestamps.removeAll { $0 < oneHourAgo }

        // Check hour limit
        if requestTimestamps.count >= maxPerHour {
            guard let oldestInHour = requestTimestamps.first else {
                // Shouldn't happen, but handle gracefully
                throw MCPError.rateLimitExceeded(retryAfter: 60)
            }
            let waitTime = max(1, Int(3600 - now.timeIntervalSince(oldestInHour)))
            throw MCPError.rateLimitExceeded(retryAfter: waitTime)
        }

        // Check minute limit
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let timestampsInLastMinute = requestTimestamps.filter { $0 >= oneMinuteAgo }
        if timestampsInLastMinute.count >= maxPerMinute {
            guard let oldestInMinute = timestampsInLastMinute.min() else {
                throw MCPError.rateLimitExceeded(retryAfter: 60)
            }
            let waitTime = max(1, Int(60 - now.timeIntervalSince(oldestInMinute)))
            throw MCPError.rateLimitExceeded(retryAfter: waitTime)
        }

        // Record this request
        requestTimestamps.append(now)
    }

    /// Resets the rate limiter (for testing).
    func reset() {
        requestTimestamps.removeAll()
    }

    /// Returns current request counts (for debugging).
    func stats() -> (lastMinute: Int, lastHour: Int) {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)

        let lastMinute = requestTimestamps.filter { $0 >= oneMinuteAgo }.count
        let lastHour = requestTimestamps.filter { $0 >= oneHourAgo }.count

        return (lastMinute, lastHour)
    }
}
