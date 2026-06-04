# ``AnvilNetwork``

A type-safe, concurrent HTTP client for Swift.

## Overview

`AnvilNetwork` provides an async HTTP client with request builders, interceptors, caching, retries, and structured error handling.

## Topics

### Client

- ``HTTPClient``
- ``HTTPClientConfiguration``
- ``HTTPClientCore``

### Requests & Responses

- ``HTTPRequest``
- ``HTTPRequestBuilder``
- ``HTTPResponse``
- ``HTTPMethod``

### Transport & Interceptors

- ``HTTPTransport``
- ``RequestInterceptor``
- ``ResponseInterceptor``

### Caching & Errors

- ``CacheConfiguration``
- ``NetworkError``
- ``NetworkLogger``
