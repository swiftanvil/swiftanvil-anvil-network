import Foundation

/// Errors that can occur during a network request.
public indirect enum NetworkError: Error, Sendable {
    /// A transport-level error (no connection, timeout, etc.).
    case transport(URLError)
    
    /// The server returned a non-success status code.
    case invalidResponse(statusCode: Int, body: Data?)
    
    /// Failed to decode the response body.
    case decoding(Error, Data)
    
    /// Failed to encode the request body.
    case encoding(Error)
    
    /// All retry attempts were exhausted.
    case retryExhausted(underlying: NetworkError, attempts: Int)
    
    /// The request was cancelled.
    case cancelled
    
    /// An interceptor rejected the request.
    case interceptorRejected(reason: String)
}
