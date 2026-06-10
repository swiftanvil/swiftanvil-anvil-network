import Foundation

/// Intercepts and modifies requests before they are sent.
public protocol RequestInterceptor: Sendable {
    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest
}

/// Intercepts and modifies responses after they are received.
public protocol ResponseInterceptor: Sendable {
    func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse
}

/// A request interceptor that adds a bearer token authorization header.
public struct BearerTokenInterceptor: RequestInterceptor {
    private let tokenProvider: @Sendable () async throws -> String

    public init(tokenProvider: @escaping @Sendable () async throws -> String) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        var request = request
        let token = try await tokenProvider()
        request.headers.set("Authorization", value: "Bearer \(token)")
        return request
    }
}

/// A response interceptor that logs responses.
public struct LoggingInterceptor: ResponseInterceptor {
    private let logger: NetworkLogger

    public init(logger: NetworkLogger = DefaultNetworkLogger()) {
        self.logger = logger
    }

    public func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        await logger.logResponse(response, for: request)
        return response
    }
}
