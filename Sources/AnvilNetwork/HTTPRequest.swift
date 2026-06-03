import Foundation

/// A type-safe HTTP request.
public struct HTTPRequest: Sendable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: HTTPHeaders
    public var body: HTTPBody
    
    public init(method: HTTPMethod, url: URL, body: HTTPBody = .empty) {
        self.method = method
        self.url = url
        self.headers = HTTPHeaders()
        self.body = body
    }
    
    public init(method: HTTPMethod, baseURL: URL, path: String, body: HTTPBody = .empty) {
        self.method = method
        self.url = baseURL.appendingPathComponent(path)
        self.headers = HTTPHeaders()
        self.body = body
    }
}

/// HTTP headers with case-insensitive access.
public struct HTTPHeaders: Sendable {
    private var storage: [String: String]
    
    public init() {
        self.storage = [:]
    }
    
    public subscript(_ name: String) -> String? {
        get { storage[name.lowercased()] }
        set { storage[name.lowercased()] = newValue }
    }
    
    public mutating func add(_ name: String, value: String) {
        let key = name.lowercased()
        if let existing = storage[key] {
            storage[key] = "\(existing), \(value)"
        } else {
            storage[key] = value
        }
    }
    
    public mutating func set(_ name: String, value: String) {
        storage[name.lowercased()] = value
    }
    
    public func allHeaders() -> [String: String] {
        storage
    }
}

/// The body of an HTTP request.
public enum HTTPBody: Sendable, Equatable {
    case empty
    case data(Data)
    case json(Data)
    
    public func encoded() -> Data {
        switch self {
        case .empty:
            return Data()
        case .data(let data):
            return data
        case .json(let data):
            return data
        }
    }
    
    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }
}
