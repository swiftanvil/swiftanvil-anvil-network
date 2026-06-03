import Foundation

/// A type-safe, concurrent HTTP client.
public struct HTTPClient: Sendable {
    private let core: HTTPClientCore
    
    public init(configuration: HTTPClientConfiguration = .default) {
        self.core = HTTPClientCore(configuration: configuration)
    }
    
    public init(
        baseURL: URL? = nil,
        timeout: TimeoutConfiguration = .default,
        cache: CacheConfiguration = .default,
        retry: RetryConfiguration = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.init(configuration: HTTPClientConfiguration(
            baseURL: baseURL,
            timeout: timeout,
            cache: cache,
            retry: retry,
            decoder: decoder,
            encoder: encoder
        ))
    }
    
    // MARK: - Request Building
    
    public func request(_ method: HTTPMethod, _ path: String) -> HTTPRequestBuilder {
        HTTPRequestBuilder(client: core, method: method, path: path, baseURL: core.configuration.baseURL)
    }
    
    public func get(_ path: String) -> HTTPRequestBuilder {
        request(.get, path)
    }
    
    public func post(_ path: String) -> HTTPRequestBuilder {
        request(.post, path)
    }
    
    public func put(_ path: String) -> HTTPRequestBuilder {
        request(.put, path)
    }
    
    public func patch(_ path: String) -> HTTPRequestBuilder {
        request(.patch, path)
    }
    
    public func delete(_ path: String) -> HTTPRequestBuilder {
        request(.delete, path)
    }
    
    // MARK: - Interceptors
    
    public func addingRequestInterceptor(_ interceptor: RequestInterceptor) -> HTTPClient {
        var client = self
        Task {
            await client.core.addRequestInterceptor(interceptor)
        }
        return client
    }
    
    public func addingResponseInterceptor(_ interceptor: ResponseInterceptor) -> HTTPClient {
        var client = self
        Task {
            await client.core.addResponseInterceptor(interceptor)
        }
        return client
    }
}

// MARK: - Request Builder

public struct HTTPRequestBuilder: Sendable {
    private let client: HTTPClientCore
    private var request: HTTPRequest
    private let baseURL: URL?
    
    init(client: HTTPClientCore, method: HTTPMethod, path: String, baseURL: URL?) {
        self.client = client
        self.baseURL = baseURL
        self.request = HTTPRequest(method: method, url: Self.resolveURL(path: path, baseURL: baseURL))
    }
    
    private static func resolveURL(path: String, baseURL: URL?) -> URL {
        if let baseURL = baseURL {
            return baseURL.appendingPathComponent(path)
        }
        return URL(string: path)!
    }
    
    public func header(_ name: String, _ value: String) -> HTTPRequestBuilder {
        var builder = self
        builder.request.headers.set(name, value: value)
        return builder
    }
    
    public func body<T: Encodable & Sendable>(_ value: T, encoder: JSONEncoder? = nil) -> HTTPRequestBuilder {
        var builder = self
        let encoder = encoder ?? JSONEncoder()
        if let data = try? encoder.encode(value) {
            builder.request.body = .json(data)
        }
        return builder
    }
    
    public func body(_ data: Data) -> HTTPRequestBuilder {
        var builder = self
        builder.request.body = .data(data)
        return builder
    }
    
    public func send() async throws -> HTTPResponse {
        try await client.send(request)
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
    
    init(configuration: HTTPClientConfiguration, transport: HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
        
        if case .memory(let maxSize) = configuration.cache.strategy {
            self.cache = HTTPResponseCache(maxSize: maxSize)
        }
    }
    
    func resolveURL(path: String) -> URL {
        if let baseURL = configuration.baseURL {
            return baseURL.appendingPathComponent(path)
        }
        return URL(string: path)!
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
        
        // Check cache
        if let cache = cache, request.method == .get {
            if let entry = await cache.get(for: request) {
                return entry.response
            }
        }
        
        // Apply request interceptors
        var currentRequest = request
        for interceptor in requestInterceptors {
            currentRequest = try await interceptor.intercept(currentRequest)
        }
        
        // Send with retry
        let response = try await sendWithRetry(currentRequest)
        
        // Apply response interceptors
        var currentResponse = response
        for interceptor in responseInterceptors {
            currentResponse = try await interceptor.intercept(currentResponse, for: currentRequest)
        }
        
        // Cache successful GET responses
        if let cache = cache, request.method == .get, (200...299).contains(response.statusCode) {
            let etag = response.headers["ETag"]
            await cache.set(response, for: request, etag: etag)
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
                let delay = configuration.retry.backoff.delay(forAttempt: attempt)
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
                return try await sendWithRetry(request, attempt: attempt + 1)
            }
            
            // Validate response
            guard (200...299).contains(response.statusCode) else {
                throw NetworkError.invalidResponse(statusCode: response.statusCode, body: response.body)
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
}
