# Advanced Networking Topics

## WebSocket: URLSessionWebSocketTask

### Basic WebSocket Connection

```swift
final class WebSocketConnection {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let url: URL

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
    }

    func disconnect(reason: String = "Client disconnect") {
        task?.cancel(with: .goingAway, reason: reason.data(using: .utf8))
        task = nil
    }

    func send(_ message: String) async throws {
        guard let task else { throw WebSocketError.notConnected }
        try await task.send(.string(message))
    }

    func send(_ data: Data) async throws {
        guard let task else { throw WebSocketError.notConnected }
        try await task.send(.data(data))
    }

    func sendJSON<T: Encodable>(_ value: T) async throws {
        let data = try JSONEncoder.api.encode(value)
        try await send(data)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let task else { throw WebSocketError.notConnected }
        return try await task.receive()
    }

    func ping() async throws {
        guard let task else { throw WebSocketError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum WebSocketError: Error {
    case notConnected
    case invalidMessage
    case connectionLost
}
```

### AsyncThrowingStream WebSocket Wrapper

Wrap WebSocket receive into an AsyncSequence for ergonomic consumption:

```swift
actor WebSocketStream {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let url: URL
    private var isConnected = false

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func connect() -> AsyncThrowingStream<WebSocketMessage, Error> {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true

        return AsyncThrowingStream { continuation in
            let receiveTask = Task { [weak self] in
                while let self, await self.isConnected {
                    do {
                        guard let wsTask = await self.task else { break }
                        let message = try await wsTask.receive()

                        switch message {
                        case .string(let text):
                            continuation.yield(.text(text))
                        case .data(let data):
                            continuation.yield(.binary(data))
                        @unknown default:
                            break
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
                Task { [weak self] in
                    await self?.disconnect()
                }
            }
        }
    }

    func send(_ text: String) async throws {
        guard let task, isConnected else { throw WebSocketError.notConnected }
        try await task.send(.string(text))
    }

    func disconnect() {
        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}

enum WebSocketMessage {
    case text(String)
    case binary(Data)

    func decode<T: Decodable>(as type: T.Type) throws -> T {
        let data: Data
        switch self {
        case .text(let string):
            data = Data(string.utf8)
        case .binary(let d):
            data = d
        }
        return try JSONDecoder.api.decode(T.self, from: data)
    }
}

// Usage in a ViewModel
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var connectionState: ConnectionState = .disconnected

    private let socket = WebSocketStream(url: URL(string: "wss://chat.example.com/ws")!)
    private var receiveTask: Task<Void, Never>?

    enum ConnectionState { case connected, disconnected, reconnecting }

    func connect() {
        connectionState = .connected
        receiveTask = Task {
            do {
                let stream = await socket.connect()
                for try await message in stream {
                    if let chatMsg = try? message.decode(as: ChatMessage.self) {
                        messages.append(chatMsg)
                    }
                }
            } catch {
                connectionState = .disconnected
                // Auto-reconnect after delay
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { connect() }
            }
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        Task { await socket.disconnect() }
        connectionState = .disconnected
    }

    func sendMessage(_ text: String) {
        Task {
            let msg = OutgoingMessage(text: text)
            let data = try JSONEncoder.api.encode(msg)
            try await socket.send(String(data: data, encoding: .utf8)!)
        }
    }
}
```

## Caching

### URLCache Configuration

```swift
// Configure app-wide cache (in AppDelegate or App init)
let cache = URLCache(
    memoryCapacity: 50 * 1024 * 1024,   // 50 MB memory
    diskCapacity: 200 * 1024 * 1024      // 200 MB disk
)
URLCache.shared = cache

// Per-session cache
let config = URLSessionConfiguration.default
config.urlCache = URLCache(
    memoryCapacity: 20 * 1024 * 1024,
    diskCapacity: 100 * 1024 * 1024
)
config.requestCachePolicy = .useProtocolCachePolicy
```

### Cache Policies

```swift
// Respect server Cache-Control headers (default, recommended)
request.cachePolicy = .useProtocolCachePolicy

// Always load from origin, update cache
request.cachePolicy = .reloadIgnoringLocalCacheData

// Return cached data if available, even if expired; else load from network
request.cachePolicy = .returnCacheDataElseLoad

// Return cached data if available (even expired); never go to network
request.cachePolicy = .returnCacheDataDontLoad

// Usage: offline-first pattern
func fetchWithOfflineFallback<T: Decodable>(
    url: URL,
    session: URLSession
) async throws -> (data: T, isFromCache: Bool) {
    var request = URLRequest(url: url)

    // Try network first
    request.cachePolicy = .useProtocolCachePolicy
    do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.invalidResponse
        }
        let decoded = try JSONDecoder.api.decode(T.self, from: data)
        return (decoded, false)
    } catch {
        // Network failed — try cache
        request.cachePolicy = .returnCacheDataDontLoad
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder.api.decode(T.self, from: data)
        return (decoded, true)
    }
}
```

### Manual Cache Management

```swift
extension URLCache {
    /// Remove cached response for a specific URL
    func removeCachedResponse(for url: URL) {
        let request = URLRequest(url: url)
        removeCachedResponse(for: request)
    }

    /// Store a custom cached response
    func storeCachedResponse(data: Data, for url: URL, maxAge: Int = 3600) {
        let request = URLRequest(url: url)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Cache-Control": "max-age=\(maxAge)",
                "Content-Type": "application/json"
            ]
        ) else { return }

        let cached = CachedURLResponse(response: response, data: data)
        storeCachedResponse(cached, for: request)
    }
}
```

### Actor-Based ResponseCache for Decoded Objects

In-memory cache for decoded objects with TTL:

```swift
actor ResponseCache<T> {
    private struct CacheEntry {
        let value: T
        let expiresAt: Date
    }

    private var storage: [String: CacheEntry] = [:]
    private let defaultTTL: TimeInterval

    init(defaultTTL: TimeInterval = 300) { // 5 minutes
        self.defaultTTL = defaultTTL
    }

    func get(_ key: String) -> T? {
        guard let entry = storage[key], entry.expiresAt > Date.now else {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func set(_ key: String, value: T, ttl: TimeInterval? = nil) {
        let entry = CacheEntry(
            value: value,
            expiresAt: Date.now.addingTimeInterval(ttl ?? defaultTTL)
        )
        storage[key] = entry
    }

    func remove(_ key: String) {
        storage.removeValue(forKey: key)
    }

    func clear() {
        storage.removeAll()
    }

    /// Remove all expired entries
    func prune() {
        let now = Date.now
        storage = storage.filter { $0.value.expiresAt > now }
    }
}

// Usage in APIClient
final class CachedAPIClient {
    private let client: APIClient
    private let cache = ResponseCache<Any>(defaultTTL: 300)

    init(client: APIClient) {
        self.client = client
    }

    func send<E: Endpoint>(
        _ endpoint: E,
        cacheKey: String? = nil,
        ttl: TimeInterval? = nil
    ) async throws -> E.Response {
        let key = cacheKey ?? "\(endpoint.method.rawValue):\(endpoint.path)"

        // Check cache for GET requests only
        if endpoint.method == .get, let cached = await cache.get(key) as? E.Response {
            return cached
        }

        let response = try await client.send(endpoint)

        if endpoint.method == .get {
            await cache.set(key, value: response, ttl: ttl)
        }

        return response
    }

    func invalidate(_ key: String) async {
        await cache.remove(key)
    }
}
```

## NWPathMonitor (Network Connectivity)

### Observable NetworkMonitor

```swift
import Network

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown
    private(set) var isExpensive = false       // Cellular or personal hotspot
    private(set) var isConstrained = false     // Low Data Mode

    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
                self?.connectionType = self?.resolveType(path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func resolveType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .unknown
    }
}

// Usage in SwiftUI
struct ContentView: View {
    @State private var networkMonitor = NetworkMonitor()

    var body: some View {
        VStack {
            if !networkMonitor.isConnected {
                OfflineBanner()
            }
            // ... main content
        }
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("No Internet Connection")
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.9))
        .foregroundStyle(.white)
        .font(.caption.bold())
    }
}
```

### Wait for Connectivity Pattern

```swift
extension NetworkMonitor {
    /// Suspend until network becomes available
    func waitForConnection() async {
        guard !isConnected else { return }

        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    monitor.cancel()
                    continuation.resume()
                }
            }
            monitor.start(queue: DispatchQueue(label: "WaitForConnection"))
        }
    }
}
```

## Multipart Form Data

### MultipartFormData Builder

```swift
struct MultipartFormData {
    private let boundary: String
    private var parts: [Part] = []

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(name: String, value: String) {
        let part = Part(
            name: name,
            data: Data(value.utf8),
            fileName: nil,
            mimeType: nil
        )
        parts.append(part)
    }

    mutating func addFile(
        name: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        let part = Part(
            name: name,
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
        parts.append(part)
    }

    func build() -> Data {
        var body = Data()

        for part in parts {
            body.append("--\(boundary)\r\n")

            if let fileName = part.fileName, let mimeType = part.mimeType {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(fileName)\"\r\n")
                body.append("Content-Type: \(mimeType)\r\n")
            } else {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\r\n")
            }

            body.append("\r\n")
            body.append(part.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    private struct Part {
        let name: String
        let data: Data
        let fileName: String?
        let mimeType: String?
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
```

### Upload with MultipartFormData

```swift
func uploadAvatar(image: UIImage, userId: String) async throws -> AvatarResponse {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        throw NetworkError.invalidURL
    }

    var formData = MultipartFormData()
    formData.addField(name: "user_id", value: userId)
    formData.addFile(
        name: "avatar",
        fileName: "avatar.jpg",
        mimeType: "image/jpeg",
        data: imageData
    )

    let body = formData.build()

    var request = URLRequest(url: URL(string: "https://api.example.com/v1/avatars")!)
    request.httpMethod = "POST"
    request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.invalidResponse
    }

    return try JSONDecoder.api.decode(AvatarResponse.self, from: data)
}
```

## Certificate Pinning

Pin the server certificate or public key to prevent MITM attacks:

```swift
final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedHashes: Set<String>

    /// Initialize with base64-encoded SHA-256 hashes of the certificate's Subject Public Key Info
    init(pinnedHashes: Set<String>) {
        self.pinnedHashes = pinnedHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Evaluate the server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        guard isValid else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Check certificate chain
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        for index in 0..<certificateCount {
            guard let certificate = SecTrustCopyCertificateChain(serverTrust)?[index] as? SecCertificate else {
                continue
            }

            let publicKey = SecCertificateCopyKey(certificate)
            guard let publicKeyData = publicKey.flatMap({ SecKeyCopyExternalRepresentation($0, nil) as Data? }) else {
                continue
            }

            let hash = sha256(publicKeyData).base64EncodedString()
            if pinnedHashes.contains(hash) {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        }

        // No pin matched
        return (.cancelAuthenticationChallenge, nil)
    }

    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// Usage
let delegate = PinnedSessionDelegate(pinnedHashes: [
    "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" // Your cert's SPKI SHA-256
])
let session = URLSession(
    configuration: .default,
    delegate: delegate,
    delegateQueue: nil
)
```

## GraphQL with Apollo iOS 2.0

### Setup and Configuration

```swift
import Apollo
import ApolloAPI

final class GraphQLClient {
    static let shared = GraphQLClient()

    private(set) lazy var apollo: ApolloClient = {
        let url = URL(string: "https://api.example.com/graphql")!

        // Network transport with auth
        let transport = RequestChainNetworkTransport(
            interceptorProvider: DefaultInterceptorProvider(store: store),
            endpointURL: url,
            additionalHeaders: [
                "Authorization": "Bearer \(token)"
            ]
        )

        return ApolloClient(networkTransport: transport, store: store)
    }()

    private let store = ApolloStore(cache: InMemoryNormalizedCache())
    private var token: String = ""

    func setToken(_ token: String) {
        self.token = token
    }
}
```

### Query

```swift
// Generated from .graphql files by Apollo codegen
// query GetUser($id: ID!) { user(id: $id) { id name email avatar { url } } }

func fetchUser(id: String) async throws -> GetUserQuery.Data.User {
    try await withCheckedThrowingContinuation { continuation in
        GraphQLClient.shared.apollo.fetch(
            query: GetUserQuery(id: id),
            cachePolicy: .fetchIgnoringCacheCompletely
        ) { result in
            switch result {
            case .success(let response):
                if let user = response.data?.user {
                    continuation.resume(returning: user)
                } else if let errors = response.errors {
                    continuation.resume(throwing: GraphQLError.serverErrors(errors))
                } else {
                    continuation.resume(throwing: GraphQLError.noData)
                }
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
```

### Mutation

```swift
// mutation CreatePost($input: CreatePostInput!) { createPost(input: $input) { id title } }

func createPost(title: String, body: String) async throws -> CreatePostMutation.Data.CreatePost {
    let input = CreatePostInput(title: title, body: body)

    return try await withCheckedThrowingContinuation { continuation in
        GraphQLClient.shared.apollo.perform(
            mutation: CreatePostMutation(input: input)
        ) { result in
            switch result {
            case .success(let response):
                if let post = response.data?.createPost {
                    continuation.resume(returning: post)
                } else if let errors = response.errors {
                    continuation.resume(throwing: GraphQLError.serverErrors(errors))
                } else {
                    continuation.resume(throwing: GraphQLError.noData)
                }
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

enum GraphQLError: Error {
    case noData
    case serverErrors([Apollo.GraphQLError])
}
```

### Apollo Cache Policies

```swift
// .returnCacheDataElseFetch — cache first, network fallback (default)
// .fetchIgnoringCacheData — always network, update cache
// .fetchIgnoringCacheCompletely — network only, don't cache
// .returnCacheDataDontFetch — cache only, fail if not cached
// .returnCacheDataAndFetch — return cache immediately, then fetch and update

// Example: show cached data instantly, then refresh
func fetchUsersWithCache() async throws -> [GetUsersQuery.Data.User] {
    try await withCheckedThrowingContinuation { continuation in
        GraphQLClient.shared.apollo.fetch(
            query: GetUsersQuery(),
            cachePolicy: .returnCacheDataAndFetch
        ) { result in
            // Note: This fires twice — once for cache, once for network
            switch result {
            case .success(let response):
                if let users = response.data?.users {
                    continuation.resume(returning: users)
                }
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
```

## REST vs GraphQL Decision Guide

| Factor | REST | GraphQL |
|--------|------|---------|
| Simple CRUD | Preferred | Overkill |
| Multiple resources in one request | N+1 problem, need custom endpoints | Single query |
| Bandwidth-sensitive (mobile) | Over-fetching common | Request exactly what you need |
| File uploads | Native multipart support | Needs special handling |
| Caching | HTTP caching works out of the box | Normalized cache (Apollo) |
| Real-time | WebSocket / SSE | Subscriptions |
| Team size / complexity | Lower barrier | Requires schema management |
| Backend flexibility | Multiple backends easy | Needs dedicated GraphQL server |

**Rule of thumb**: Start with REST. Move to GraphQL when you have many related resources and mobile bandwidth matters, or when over-fetching becomes a measurable performance problem.

## Upload Progress Tracking

```swift
final class ProgressTrackingDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}

// Usage with async delegate (iOS 15+)
func uploadWithProgress(data: Data, to url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let delegate = ProgressTrackingDelegate { progress in
        Task { @MainActor in
            // Update UI with progress
            print("Upload progress: \(Int(progress * 100))%")
        }
    }

    let (responseData, response) = try await URLSession.shared.upload(
        for: request,
        from: data,
        delegate: delegate
    )

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.invalidResponse
    }

    return responseData
}
```
