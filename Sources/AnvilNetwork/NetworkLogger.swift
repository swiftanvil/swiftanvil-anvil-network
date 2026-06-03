import Foundation
import os.log

/// Logs network activity.
public protocol NetworkLogger: Sendable {
    func logRequest(_ request: HTTPRequest) async
    func logResponse(_ response: HTTPResponse, for request: HTTPRequest) async
    func logError(_ error: NetworkError, for request: HTTPRequest) async
}

/// Default logger using OSLog.
public struct DefaultNetworkLogger: NetworkLogger {
    private let logger: Logger
    
    public init(subsystem: String = "com.swiftanvil.network", category: String = "HTTP") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    
    public func logRequest(_ request: HTTPRequest) async {
        logger.info("➡️ \(request.method.rawValue) \(request.url.absoluteString)")
    }
    
    public func logResponse(_ response: HTTPResponse, for request: HTTPRequest) async {
        logger.info("⬅️ \(response.statusCode) \(request.url.absoluteString)")
    }
    
    public func logError(_ error: NetworkError, for request: HTTPRequest) async {
        logger.error("❌ \(String(describing: error)) \(request.url.absoluteString)")
    }
}
