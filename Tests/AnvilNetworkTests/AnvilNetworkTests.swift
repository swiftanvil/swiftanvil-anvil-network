import Foundation
import Testing
@testable import AnvilNetwork

// MARK: - HTTPMethod Tests

@Suite("HTTPMethod")
struct HTTPMethodTests {
    @Test("static constants have correct raw values")
    func constants() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
    
    @Test("rawValue is uppercased")
    func uppercased() {
        #expect(HTTPMethod(rawValue: "get").rawValue == "GET")
    }
}

// MARK: - HTTPHeaders Tests

@Suite("HTTPHeaders")
struct HTTPHeadersTests {
    @Test("set and get are case-insensitive")
    func caseInsensitive() {
        var headers = HTTPHeaders()
        headers.set("Content-Type", value: "application/json")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["CONTENT-TYPE"] == "application/json")
    }
    
    @Test("add appends values")
    func addAppends() {
        var headers = HTTPHeaders()
        headers.add("Accept", value: "application/json")
        headers.add("Accept", value: "text/plain")
        #expect(headers["accept"] == "application/json, text/plain")
    }
}

// MARK: - HTTPRequest Tests

@Suite("HTTPRequest")
struct HTTPRequestTests {
    @Test("init with baseURL and path")
    func initWithBaseURL() {
        let request = HTTPRequest(method: .get, baseURL: URL(string: "https://api.example.com")!, path: "users")
        #expect(request.url.absoluteString == "https://api.example.com/users")
        #expect(request.method == .get)
        #expect(request.body == .empty)
    }
    
    @Test("empty body by default")
    func emptyBodyDefault() {
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        #expect(request.body == .empty)
        #expect(request.body.encoded().isEmpty)
    }
}

// MARK: - HTTPBody Tests

@Suite("HTTPBody")
struct HTTPBodyTests {
    @Test("empty encodes to empty data")
    func emptyEncodes() {
        #expect(HTTPBody.empty.encoded().isEmpty)
    }
    
    @Test("data encodes to same data")
    func dataEncodes() {
        let data = Data("hello".utf8)
        #expect(HTTPBody.data(data).encoded() == data)
    }
    
    @Test("json encodes to same data")
    func jsonEncodes() {
        let data = Data("{}".utf8)
        #expect(HTTPBody.json(data).encoded() == data)
    }
}

// MARK: - HTTPResponse Tests

@Suite("HTTPResponse")
struct HTTPResponseTests {
    @Test("decode parses JSON body")
    func decodeJSON() throws {
        let json = Data("{\"name\":\"Ada\"}".utf8)
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        let response = HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: json)
        
        struct User: Decodable {
            let name: String
        }
        
        let user = try response.decode(as: User.self)
        #expect(user.name == "Ada")
    }
}

// MARK: - NetworkError Tests

@Suite("NetworkError")
struct NetworkErrorTests {
    @Test("is Sendable")
    func sendable() {
        let error: NetworkError = .cancelled
        let _ = error as Sendable
    }
    
    @Test("decoding error carries SendableError")
    func decodingError() {
        let data = Data()
        let error = NetworkError.decoding(SendableError(NSError(domain: "test", code: 1)), data)
        let _ = error as Sendable
    }
}

// MARK: - SendableError Tests

@Suite("SendableError")
struct SendableErrorTests {
    @Test("captures error description")
    func description() {
        let nsError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let sendable = SendableError(nsError)
        #expect(sendable.description.contains("boom"))
    }
    
    @Test("is Sendable")
    func sendable() {
        let sendable = SendableError(NSError(domain: "test", code: 1))
        let _ = sendable as Sendable
    }
}

// MARK: - Mock Transport

actor MockTransport: HTTPTransport {
    var responses: [HTTPResponse] = []
    var requests: [HTTPRequest] = []
    var error: NetworkError?
    var retryAfterHeader: String?
    
    func enqueue(_ response: HTTPResponse) {
        responses.append(response)
    }
    
    func enqueue(error: NetworkError) {
        self.error = error
    }
    
    func enqueueRetryable(statusCode: Int, retryAfter: String? = nil) {
        self.retryAfterHeader = retryAfter
        // Will be handled in send
    }
    
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if let error = error {
            self.error = nil
            throw error
        }
        let response = responses.removeFirst()
        if let retryAfter = retryAfterHeader {
            var headers = response.headers
            headers.set("Retry-After", value: retryAfter)
            retryAfterHeader = nil
            return HTTPResponse(
                request: response.request,
                statusCode: response.statusCode,
                headers: headers,
                body: response.body
            )
        }
        return response
    }
    
    func recordedRequests() -> [HTTPRequest] {
        requests
    }
}

// MARK: - HTTPClient Tests

@Suite("HTTPClient")
struct HTTPClientTests {
    
    @Test("GET request with mock transport returns decoded response")
    func getRequestWithMock() async throws {
        let mock = MockTransport()
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.example.com/users/1")!)
        let response = HTTPResponse(
            request: request,
            statusCode: 200,
            headers: HTTPHeaders(),
            body: Data("{\"name\":\"Ada\"}".utf8)
        )
        await mock.enqueue(response)
        
        let client = HTTPClient(transport: mock)
        let builder = client.get("https://api.example.com/users/1")
        let result = try await builder.decode(as: TestUser.self)
        
        #expect(result.name == "Ada")
        
        let recorded = await mock.recordedRequests()
        #expect(recorded.count == 1)
        #expect(recorded[0].method == .get)
    }
    
    @Test("HTTPClient is Sendable")
    func sendable() {
        let client = HTTPClient()
        let _ = client as Sendable
    }
    
    @Test("transport injection works")
    func transportInjection() async throws {
        let mock = MockTransport()
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        await mock.enqueue(HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data()))
        
        let client = HTTPClient(transport: mock)
        let _ = try await client.send(request)
        
        let recorded = await mock.recordedRequests()
        #expect(recorded.count == 1)
    }
    
    @Test("query parameters are applied to URL")
    func queryParameters() async throws {
        let mock = MockTransport()
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.example.com/search")!)
        await mock.enqueue(HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data()))
        
        let client = HTTPClient(transport: mock)
        let _ = try await client.get("https://api.example.com/search")
            .query("q", "swift")
            .query("limit", "10")
            .send()
        
        let recorded = await mock.recordedRequests()
        #expect(recorded.count == 1)
        let url = recorded[0].url.absoluteString
        #expect(url.contains("q=swift"))
        #expect(url.contains("limit=10"))
    }
    
    @Test("body encoding throws on failure")
    func bodyEncodingThrows() {
        struct Unencodable: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: [], debugDescription: "nope"))
            }
        }
        
        let client = HTTPClient()
        let builder = client.post("https://example.com")
        #expect(throws: Error.self) {
            try builder.body(Unencodable())
        }
    }
    
    @Test("request interceptor is applied")
    func requestInterceptor() async throws {
        let mock = MockTransport()
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.example.com")!)
        await mock.enqueue(HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data()))
        
        let client = HTTPClient(transport: mock)
        let intercepted = await client.addingRequestInterceptor(TestAuthInterceptor(token: "secret"))
        let _ = try await intercepted.get("https://api.example.com").send()
        
        let recorded = await mock.recordedRequests()
        #expect(recorded[0].headers["Authorization"] == "Bearer secret")
    }
    
    @Test("cache respects auth scope")
    func cacheAuthIsolation() async throws {
        let mock = MockTransport()
        let url = URL(string: "https://api.example.com/user")!
        let response = HTTPResponse(
            request: HTTPRequest(method: .get, url: url),
            statusCode: 200,
            headers: HTTPHeaders(),
            body: Data("{\"name\":\"User1\"}".utf8)
        )
        await mock.enqueue(response)
        
        let client = HTTPClient(
            cache: .init(strategy: .memory(maxSize: 1000)),
            transport: mock
        )
        
        let authed1 = await client.addingRequestInterceptor(TestAuthInterceptor(token: "token1"))
        let result1 = try await authed1.get("https://api.example.com/user").decode(as: TestUser.self)
        #expect(result1.name == "User1")
        
        // Same URL, different auth — should hit mock again (not cache)
        await mock.enqueue(HTTPResponse(
            request: HTTPRequest(method: .get, url: url),
            statusCode: 200,
            headers: HTTPHeaders(),
            body: Data("{\"name\":\"User2\"}".utf8)
        ))
        let authed2 = await client.addingRequestInterceptor(TestAuthInterceptor(token: "token2"))
        let result2 = try await authed2.get("https://api.example.com/user").decode(as: TestUser.self)
        #expect(result2.name == "User2")
    }
    
    @Test("retry respects Retry-After header")
    func retryAfterHeader() async throws {
        let mock = MockTransport()
        let url = URL(string: "https://api.example.com")!
        let request = HTTPRequest(method: .get, url: url)
        
        // First response: 429 with Retry-After: 0 (so test doesn't wait)
        var headers = HTTPHeaders()
        headers.set("Retry-After", value: "0")
        await mock.enqueue(HTTPResponse(request: request, statusCode: 429, headers: headers, body: Data()))
        
        // Second response: success
        await mock.enqueue(HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data("{\"name\":\"OK\"}".utf8)))
        
        let client = HTTPClient(
            retry: .init(maxAttempts: 3, retryableStatusCodes: [429]),
            transport: mock
        )
        
        let result = try await client.get("https://api.example.com").decode(as: TestUser.self)
        #expect(result.name == "OK")
        
        let recorded = await mock.recordedRequests()
        #expect(recorded.count == 2) // Original + 1 retry
    }
    
    @Test("retry exhaustion wraps in retryExhausted error")
    func retryExhausted() async throws {
        let mock = MockTransport()
        let url = URL(string: "https://api.example.com")!
        let request = HTTPRequest(method: .get, url: url)
        
        // Always return 500
        await mock.enqueue(HTTPResponse(request: request, statusCode: 500, headers: HTTPHeaders(), body: Data()))
        await mock.enqueue(HTTPResponse(request: request, statusCode: 500, headers: HTTPHeaders(), body: Data()))
        await mock.enqueue(HTTPResponse(request: request, statusCode: 500, headers: HTTPHeaders(), body: Data()))
        
        let client = HTTPClient(
            retry: .init(maxAttempts: 2, retryableStatusCodes: [500]),
            transport: mock
        )
        
        await #expect(throws: NetworkError.self) {
            try await client.get("https://api.example.com").send()
        }
    }
}

// MARK: - Retry Tests

@Suite("Retry")
struct RetryTests {
    @Test("exponential backoff increases delay")
    func exponentialBackoff() {
        let backoff = BackoffStrategy.exponential(base: 1.0, maxDelay: 60.0)
        let delay1 = backoff.delay(forAttempt: 1)
        let delay2 = backoff.delay(forAttempt: 2)
        #expect(delay2 >= delay1)
    }
    
    @Test("exponential backoff respects maxDelay")
    func maxDelay() {
        let backoff = BackoffStrategy.exponential(base: 1.0, maxDelay: 5.0)
        let delay = backoff.delay(forAttempt: 10)
        #expect(delay <= 5.0)
    }
}

// MARK: - Cache Tests

@Suite("Cache")
struct CacheTests {
    @Test("cache stores and retrieves")
    func storeAndRetrieve() async {
        let cache = HTTPResponseCache(maxSize: 10)
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        let response = HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data())
        
        await cache.set(response, for: request)
        let entry = await cache.get(for: request)
        
        #expect(entry != nil)
        #expect(entry?.response.statusCode == 200)
    }
    
    @Test("expired entry returns nil")
    func expiredEntry() async {
        let cache = HTTPResponseCache(maxSize: 10)
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        let response = HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data())
        
        await cache.set(response, for: request, ttl: -1)  // Already expired
        let entry = await cache.get(for: request)
        
        #expect(entry == nil)
    }
    
    @Test("LRU eviction removes oldest")
    func lruEviction() async {
        let cache = HTTPResponseCache(maxSize: 2)
        let url1 = URL(string: "https://example.com/1")!
        let url2 = URL(string: "https://example.com/2")!
        let url3 = URL(string: "https://example.com/3")!
        
        await cache.set(HTTPResponse(request: HTTPRequest(method: .get, url: url1), statusCode: 200, headers: HTTPHeaders(), body: Data()), for: HTTPRequest(method: .get, url: url1))
        await cache.set(HTTPResponse(request: HTTPRequest(method: .get, url: url2), statusCode: 200, headers: HTTPHeaders(), body: Data()), for: HTTPRequest(method: .get, url: url2))
        await cache.set(HTTPResponse(request: HTTPRequest(method: .get, url: url3), statusCode: 200, headers: HTTPHeaders(), body: Data()), for: HTTPRequest(method: .get, url: url3))
        
        // url1 should be evicted (LRU)
        let entry1 = await cache.get(for: HTTPRequest(method: .get, url: url1))
        let entry3 = await cache.get(for: HTTPRequest(method: .get, url: url3))
        #expect(entry1 == nil)
        #expect(entry3 != nil)
    }
    
    @Test("cache uses defaultTTL from configuration")
    func defaultTTL() async {
        let cache = HTTPResponseCache(maxSize: 10, defaultTTL: 600)
        let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)
        let response = HTTPResponse(request: request, statusCode: 200, headers: HTTPHeaders(), body: Data())
        
        await cache.set(response, for: request) // no explicit ttl
        let entry = await cache.get(for: request)
        
        #expect(entry != nil)
        // Entry should not be expired immediately
        #expect(entry?.isExpired == false)
    }
}

// MARK: - Test Helpers

struct TestUser: Codable {
    let name: String
}

struct TestAuthInterceptor: RequestInterceptor {
    let token: String
    
    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        var request = request
        request.headers.set("Authorization", value: "Bearer \(token)")
        return request
    }
}
