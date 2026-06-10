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
struct CacheEntry {
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
    let maxSize: Int
    let defaultTTL: TimeInterval

    init(maxSize: Int, defaultTTL: TimeInterval = 300) {
        self.maxSize = maxSize
        self.defaultTTL = defaultTTL
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
            ttl: ttl ?? defaultTTL
        )

        if storage[key] == nil, storage.count >= maxSize {
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
        // Use literal auth header for stable cache key
        let authScope = request.headers["Authorization"] ?? ""
        return "\(request.method.rawValue)|\(request.url.absoluteString)|\(authScope)"
    }
}
