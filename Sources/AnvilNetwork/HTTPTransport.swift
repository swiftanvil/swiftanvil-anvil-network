import Foundation

/// A transport that sends HTTP requests and returns responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// A transport backed by `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared, timeout: TimeoutConfiguration? = nil) {
        if let timeout {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout.request
            config.timeoutIntervalForResource = timeout.resource
            self.session = URLSession(configuration: config)
        } else {
            self.session = session
        }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers.allHeaders()

        if !request.body.isEmpty {
            urlRequest.httpBody = request.body.encoded()
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse(statusCode: 0, body: data)
            }

            var headers = HTTPHeaders()
            for (key, value) in httpResponse.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers.set(key, value: value)
                }
            }

            return HTTPResponse(
                request: request,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: data
            )
        } catch let error as URLError {
            if error.code == .cancelled {
                throw NetworkError.cancelled
            }
            throw NetworkError.transport(error)
        }
    }
}
