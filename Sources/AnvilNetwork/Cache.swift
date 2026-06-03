import Foundation

/// Configuration for response caching.
public struct CacheConfiguration: Sendable {
    public let strategy: CacheStrategy
    public let defaultTTL: TimeInterval
    
    public init(strategy: CacheStrategy = .none, defaultTTL: TimeInterval = 300) {
        self.strategy = strategy
        self.defaultTTL = defaultTTL
    }
    
    public static let `default` = CacheConfiguration()
}

/// The caching strategy.
public enum CacheStrategy: Sendable {
    case none
    case memory(maxSize: Int)
}

/// A cached response entry.
struct CacheEntry: Sendable {
    let response: HTTPResponse
    let cachedAt: Date
    let etag: String?
    let ttl: TimeInterval
    
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }
}

/// An in-memory cache for HTTP responses.
actor HTTPResponseCache {
    private var storage: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxSize: Int
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    func get(for request: HTTPRequest) -> CacheEntry? {
        let key = cacheKey(for: request)
        guard let entry = storage[key], !entry.isExpired else {
            if storage[key] != nil {
                remove(key: key)
            }
            return nil
        }
        // Update access order for LRU
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        return entry
    }
    
    func set(_ response: HTTPResponse, for request: HTTPRequest, etag: String? = nil, ttl: TimeInterval? = nil) {
        let key = cacheKey(for: request)
        let entry = CacheEntry(
            response: response,
            cachedAt: Date(),
            etag: etag,
            ttl: ttl ?? 300
        )
        
        if storage[key] == nil && storage.count >= maxSize {
            evictLRU()
        }
        
        storage[key] = entry
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    func remove(key: String) {
        storage.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }
    
    private func evictLRU() {
        guard let oldest = accessOrder.first else { return }
        remove(key: oldest)
    }
    
    private func cacheKey(for request: HTTPRequest) -> String {
        // Include auth scope in key if present
        let authHash = request.headers["Authorization"]?.hashValue ?? 0
        return "\(request.method.rawValue)|\(request.url.absoluteString)|\(authHash)"
    }
}
