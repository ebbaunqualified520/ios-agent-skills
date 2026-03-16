# API Client Architecture

## Endpoint Protocol

Define a protocol that describes any API endpoint in a type-safe way:

```swift
protocol Endpoint {
    associatedtype Response: Decodable

    var scheme: String { get }
    var host: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem] { get }
    var body: Data? { get }
}

// Sensible defaults so endpoints only override what they need
extension Endpoint {
    var scheme: String { "https" }
    var host: String { AppConfig.apiHost }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem] { [] }
    var body: Data? { nil }
}
```

## HTTPMethod Enum

```swift
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}
```

## Concrete Endpoints

```swift
struct GetUsersEndpoint: Endpoint {
    typealias Response = [User]

    let page: Int
    let limit: Int

    var path: String { "/v1/users" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
    }
}

struct GetUserEndpoint: Endpoint {
    typealias Response = User

    let userId: Int

    var path: String { "/v1/users/\(userId)" }
    var method: HTTPMethod { .get }
}

struct CreateUserEndpoint: Endpoint {
    typealias Response = User

    let name: String
    let email: String

    var path: String { "/v1/users" }
    var method: HTTPMethod { .post }
    var headers: [String: String] { ["Content-Type": "application/json"] }
    var body: Data? {
        try? JSONEncoder.api.encode(CreateUserRequest(name: name, email: email))
    }
}

struct DeleteUserEndpoint: Endpoint {
    typealias Response = EmptyResponse

    let userId: Int

    var path: String { "/v1/users/\(userId)" }
    var method: HTTPMethod { .delete }
}

struct EmptyResponse: Decodable {}
```

## Generic Request Type (Alternative Pattern)

When you need a more flexible request object:

```swift
struct Request<Response: Decodable> {
    let method: HTTPMethod
    let path: String
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?

    func asURLRequest(baseURL: URL) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

// Usage
let request = Request<[User]>(method: .get, path: "/v1/users", queryItems: [
    URLQueryItem(name: "active", value: "true")
])
```

## APIClient

The core networking client that sends endpoints and returns decoded responses:

```swift
final class APIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let interceptors: [any Interceptor]

    init(
        baseURL: URL = URL(string: "https://api.example.com")!,
        session: URLSession = .shared,
        decoder: JSONDecoder = .api,
        interceptors: [any Interceptor] = []
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.interceptors = interceptors
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        var request = buildRequest(from: endpoint)

        // Apply interceptors (auth, logging, etc.)
        for interceptor in interceptors {
            request = try await interceptor.intercept(request)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        // Let interceptors handle response (e.g., token refresh on 401)
        for interceptor in interceptors {
            try await interceptor.handleResponse(httpResponse, data: data, for: request)
        }

        try validateStatusCode(httpResponse.statusCode, data: data)

        // Handle empty responses (204 No Content, DELETE, etc.)
        if data.isEmpty, let empty = EmptyResponse() as? E.Response {
            return empty
        }

        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decodingError(error, data: data)
        }
    }

    /// Send and discard response body (for DELETE, POST with no return)
    func sendVoid<E: Endpoint>(_ endpoint: E) async throws where E.Response == EmptyResponse {
        _ = try await send(endpoint)
    }

    private func buildRequest<E: Endpoint>(from endpoint: E) -> URLRequest {
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.path = endpoint.path
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Endpoint-specific headers
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func validateStatusCode(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 429:
            throw NetworkError.rateLimited(retryAfter: nil)
        case 400...499:
            let serverError = try? decoder.decode(ServerErrorResponse.self, from: data)
            throw NetworkError.clientError(
                statusCode: statusCode,
                message: serverError?.message ?? "Client error"
            )
        case 500...599:
            throw NetworkError.serverError(statusCode: statusCode)
        default:
            throw NetworkError.httpError(statusCode: statusCode, data: data)
        }
    }
}

struct ServerErrorResponse: Decodable {
    let message: String
    let code: String?
}
```

## Interceptor / Middleware Pattern

Interceptors modify requests before sending and inspect responses after receiving:

```swift
protocol Interceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
    func handleResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async throws
}

extension Interceptor {
    // Default no-op implementations
    func intercept(_ request: URLRequest) async throws -> URLRequest { request }
    func handleResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async throws {}
}
```

### Auth Interceptor

```swift
struct AuthInterceptor: Interceptor {
    private let tokenManager: TokenManager

    init(tokenManager: TokenManager) {
        self.tokenManager = tokenManager
    }

    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let token = try await tokenManager.validToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func handleResponse(
        _ response: HTTPURLResponse,
        data: Data,
        for request: URLRequest
    ) async throws {
        if response.statusCode == 401 {
            // Force refresh for next request
            try await tokenManager.forceRefresh()
        }
    }
}
```

### Logging Interceptor

```swift
struct LoggingInterceptor: Interceptor {
    private let logger = Logger(subsystem: "com.app", category: "Network")

    func intercept(_ request: URLRequest) async throws -> URLRequest {
        logger.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        return request
    }

    func handleResponse(
        _ response: HTTPURLResponse,
        data: Data,
        for request: URLRequest
    ) async throws {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        let status = response.statusCode
        let size = data.count

        if (200...299).contains(status) {
            logger.debug("← \(status) \(method) \(url) (\(size) bytes)")
        } else {
            logger.warning("← \(status) \(method) \(url) (\(size) bytes)")
            if let body = String(data: data, encoding: .utf8) {
                logger.debug("  Body: \(body.prefix(500))")
            }
        }
    }
}
```

### API Key Interceptor

```swift
struct APIKeyInterceptor: Interceptor {
    let apiKey: String

    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }
}
```

## Assembling the Client

```swift
// In your DI container or app setup
let tokenManager = TokenManager(/* ... */)

let apiClient = APIClient(
    baseURL: URL(string: AppConfig.apiBaseURL)!,
    session: NetworkSessionFactory.makeAPISession(),
    interceptors: [
        LoggingInterceptor(),
        AuthInterceptor(tokenManager: tokenManager),
    ]
)

// Usage in a ViewModel
let users = try await apiClient.send(GetUsersEndpoint(page: 1, limit: 20))
let user = try await apiClient.send(GetUserEndpoint(userId: 42))
try await apiClient.sendVoid(DeleteUserEndpoint(userId: 42))
```

## Codable Patterns

### Shared Encoder/Decoder Configuration

```swift
extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds first
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateString) {
                return date
            }
            // Fall back to standard ISO 8601
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
```

### CodingKeys for Non-Standard Mappings

Only use explicit CodingKeys when snake_case conversion doesn't handle the mapping:

```swift
struct Product: Codable {
    let id: Int
    let displayName: String    // ← display_name works with .convertFromSnakeCase
    let sku: String            // ← maps to "sku" (same)
    let priceUSD: Double       // ← "price_u_s_d" ≠ "price_usd", need CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case displayName       // handled by .convertFromSnakeCase as "display_name"
        case sku
        case priceUSD = "price_usd"  // explicit override
    }
}
```

### Custom Date Strategies

```swift
// Unix timestamp (seconds)
decoder.dateDecodingStrategy = .secondsSince1970

// Unix timestamp (milliseconds) — common in Java/JS backends
decoder.dateDecodingStrategy = .custom { decoder in
    let container = try decoder.singleValueContainer()
    let ms = try container.decode(Double.self)
    return Date(timeIntervalSince1970: ms / 1000.0)
}

// Custom format
decoder.dateDecodingStrategy = .formatted({
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
}())
```

### Nested JSON Extraction

When the response wraps data in an envelope:

```swift
// API returns: { "data": { ... }, "meta": { "page": 1 } }
struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let meta: Meta?
}

struct Meta: Decodable {
    let page: Int?
    let totalPages: Int?
    let totalCount: Int?
}

// In APIClient, unwrap the envelope:
func sendUnwrapped<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
    // Decode as APIResponse<E.Response> then return .data
    let wrapper: APIResponse<E.Response> = try await sendRaw(endpoint)
    return wrapper.data
}
```

### Dynamic Keys

When JSON keys are dynamic (e.g., a dictionary):

```swift
// { "users": { "123": { "name": "John" }, "456": { "name": "Jane" } } }
struct UsersResponse: Decodable {
    let users: [String: User]
}

// Or decode any string-keyed JSON:
struct DynamicKeysContainer: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var result: [String: String] = [:]
        for key in container.allKeys {
            result[key.stringValue] = try container.decode(String.self, forKey: key)
        }
        values = result
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}
```

### Optional & Default Handling

```swift
// Property wrapper for defaulting missing/null values
@propertyWrapper
struct Default<T: Decodable & DefaultValue>: Decodable {
    var wrappedValue: T

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = (try? container.decode(T.self)) ?? T.defaultValue
    }
}

protocol DefaultValue {
    static var defaultValue: Self { get }
}

extension Bool: DefaultValue { static var defaultValue: Bool { false } }
extension Int: DefaultValue { static var defaultValue: Int { 0 } }
extension String: DefaultValue { static var defaultValue: String { "" } }
extension Array: DefaultValue where Element: Decodable { static var defaultValue: [Element] { [] } }

// Usage
struct UserProfile: Decodable {
    let name: String
    @Default var bio: String          // defaults to "" if missing or null
    @Default var isVerified: Bool     // defaults to false if missing or null
    @Default var tags: [String]       // defaults to [] if missing or null
}
```

## JSONValue Enum for Dynamic JSON

Handle arbitrarily structured JSON:

```swift
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Convenience accessors
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var numberValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, index < array.count else { return nil }
        return array[index]
    }
}

// Usage with Codable models
struct AnalyticsEvent: Codable {
    let name: String
    let timestamp: Date
    let properties: [String: JSONValue]  // Arbitrary key-value pairs
}
```

## Paginated Responses

```swift
struct PaginatedResponse<T: Decodable>: Decodable {
    let data: [T]
    let meta: PaginationMeta
}

struct PaginationMeta: Decodable {
    let currentPage: Int
    let totalPages: Int
    let totalCount: Int
    let hasNextPage: Bool
}

// AsyncSequence for auto-pagination
struct PaginatedSequence<T: Decodable>: AsyncSequence {
    typealias Element = [T]

    let client: APIClient
    let basePath: String
    let limit: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let client: APIClient
        let basePath: String
        let limit: Int
        var currentPage = 1
        var hasMore = true

        mutating func next() async throws -> [T]? {
            guard hasMore else { return nil }

            let endpoint = PaginatedEndpoint<T>(
                path: basePath,
                page: currentPage,
                limit: limit
            )
            let response: PaginatedResponse<T> = try await client.send(endpoint)
            hasMore = response.meta.hasNextPage
            currentPage += 1
            return response.data.isEmpty ? nil : response.data
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(client: client, basePath: basePath, limit: limit)
    }
}

// Usage
for try await page in PaginatedSequence<User>(client: apiClient, basePath: "/v1/users", limit: 20) {
    users.append(contentsOf: page)
}
```
