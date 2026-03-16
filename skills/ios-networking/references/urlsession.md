# URLSession Fundamentals

## Session Configurations

URLSession provides three configuration types. Choose based on your use case:

```swift
// Default: disk-persisted cache, cookies, credentials
let defaultConfig = URLSessionConfiguration.default

// Ephemeral: no persistent storage (private browsing equivalent)
let ephemeralConfig = URLSessionConfiguration.ephemeral

// Background: transfers continue when app is suspended/terminated
let backgroundConfig = URLSessionConfiguration.background(withIdentifier: "com.app.background-upload")
```

### Key Configuration Properties

```swift
let config = URLSessionConfiguration.default

// Timeouts
config.timeoutIntervalForRequest = 30    // Per-request timeout (seconds)
config.timeoutIntervalForResource = 300  // Total resource timeout (seconds)

// Connection management
config.httpMaximumConnectionsPerHost = 6 // Default is 6; increase for API-heavy apps
config.waitsForConnectivity = true       // Wait for connectivity instead of failing immediately
config.allowsConstrainedNetworkAccess = true  // Allow on Low Data Mode
config.allowsExpensiveNetworkAccess = true    // Allow on cellular

// Cache
config.urlCache = URLCache(
    memoryCapacity: 20 * 1024 * 1024,  // 20 MB memory
    diskCapacity: 100 * 1024 * 1024     // 100 MB disk
)
config.requestCachePolicy = .useProtocolCachePolicy // Respect server cache headers

// Headers applied to every request
config.httpAdditionalHeaders = [
    "Accept": "application/json",
    "X-App-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
]

// Multiplex (HTTP/2) — enabled by default
config.multipathServiceType = .none // .handover or .interactive for multipath TCP
```

### Creating a Properly Configured Session

```swift
final class NetworkSessionFactory {
    static func makeAPISession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        return URLSession(configuration: config)
    }

    static func makeImageSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        return URLSession(configuration: config)
    }

    static func makeBackgroundSession(delegate: URLSessionDelegate) -> URLSession {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.app.background-transfer"
        )
        config.isDiscretionary = false          // Start immediately
        config.sessionSendsLaunchEvents = true  // Wake app on completion
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}
```

## Async Data Tasks

### GET Request

```swift
func fetchData<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
        throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
}

// Usage
let users: [User] = try await fetchData(from: usersURL, as: [User].self)
```

### POST Request

```swift
func createUser(_ user: CreateUserRequest) async throws -> User {
    var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    request.httpBody = try encoder.encode(user)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.httpError(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
            data: data
        )
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(User.self, from: data)
}
```

### Upload Task

```swift
func uploadFile(data: Data, to url: URL, mimeType: String) async throws -> UploadResponse {
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
    request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

    let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.httpError(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
            data: responseData
        )
    }

    return try JSONDecoder().decode(UploadResponse.self, from: responseData)
}
```

### Download Task

```swift
func downloadFile(from url: URL) async throws -> URL {
    let (localURL, response) = try await URLSession.shared.download(from: url)

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw NetworkError.httpError(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
            data: Data()
        )
    }

    // Move from temp location to permanent location
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let savedURL = documentsURL.appendingPathComponent(url.lastPathComponent)

    if FileManager.default.fileExists(atPath: savedURL.path) {
        try FileManager.default.removeItem(at: savedURL)
    }
    try FileManager.default.moveItem(at: localURL, to: savedURL)

    return savedURL
}
```

## AsyncBytes Streaming

Use `AsyncBytes` for streaming responses — ideal for Server-Sent Events (SSE) or large payloads processed line-by-line.

### Line-by-Line Streaming

```swift
func streamLines(from url: URL) async throws -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: url)

                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continuation.finish(throwing: NetworkError.httpError(
                        statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                        data: Data()
                    ))
                    return
                }

                for try await line in bytes.lines {
                    continuation.yield(line)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}
```

### Server-Sent Events (SSE) Parser

```swift
struct SSEEvent {
    let event: String?
    let data: String
    let id: String?
}

func streamSSE(from url: URL) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continuation.finish(throwing: NetworkError.invalidResponse)
                    return
                }

                var eventType: String?
                var dataBuffer = ""
                var eventId: String?

                for try await line in bytes.lines {
                    if line.isEmpty {
                        // Empty line = dispatch event
                        if !dataBuffer.isEmpty {
                            let event = SSEEvent(
                                event: eventType,
                                data: dataBuffer.trimmingCharacters(in: .newlines),
                                id: eventId
                            )
                            continuation.yield(event)
                        }
                        eventType = nil
                        dataBuffer = ""
                        eventId = nil
                    } else if line.hasPrefix("event:") {
                        eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        dataBuffer += dataBuffer.isEmpty ? data : "\n" + data
                    } else if line.hasPrefix("id:") {
                        eventId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}
```

## Background Sessions

Background sessions allow transfers to continue when the app is suspended or terminated.

### Background Download Manager

```swift
final class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadManager()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.app.background-downloads"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var completionHandlers: [String: () -> Void] = [:]
    private var progressHandlers: [String: (Double) -> Void] = [:]
    private var downloadContinuations: [String: CheckedContinuation<URL, Error>] = [:]

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url)
            downloadContinuations[task.taskDescription ?? "\(task.taskIdentifier)"] = continuation
            task.taskDescription = url.absoluteString
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let key = downloadTask.taskDescription ?? "\(downloadTask.taskIdentifier)"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = documentsURL.appendingPathComponent(
            downloadTask.originalRequest?.url?.lastPathComponent ?? UUID().uuidString
        )

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
            downloadContinuations[key]?.resume(returning: destURL)
        } catch {
            downloadContinuations[key]?.resume(throwing: error)
        }
        downloadContinuations.removeValue(forKey: key)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let key = downloadTask.taskDescription ?? "\(downloadTask.taskIdentifier)"
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandlers[key]?(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let key = task.taskDescription ?? "\(task.taskIdentifier)"
        downloadContinuations[key]?.resume(throwing: error)
        downloadContinuations.removeValue(forKey: key)
    }

    // MARK: - App Delegate Integration

    /// Call from AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)
    func handleBackgroundCompletion(identifier: String, completionHandler: @escaping () -> Void) {
        completionHandlers[identifier] = completionHandler
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let id = session.configuration.identifier,
              let handler = completionHandlers.removeValue(forKey: id) else { return }
        DispatchQueue.main.async { handler() }
    }
}
```

### App Delegate Hook

```swift
// In AppDelegate or App struct
func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
) {
    BackgroundDownloadManager.shared.handleBackgroundCompletion(
        identifier: identifier,
        completionHandler: completionHandler
    )
}
```

## Task Cancellation with Swift Concurrency

### Automatic Cancellation in SwiftUI

```swift
struct UserProfileView: View {
    let userId: Int
    @State private var user: User?
    @State private var error: Error?

    var body: some View {
        Group {
            if let user {
                Text(user.name)
            } else if let error {
                Text("Error: \(error.localizedDescription)")
            } else {
                ProgressView()
            }
        }
        .task { // Automatically cancelled when view disappears
            do {
                user = try await APIClient.shared.send(GetUserEndpoint(userId: userId))
            } catch is CancellationError {
                // View disappeared, ignore
            } catch {
                self.error = error
            }
        }
    }
}
```

### Manual Cancellation with Task Handle

```swift
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [SearchResult] = []

    private var searchTask: Task<Void, Never>?

    func search() {
        // Cancel previous in-flight search
        searchTask?.cancel()

        searchTask = Task {
            // Debounce
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let results = try await APIClient.shared.send(
                    SearchEndpoint(query: query)
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { self.results = results }
            } catch is CancellationError {
                // Expected, ignore
            } catch {
                // Handle real error
            }
        }
    }
}
```

## Combine: DataTaskPublisher (Legacy Reference)

Use only when integrating with existing Combine pipelines. For new code, prefer async/await.

```swift
import Combine

func fetchUserPublisher(id: Int) -> AnyPublisher<User, Error> {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    return URLSession.shared.dataTaskPublisher(for: url)
        .tryMap { data, response in
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw NetworkError.invalidResponse
            }
            return data
        }
        .decode(type: User.self, decoder: {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }())
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}
```

## Request Building Utilities

```swift
extension URLRequest {
    /// Create a JSON request with common defaults
    static func json(
        url: URL,
        method: String = "GET",
        body: Encodable? = nil,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
```

## URL Construction

Always use URLComponents for safe URL construction:

```swift
extension URL {
    static func api(
        path: String,
        queryItems: [URLQueryItem] = [],
        baseURL: String = "https://api.example.com"
    ) -> URL? {
        var components = URLComponents(string: baseURL)
        components?.path = path
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url
    }
}

// Usage
let url = URL.api(
    path: "/users",
    queryItems: [
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "limit", value: "20"),
        URLQueryItem(name: "q", value: "john doe") // Automatically percent-encoded
    ]
)
```
