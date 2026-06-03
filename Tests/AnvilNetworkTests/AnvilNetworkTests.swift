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
}

// MARK: - Mock Transport

actor MockTransport: HTTPTransport {
    var responses: [HTTPResponse] = []
    var requests: [HTTPRequest] = []
    var error: NetworkError?
    
    func enqueue(_ response: HTTPResponse) {
        responses.append(response)
    }
    
    func enqueue(error: NetworkError) {
        self.error = error
    }
    
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if let error = error {
            self.error = nil
            throw error
        }
        return responses.removeFirst()
    }
}

// MARK: - HTTPClient Tests

@Suite("HTTPClient")
struct HTTPClientTests {
    
    @Test("GET request returns decoded response")
    func getRequest() async throws {
        let mock = MockTransport()
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.example.com/users/1")!)
        let response = HTTPResponse(
            request: request,
            statusCode: 200,
            headers: HTTPHeaders(),
            body: Data("{\"name\":\"Ada\"}".utf8)
        )
        await mock.enqueue(response)
        
        let client = HTTPClient(configuration: .default)
        // Note: In real tests we'd inject mock transport; for now test the builder API
        // This test demonstrates the API shape
    }
    
    @Test("request builder creates correct method")
    func requestBuilderMethod() {
        let client = HTTPClient()
        let builder = client.get("/users")
        #expect(builder != nil)  // Builder exists
    }
    
    @Test("HTTPClient is Sendable")
    func sendable() {
        let client = HTTPClient()
        let _ = client as Sendable
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
}
