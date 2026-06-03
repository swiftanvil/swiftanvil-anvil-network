import Foundation

/// A type-safe HTTP request.
public struct HTTPRequest: Sendable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: HTTPHeaders
    public var body: HTTPBody?
    
    public init(method: HTTPMethod, url: URL) {
        self.method = method
        self.url = url
        self.headers = HTTPHeaders()
        self.body = nil
    }
    
    public init(method: HTTPMethod, baseURL: URL, path: String) {
        self.method = method
        self.url = baseURL.appendingPathComponent(path)
        self.headers = HTTPHeaders()
        self.body = nil
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
public enum HTTPBody: Sendable {
    case data(Data)
    case json(Data)
    
    public func encoded() -> Data {
        switch self {
        case .data(let data):
            return data
        case .json(let data):
            return data
        }
    }
}
