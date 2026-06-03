import Foundation

/// A wrapper that makes any `Error` `Sendable` by capturing its description.
public struct SendableError: Sendable {
    public let description: String
    public init(_ error: Error) {
        self.description = String(describing: error)
    }
}

/// Errors that can occur during a network request.
public indirect enum NetworkError: Error, Sendable {
    /// A transport-level error (no connection, timeout, etc.).
    case transport(URLError)
    
    /// The server returned a non-success status code.
    case invalidResponse(statusCode: Int, body: Data?)
    
    /// Failed to decode the response body.
    case decoding(SendableError, Data)
    
    /// Failed to encode the request body.
    case encoding(SendableError)
    
    /// All retry attempts were exhausted.
    case retryExhausted(underlying: NetworkError, attempts: Int)
    
    /// The request was cancelled.
    case cancelled
    
    /// An interceptor rejected the request.
    case interceptorRejected(reason: String)
    
    /// The HTTP status code associated with this error, if any.
    public var statusCode: Int? {
        switch self {
        case .invalidResponse(let statusCode, _):
            return statusCode
        case .retryExhausted(let underlying, _):
            return underlying.statusCode
        default:
            return nil
        }
    }
}
