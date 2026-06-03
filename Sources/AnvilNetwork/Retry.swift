import Foundation

/// Configuration for request retry behavior.
public struct RetryConfiguration: Sendable {
    public let maxAttempts: Int
    public let backoff: BackoffStrategy
    public let retryableStatusCodes: Set<Int>
    public let retryableMethods: Set<HTTPMethod>
    
    public init(
        maxAttempts: Int = 3,
        backoff: BackoffStrategy = .exponential(base: 1.0, maxDelay: 60.0),
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableMethods: Set<HTTPMethod> = [.get, .head, .put, .delete]
    ) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
    }
    
    public static let `default` = RetryConfiguration()
}

/// A backoff strategy for retry delays.
public enum BackoffStrategy: Sendable {
    case exponential(base: TimeInterval, maxDelay: TimeInterval)
    case linear(delay: TimeInterval)
    case fixed(delay: TimeInterval)
    
    func delay(forAttempt attempt: Int) -> TimeInterval {
        switch self {
        case .exponential(let base, let maxDelay):
            let delay = base * pow(2.0, Double(attempt))
            let jittered = delay * Double.random(in: 0.5...1.0)
            return min(jittered, maxDelay)
        case .linear(let delay):
            return delay * Double(attempt)
        case .fixed(let delay):
            return delay
        }
    }
}
