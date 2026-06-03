import Foundation

/// A type-safe HTTP response.
public struct HTTPResponse: Sendable {
    public let request: HTTPRequest
    public let statusCode: Int
    public let headers: HTTPHeaders
    public let body: Data
    
    public init(request: HTTPRequest, statusCode: Int, headers: HTTPHeaders, body: Data) {
        self.request = request
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
    
    /// Decodes the response body as the given type.
    public func decode<T: Decodable>(as type: T.Type = T.self, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(T.self, from: body)
    }
}
