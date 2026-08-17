import Foundation

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: Double
    public let maxDelay: Double

    public init(maxAttempts: Int = 4, baseDelay: Double = 0.5, maxDelay: Double = 8.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int, jitter: Double) -> Double {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        return min(exponential, maxDelay) * (1.0 + jitter)
    }

    public func shouldRetry(attempt: Int, error: OmniRouteError) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error {
        case .rateLimited, .network, .invalidResponse:
            return true
        case .authenticationFailed, .streamInterrupted, .unknown:
            return false
        }
    }
}
