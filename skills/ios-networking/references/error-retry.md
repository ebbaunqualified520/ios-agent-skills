# Error Handling & Retry

## NetworkError Enum

A comprehensive error type covering all networking failure modes:

```swift
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error, data: Data)
    case noConnection
    case timeout
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case clientError(statusCode: Int, message: String)
    case serverError(statusCode: Int)
    case cancelled
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, _):
            return "HTTP error \(code)"
        case .decodingError(let error, _):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .unauthorized:
            return "Authentication required"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Retry after \(Int(retryAfter)) seconds"
            }
            return "Rate limited"
        case .clientError(let code, let message):
            return "Client error \(code): \(message)"
        case .serverError(let code):
            return "Server error \(code)"
        case .cancelled:
            return "Request cancelled"
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    /// Whether this error should be retried automatically
    var isRetryable: Bool {
        switch self {
        case .serverError: return true
        case .rateLimited: return true
        case .timeout: return true
        case .noConnection: return true
        case .httpError(let code, _): return code >= 500
        default: return false
        }
    }

    /// Extract Retry-After header value
    var retryAfterInterval: TimeInterval? {
        if case .rateLimited(let interval) = self { return interval }
        return nil
    }
}
```

## HTTP Status Code Validation

```swift
func validateHTTPResponse(
    _ response: HTTPURLResponse,
    data: Data
) throws {
    switch response.statusCode {
    case 200...299:
        return // Success

    case 401:
        throw NetworkError.unauthorized

    case 429:
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
        throw NetworkError.rateLimited(retryAfter: retryAfter)

    case 400...499:
        let decoder = JSONDecoder()
        let serverError = try? decoder.decode(ServerErrorResponse.self, from: data)
        throw NetworkError.clientError(
            statusCode: response.statusCode,
            message: serverError?.message ?? HTTPURLResponse.localizedString(
                forStatusCode: response.statusCode
            )
        )

    case 500...599:
        throw NetworkError.serverError(statusCode: response.statusCode)

    default:
        throw NetworkError.httpError(statusCode: response.statusCode, data: data)
    }
}
```

## URLError Categorization

Map URLError codes to NetworkError for consistent handling:

```swift
extension NetworkError {
    init(urlError: URLError) {
        switch urlError.code {
        // No connection
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed:
            self = .noConnection

        // Timeout
        case .timedOut:
            self = .timeout

        // Cancelled
        case .cancelled:
            self = .cancelled

        // Retryable transport errors
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .internationalRoamingOff:
            self = .noConnection

        default:
            self = .unknown(urlError)
        }
    }
}

// Usage pattern: wrap URLSession calls
func safeFetch<T: Decodable>(request: URLRequest) async throws -> T {
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        try validateHTTPResponse(http, data: data)
        return try JSONDecoder.api.decode(T.self, from: data)
    } catch let error as NetworkError {
        throw error
    } catch let error as URLError {
        throw NetworkError(urlError: error)
    } catch let error as DecodingError {
        throw NetworkError.decodingError(error, data: Data())
    } catch {
        throw NetworkError.unknown(error)
    }
}
```

## Retry with Exponential Backoff

A generic retry function that handles backoff, jitter, and Retry-After headers:

```swift
struct RetryConfiguration {
    var maxAttempts: Int = 3
    var baseDelay: TimeInterval = 1.0
    var maxDelay: TimeInterval = 30.0
    var jitterFactor: Double = 0.25        // 0.0 = no jitter, 1.0 = full jitter
    var retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    var retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed
    ]
}

func withRetry<T>(
    config: RetryConfiguration = RetryConfiguration(),
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<config.maxAttempts {
        do {
            return try await operation()
        } catch let error as NetworkError where error.isRetryable {
            lastError = error

            // Check for Retry-After header
            if let retryAfter = error.retryAfterInterval {
                try await Task.sleep(for: .seconds(retryAfter))
                continue
            }

            // Don't sleep after the last attempt
            guard attempt < config.maxAttempts - 1 else { break }

            let delay = calculateDelay(
                attempt: attempt,
                baseDelay: config.baseDelay,
                maxDelay: config.maxDelay,
                jitterFactor: config.jitterFactor
            )
            try await Task.sleep(for: .seconds(delay))

        } catch let error as URLError where config.retryableURLErrorCodes.contains(error.code) {
            lastError = error
            guard attempt < config.maxAttempts - 1 else { break }

            let delay = calculateDelay(
                attempt: attempt,
                baseDelay: config.baseDelay,
                maxDelay: config.maxDelay,
                jitterFactor: config.jitterFactor
            )
            try await Task.sleep(for: .seconds(delay))

        } catch {
            // Non-retryable error — throw immediately
            throw error
        }
    }

    throw lastError ?? NetworkError.unknown(
        NSError(domain: "Retry", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "All \(config.maxAttempts) attempts failed"
        ])
    )
}

/// Exponential backoff with decorrelated jitter
private func calculateDelay(
    attempt: Int,
    baseDelay: TimeInterval,
    maxDelay: TimeInterval,
    jitterFactor: Double
) -> TimeInterval {
    // 2^attempt * baseDelay
    let exponential = baseDelay * pow(2.0, Double(attempt))
    let capped = min(exponential, maxDelay)

    // Add jitter: delay * (1 - jitter) + random * (2 * jitter * delay)
    let jitterRange = capped * jitterFactor
    let jitter = Double.random(in: -jitterRange...jitterRange)

    return max(0, capped + jitter)
}
```

### Usage

```swift
// Simple retry
let user: User = try await withRetry {
    try await apiClient.send(GetUserEndpoint(userId: 42))
}

// Custom retry config
let data = try await withRetry(config: RetryConfiguration(
    maxAttempts: 5,
    baseDelay: 2.0,
    maxDelay: 60.0
)) {
    try await apiClient.send(HeavyEndpoint())
}
```

## Actor-Based TokenManager

Thread-safe OAuth2 token management with refresh deduplication:

```swift
actor TokenManager {
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var refreshTask: Task<String, Error>?

    private let tokenURL: URL
    private let clientId: String
    private let session: URLSession

    init(
        tokenURL: URL,
        clientId: String,
        session: URLSession = .shared
    ) {
        self.tokenURL = tokenURL
        self.clientId = clientId
        self.session = session
    }

    /// Get a valid access token, refreshing if needed
    func validToken() async throws -> String {
        // If token exists and hasn't expired, return it
        if let token = accessToken, let expires = expiresAt, expires > Date.now.addingTimeInterval(30) {
            return token
        }

        // Token expired or missing — refresh
        return try await refreshAccessToken()
    }

    /// Force a token refresh (called after 401)
    func forceRefresh() async throws {
        accessToken = nil
        expiresAt = nil
        _ = try await refreshAccessToken()
    }

    /// Set tokens after initial login
    func setTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        self.accessToken = access
        self.refreshToken = refresh
        self.expiresAt = Date.now.addingTimeInterval(expiresIn)
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        refreshTask = nil
    }

    var isAuthenticated: Bool {
        refreshToken != nil
    }

    // MARK: - Private

    private func refreshAccessToken() async throws -> String {
        // Deduplicate: if a refresh is already in flight, await that one
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        guard let refresh = refreshToken else {
            throw NetworkError.unauthorized
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let bodyParams = [
                "grant_type=refresh_token",
                "refresh_token=\(refresh)",
                "client_id=\(clientId)"
            ].joined(separator: "&")
            request.httpBody = bodyParams.data(using: .utf8)

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            guard (200...299).contains(http.statusCode) else {
                // Refresh token is invalid — user must re-authenticate
                clearTokens()
                throw NetworkError.unauthorized
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken ?? refresh
            self.expiresAt = Date.now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

            return tokenResponse.accessToken
        }

        refreshTask = task
        return try await task.value
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
}
```

## Authenticated API Client

Putting retry and token management together:

```swift
final class AuthenticatedAPIClient: Sendable {
    private let client: APIClient
    private let tokenManager: TokenManager
    private let retryConfig: RetryConfiguration

    init(
        client: APIClient,
        tokenManager: TokenManager,
        retryConfig: RetryConfiguration = RetryConfiguration()
    ) {
        self.client = client
        self.tokenManager = tokenManager
        self.retryConfig = retryConfig
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        try await withRetry(config: retryConfig) { [client, tokenManager] in
            do {
                return try await client.send(endpoint)
            } catch NetworkError.unauthorized {
                // Token expired — force refresh and retry
                try await tokenManager.forceRefresh()
                throw NetworkError.unauthorized // Re-throw to trigger retry
            }
        }
    }
}
```

## Keychain Token Storage

Store tokens securely in the Keychain:

```swift
enum KeychainHelper {
    static func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary) // Remove existing
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
}

// Usage with TokenManager
extension TokenManager {
    private static let accessTokenKey = "com.app.accessToken"
    private static let refreshTokenKey = "com.app.refreshToken"

    func persistTokens() throws {
        // Called after successful login or refresh
        // Implementation saves to keychain
    }

    func loadPersistedTokens() throws {
        guard let accessData = try KeychainHelper.load(forKey: Self.accessTokenKey),
              let access = String(data: accessData, encoding: .utf8),
              let refreshData = try KeychainHelper.load(forKey: Self.refreshTokenKey),
              let refresh = String(data: refreshData, encoding: .utf8) else {
            return
        }
        setTokens(access: access, refresh: refresh, expiresIn: 0) // Will refresh on first use
    }
}
```

## User-Facing Error Presentation

Map NetworkError to user-friendly messages:

```swift
extension NetworkError {
    var userMessage: String {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "The request took too long. Please try again."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError:
            return "Something went wrong on our end. Please try again later."
        case .clientError(_, let message):
            return message
        case .cancelled:
            return "" // Don't show anything for cancelled requests
        default:
            return "An unexpected error occurred. Please try again."
        }
    }

    var isUserActionRequired: Bool {
        switch self {
        case .unauthorized: return true   // Must re-login
        case .noConnection: return true    // Must fix network
        default: return false
        }
    }
}
```

## Error Handling in SwiftUI ViewModels

```swift
@MainActor
final class ContentViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var error: NetworkError?
    @Published var isLoading = false

    private let client: AuthenticatedAPIClient

    init(client: AuthenticatedAPIClient) {
        self.client = client
    }

    func loadItems() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                items = try await client.send(GetItemsEndpoint())
            } catch let networkError as NetworkError {
                error = networkError
                if networkError == .unauthorized {
                    // Navigate to login
                    NotificationCenter.default.post(name: .userSessionExpired, object: nil)
                }
            } catch {
                self.error = .unknown(error)
            }
            isLoading = false
        }
    }
}

// In the View
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel

    var body: some View {
        List(viewModel.items) { item in
            Text(item.name)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )
        ) {
            Button("Retry") { viewModel.loadItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.error?.userMessage ?? "")
        }
        .task {
            viewModel.loadItems()
        }
    }
}
```
