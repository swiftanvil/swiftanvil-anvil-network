import Foundation

/// A type-safe, concurrent HTTP client.
public struct HTTPClient: Sendable {
    private let core: HTTPClientCore
    
    public init(configuration: HTTPClientConfiguration = .default, transport: HTTPTransport? = nil) {
        self.core = HTTPClientCore(configuration: configuration, transport: transport)
    }
    
    public init(
        baseURL: URL? = nil,
        timeout: TimeoutConfiguration = .default,
        cache: CacheConfiguration = .default,
        retry: RetryConfiguration = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        transport: HTTPTransport? = nil
    ) {
        self.init(
            configuration: HTTPClientConfiguration(
                baseURL: baseURL,
                timeout: timeout,
                cache: cache,
                retry: retry,
                decoder: decoder,
                encoder: encoder
            ),
            transport: transport
        )
    }
    
    // MARK: - Request Building
    
    public func request(_ method: HTTPMethod, _ path: String) -> HTTPRequestBuilder {
        HTTPRequestBuilder(client: core, method: method, path: path, baseURL: core.configuration.baseURL)
    }
    
    public func get(_ path: String) -> HTTPRequestBuilder { request(.get, path) }
    public func post(_ path: String) -> HTTPRequestBuilder { request(.post, path) }
    public func put(_ path: String) -> HTTPRequestBuilder { request(.put, path) }
    public func patch(_ path: String) -> HTTPRequestBuilder { request(.patch, path) }
    public func delete(_ path: String) -> HTTPRequestBuilder { request(.delete, path) }
    
    // MARK: - Interceptors (async — safe)
    
    public func addingRequestInterceptor(_ interceptor: RequestInterceptor) async -> HTTPClient {
        let client = self
        await client.core.addRequestInterceptor(interceptor)
        return client
    }
    
    public func addingResponseInterceptor(_ interceptor: ResponseInterceptor) async -> HTTPClient {
        let client = self
        await client.core.addResponseInterceptor(interceptor)
        return client
    }
    
    // MARK: - Direct Send
    
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await core.send(request)
    }
}

// MARK: - Request Builder

public struct HTTPRequestBuilder: Sendable {
    private let client: HTTPClientCore
    private var request: HTTPRequest
    private let baseURL: URL?
    private var queryItems: [URLQueryItem] = []
    
    init(client: HTTPClientCore, method: HTTPMethod, path: String, baseURL: URL?) {
        self.client = client
        self.baseURL = baseURL
        self.request = HTTPRequest(method: method, url: Self.resolveURL(path: path, baseURL: baseURL))
    }
    
    private static func resolveURL(path: String, baseURL: URL?) -> URL {
        if let baseURL = baseURL {
            return baseURL.appendingPathComponent(path)
        }
        // For paths without baseURL, attempt to parse as full URL first
        if let url = URL(string: path) {
            return url
        }
        // Fallback: this will produce a URL with empty components but won't trap
        return URL(string: "about:invalid")!
    }
    
    public func header(_ name: String, _ value: String) -> HTTPRequestBuilder {
        var builder = self
        builder.request.headers.set(name, value: value)
        return builder
    }
    
    public func query(_ name: String, _ value: String) -> HTTPRequestBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: name, value: value))
        return builder
    }
    
    public func queries(_ items: [URLQueryItem]) -> HTTPRequestBuilder {
        var builder = self
        builder.queryItems.append(contentsOf: items)
        return builder
    }
    
    public func body<T: Encodable & Sendable>(_ value: T, encoder: JSONEncoder? = nil) throws -> HTTPRequestBuilder {
        var builder = self
        let encoder = encoder ?? JSONEncoder()
        let data = try encoder.encode(value)
        builder.request.body = .json(data)
        return builder
    }
    
    public func body(_ data: Data) -> HTTPRequestBuilder {
        var builder = self
        builder.request.body = .data(data)
        return builder
    }
    
    public func send() async throws -> HTTPResponse {
        var request = self.request
        // Apply query items to URL
        if !queryItems.isEmpty {
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: true)
            var existing = components?.queryItems ?? []
            existing.append(contentsOf: queryItems)
            components?.queryItems = existing
            if let newURL = components?.url {
                request.url = newURL
            }
        }
        return try await client.send(request)
    }
    
    public func decode<T: Decodable>(as type: T.Type = T.self) async throws -> T {
        let response = try await send()
        return try response.decode(as: type, using: client.configuration.decoder)
    }
}

// MARK: - Core Actor

actor HTTPClientCore {
    let configuration: HTTPClientConfiguration
    private let transport: HTTPTransport
    private var requestInterceptors: [RequestInterceptor] = []
    private var responseInterceptors: [ResponseInterceptor] = []
    private var cache: HTTPResponseCache?
    
    init(configuration: HTTPClientConfiguration, transport: HTTPTransport? = nil) {
        self.configuration = configuration
        self.transport = transport ?? URLSessionTransport()
        
        if case .memory(let maxSize) = configuration.cache.strategy {
            self.cache = HTTPResponseCache(maxSize: maxSize, defaultTTL: configuration.cache.defaultTTL)
        }
    }
    
    func addRequestInterceptor(_ interceptor: RequestInterceptor) {
        requestInterceptors.append(interceptor)
    }
    
    func addResponseInterceptor(_ interceptor: ResponseInterceptor) {
        responseInterceptors.append(interceptor)
    }
    
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        // Check cancellation
        try Task.checkCancellation()
        
        // Apply request interceptors
        var currentRequest = request
        for interceptor in requestInterceptors {
            currentRequest = try await interceptor.intercept(currentRequest)
        }
        
        // Check cache AFTER interceptors (so auth is included in cache key)
        if let cache = cache, currentRequest.method == .get {
            if let entry = await cache.get(for: currentRequest) {
                return entry.response
            }
        }
        
        // Send with retry
        let response = try await sendWithRetry(currentRequest)
        
        // Apply response interceptors
        var currentResponse = response
        for interceptor in responseInterceptors {
            currentResponse = try await interceptor.intercept(currentResponse, for: currentRequest)
        }
        
        // Cache successful GET responses
        if let cache = cache, currentRequest.method == .get, (200...299).contains(response.statusCode) {
            let etag = response.headers["ETag"]
            await cache.set(response, for: currentRequest, etag: etag)
        }
        
        return currentResponse
    }
    
    private func sendWithRetry(_ request: HTTPRequest, attempt: Int = 1) async throws -> HTTPResponse {
        do {
            let response = try await transport.send(request)
            
            // Check if retryable
            if configuration.retry.retryableStatusCodes.contains(response.statusCode),
               configuration.retry.retryableMethods.contains(request.method),
               attempt < configuration.retry.maxAttempts {
                
                let delay = retryDelay(for: response, attempt: attempt)
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
                return try await sendWithRetry(request, attempt: attempt + 1)
            }
            
            // Validate response
            guard (200...299).contains(response.statusCode) else {
                let error = NetworkError.invalidResponse(statusCode: response.statusCode, body: response.body)
                if attempt >= configuration.retry.maxAttempts {
                    throw NetworkError.retryExhausted(underlying: error, attempts: attempt)
                }
                throw error
            }
            
            return response
        } catch let error as NetworkError {
            if case .cancelled = error { throw error }
            if case .transport = error, attempt < configuration.retry.maxAttempts {
                let delay = configuration.retry.backoff.delay(forAttempt: attempt)
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
                return try await sendWithRetry(request, attempt: attempt + 1)
            }
            if attempt >= configuration.retry.maxAttempts {
                throw NetworkError.retryExhausted(underlying: error, attempts: attempt)
            }
            throw error
        }
    }
    
    private func retryDelay(for response: HTTPResponse, attempt: Int) -> TimeInterval {
        // Respect Retry-After header if present
        if let retryAfter = response.headers["Retry-After"],
           let seconds = TimeInterval(retryAfter) {
            return seconds
        }
        return configuration.retry.backoff.delay(forAttempt: attempt)
    }
}
