import Foundation

#if canImport(os)
    import os.log
#endif

/// Logs network activity.
public protocol NetworkLogger: Sendable {
    func logRequest(_ request: HTTPRequest) async
    func logResponse(_ response: HTTPResponse, for request: HTTPRequest) async
    func logError(_ error: NetworkError, for request: HTTPRequest) async
}

/// Default logger using OSLog on Apple platforms, print on Linux.
public struct DefaultNetworkLogger: NetworkLogger {
    private let subsystem: String
    private let category: String

    public init(subsystem: String = "com.swiftanvil.network", category: String = "HTTP") {
        self.subsystem = subsystem
        self.category = category
    }

    public func logRequest(_ request: HTTPRequest) async {
        let message = "➡️ \(request.method.rawValue) \(request.url.absoluteString)"
        #if canImport(os)
            Logger(subsystem: subsystem, category: category).info("\(message)")
        #else
            print(message)
        #endif
    }

    public func logResponse(_ response: HTTPResponse, for request: HTTPRequest) async {
        let message = "⬅️ \(response.statusCode) \(request.url.absoluteString)"
        #if canImport(os)
            Logger(subsystem: subsystem, category: category).info("\(message)")
        #else
            print(message)
        #endif
    }

    public func logError(_ error: NetworkError, for request: HTTPRequest) async {
        let message = "❌ \(String(describing: error)) \(request.url.absoluteString)"
        #if canImport(os)
            Logger(subsystem: subsystem, category: category).error("\(message)")
        #else
            print(message)
        #endif
    }
}
