import Foundation

/// Configuration for an `HTTPClient`.
public struct HTTPClientConfiguration: Sendable {
    public let baseURL: URL?
    public let timeout: TimeoutConfiguration
    public let cache: CacheConfiguration
    public let retry: RetryConfiguration
    public let decoder: JSONDecoder
    public let encoder: JSONEncoder
    
    public init(
        baseURL: URL? = nil,
        timeout: TimeoutConfiguration = .default,
        cache: CacheConfiguration = .default,
        retry: RetryConfiguration = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.cache = cache
        self.retry = retry
        self.decoder = decoder
        self.encoder = encoder
    }
    
    public static let `default` = HTTPClientConfiguration()
}

/// Timeout configuration.
public struct TimeoutConfiguration: Sendable {
    public let request: TimeInterval
    public let resource: TimeInterval
    
    public init(request: TimeInterval = 60, resource: TimeInterval = 604800) {
        self.request = request
        self.resource = resource
    }
    
    public static let `default` = TimeoutConfiguration()
}
