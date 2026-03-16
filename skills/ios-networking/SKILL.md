---
name: ios-networking
description: >
  iOS networking expert skill covering URLSession with async/await, type-safe generic API clients,
  Codable JSON encoding/decoding, error handling with retry and exponential backoff, OAuth2 token management,
  WebSocket connections, caching strategies (URLCache/NSCache), network monitoring (NWPathMonitor),
  multipart uploads, certificate pinning, and GraphQL with Apollo. Use this skill whenever the user builds
  networking code, API clients, handles JSON, implements authentication flows, or works with remote data.
  Triggers on: URLSession, networking, API client, REST, HTTP, JSON, Codable, endpoint, fetch data,
  download, upload, WebSocket, cache, network monitor, reachability, multipart, GraphQL, Apollo,
  bearer token, refresh token, retry, backoff, certificate pinning, URL, request, response, async networking.
---

# iOS Networking Skill

## Core Rules

1. **Always use async/await** (NOT completion handlers) for new networking code. Completion handlers are legacy — Swift Concurrency is the standard since iOS 15.
2. **Build a generic APIClient** with an Endpoint protocol for type-safe requests. Never scatter raw URLSession calls throughout the codebase.
3. **Use actor-based TokenManager** for thread-safe OAuth2 token refresh with deduplication. Never allow multiple simultaneous refresh requests.
4. **Handle ALL HTTP status codes properly**:
   - 401 → refresh token, retry original request
   - 429 → respect Retry-After header, exponential backoff
   - 5xx → retry with exponential backoff + jitter
   - 4xx (other) → client error, do not retry
5. **Use URLProtocol mocking for tests** (NOT mocking URLSession itself). URLProtocol intercepts at the transport layer and tests real serialization paths.
6. **Reuse URLSession instances** — creating a session per request prevents HTTP/2 connection multiplexing and wastes memory.
7. **Use URLCache** with `.useProtocolCachePolicy` as the default cache policy. Configure cache size explicitly for production apps.
8. **NWPathMonitor for connectivity awareness**, NOT pre-flight checks. Never gate a request on reachability — just make the request and handle the error.
9. **Codable with `.convertFromSnakeCase`** and custom date strategies. Avoid manual CodingKeys when snake_case conversion handles it.
10. **Keep ATS enabled.** Use domain-specific exceptions in Info.plist only when absolutely necessary. Never disable ATS globally.

## Decision Guide

| Task | Solution | Reference |
|------|----------|-----------|
| Simple GET/POST | `URLSession.shared.data(for:)` | [urlsession.md](references/urlsession.md) |
| Multiple endpoints | Generic APIClient + Endpoint protocol | [api-client.md](references/api-client.md) |
| Auth with token refresh | Actor-based TokenManager | [error-retry.md](references/error-retry.md) |
| Real-time data | URLSessionWebSocketTask | [advanced.md](references/advanced.md) |
| Large file download | URLSession download task | [urlsession.md](references/urlsession.md) |
| Background upload | Background URLSession configuration | [urlsession.md](references/urlsession.md) |
| Offline support | URLCache + `.returnCacheDataElseLoad` | [advanced.md](references/advanced.md) |
| Network status | NWPathMonitor | [advanced.md](references/advanced.md) |
| File upload | MultipartFormData builder | [advanced.md](references/advanced.md) |
| Dynamic JSON | JSONValue enum | [api-client.md](references/api-client.md) |
| Certificate pinning | URLSessionDelegate | [advanced.md](references/advanced.md) |
| GraphQL | Apollo iOS 2.0 | [advanced.md](references/advanced.md) |

## Architecture Patterns

### Minimal URLSession Call (Quick Reference)

```swift
func fetchUser(id: Int) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(User.self, from: data)
}
```

### Production API Client (Quick Reference)

```swift
// 1. Define endpoint
struct GetUserEndpoint: Endpoint {
    typealias Response = User
    let userId: Int
    var path: String { "/users/\(userId)" }
    var method: HTTPMethod { .get }
}

// 2. Call through client
let user = try await apiClient.send(GetUserEndpoint(userId: 42))
```

### Authenticated Request Flow

```
Request → AuthInterceptor (attach token)
       → URLSession.data(for:)
       → 401? → TokenManager.forceRefresh()
              → Retry original request with new token
       → Decode response
```

## Common Mistakes to Avoid

| Mistake | Why It's Wrong | Fix |
|---------|---------------|-----|
| `URLSession()` per request | Kills HTTP/2 multiplexing, leaks memory | Reuse a shared or injected session |
| Checking reachability before request | Race condition, wastes time | Just make the request, handle errors |
| `NSAllowsArbitraryLoads = true` | Disables all ATS security | Use domain-specific exceptions |
| Decoding on main thread | Blocks UI for large payloads | URLSession already decodes off-main |
| Force-unwrapping URL | Crashes on malformed strings | Use guard + throw pattern |
| Ignoring HTTP status codes | 404/500 treated as success | Always validate response status |
| Mocking URLSession directly | Fragile, doesn't test serialization | Use URLProtocol subclass |
| `JSONSerialization` for Codable types | Verbose, error-prone | Use JSONDecoder/JSONEncoder |
| Retry without backoff | Server overload, ban risk | Exponential backoff + jitter |
| Token refresh without dedup | Multiple simultaneous refreshes | Actor with stored Task |

## File Upload Decision Tree

```
Need to upload?
├── Small file (<5MB) → URLSession upload task with Data
├── Large file (>5MB) → URLSession upload task with file URL
├── Multiple files → MultipartFormData builder
├── Background upload → Background URLSession config
└── Progress tracking → URLSessionTaskDelegate (async delegate)
```

## HTTP Method Semantics

| Method | Idempotent | Body | Use Case |
|--------|-----------|------|----------|
| GET | Yes | No | Fetch resource |
| POST | No | Yes | Create resource |
| PUT | Yes | Yes | Replace resource |
| PATCH | No | Yes | Partial update |
| DELETE | Yes | Optional | Remove resource |
| HEAD | Yes | No | Check existence |

## Testing Strategy

1. **Unit tests**: URLProtocol mock → test request building, response parsing, error handling
2. **Integration tests**: Staged/sandbox API → test real network stack
3. **Snapshot tests**: Capture request/response pairs for regression

```swift
// URLProtocol mock setup
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// Usage in tests
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)
let client = APIClient(session: session)

MockURLProtocol.requestHandler = { request in
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let data = try JSONEncoder().encode(User(id: 1, name: "Test"))
    return (response, data)
}

let user = try await client.send(GetUserEndpoint(userId: 1))
XCTAssertEqual(user.name, "Test")
```

## Performance Checklist

- [ ] Reuse URLSession instances (one per configuration type)
- [ ] Configure `httpMaximumConnectionsPerHost` (default 6, increase for API-heavy apps)
- [ ] Enable HTTP/2 (default in URLSession, verify server supports it)
- [ ] Set appropriate `timeoutIntervalForRequest` (30s default, reduce for user-facing)
- [ ] Use `waitsForConnectivity = true` for non-urgent requests
- [ ] Configure URLCache size (memoryCapacity + diskCapacity)
- [ ] Use `AsyncBytes` for streaming instead of buffering large responses
- [ ] Cancel tasks when views disappear (use `.task` modifier in SwiftUI)

## Minimum Deployment Targets

| Feature | Minimum iOS |
|---------|-------------|
| URLSession async/await | 15.0 |
| URLSession.data(for:) | 15.0 |
| AsyncBytes | 15.0 |
| URLSessionWebSocketTask | 13.0 |
| NWPathMonitor | 12.0 |
| Background URLSession | 7.0 |
| Codable | 11.0 |
| async URLSession delegate | 15.0 |

## References

- [URLSession Fundamentals](references/urlsession.md) — configurations, async tasks, background sessions, streaming
- [API Client Architecture](references/api-client.md) — Endpoint protocol, generic client, interceptors, Codable patterns
- [Error Handling & Retry](references/error-retry.md) — NetworkError, exponential backoff, token management
- [Advanced Topics](references/advanced.md) — WebSocket, caching, NWPathMonitor, multipart, GraphQL
