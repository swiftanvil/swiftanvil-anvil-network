# AnvilNetwork

> Type-safe HTTP client for Swift with caching, retry, and observability.

## Overview

AnvilNetwork provides a concurrent, Swift 6-strict HTTP client with:

- **Type-safe requests**: Builder-pattern API with compile-time method safety
- **Automatic retry**: Exponential backoff with jitter, respects `Retry-After`
- **Response caching**: In-memory LRU cache with TTL and ETag support
- **Interceptors**: Async request/response chains for auth, logging, etc.
- **Observability**: `NetworkLogger` protocol with OSLog default
- **Testability**: `HTTPTransport` protocol for mock injection

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/swiftanvil/swiftanvil-anvil-network.git", from: "1.0.0"),
]
```

```swift
targets: [.target(name: "MyTarget", dependencies: [.product(name: "AnvilNetwork", package: "swiftanvil-anvil-network")])]
```

## Quick Start

```swift
import AnvilNetwork

// Basic GET with auto-decode
let client = HTTPClient()
let user: User = try await client.get("/users/\(id)").decode()

// With configuration
let client = HTTPClient(
    baseURL: URL(string: "https://api.example.com")!,
    timeout: .init(request: 30),
    cache: .init(strategy: .memory(maxSize: 10_000_000)),
    retry: .init(maxAttempts: 3)
)

// POST with body
let response = try await client.post("/users")
    .body(newUser)
    .header("Content-Type", "application/json")
    .send()

// With auth interceptor
let authedClient = client.addingRequestInterceptor(
    BearerTokenInterceptor(tokenProvider: { try await tokenStore.getToken() })
)
```

## Architecture

```
AnvilNetwork
├── HTTPClient.swift              # Public API (Sendable struct)
├── HTTPClientCore.swift          # Actor-isolated core
├── HTTPRequest.swift             # Request + Headers + Body
├── HTTPResponse.swift            # Response + decode()
├── HTTPMethod.swift              # Type-safe HTTP methods
├── HTTPTransport.swift           # Transport protocol + URLSession impl
├── Interceptors.swift            # Request/Response interceptor protocols
├── NetworkLogger.swift           # Logging protocol + OSLog default
├── Cache.swift                   # Actor-isolated LRU cache
├── Retry.swift                   # Retry config + backoff strategies
└── NetworkError.swift            # Comprehensive error enum
```

## Requirements

- iOS 18+ / macOS 15+ / tvOS 18+ / watchOS 11+ / visionOS 2+
- Swift 6.0+

## License

MIT
