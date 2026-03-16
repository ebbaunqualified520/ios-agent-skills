# Async/Await, Tasks, and AsyncSequence Reference

## async/await Fundamentals

### Declaring Async Functions

```swift
// Basic async function
func fetchUser(id: String) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw APIError.invalidResponse
    }
    return try JSONDecoder().decode(User.self, from: data)
}

// Async property (read-only)
extension URLSession {
    var currentUser: User {
        get async throws {
            try await fetchUser(id: "current")
        }
    }
}

// Async subscript
struct RemoteCollection {
    subscript(index: Int) -> Item {
        get async throws {
            try await fetchItem(at: index)
        }
    }
}
```

### Calling Async Functions

```swift
// From another async context — just use await
func loadProfile() async throws -> Profile {
    let user = try await fetchUser(id: "123")
    let settings = try await fetchSettings(for: user)
    return Profile(user: user, settings: settings)
}

// From synchronous context — wrap in Task
func viewDidLoad() {
    super.viewDidLoad()
    Task {
        do {
            let profile = try await loadProfile()
            updateUI(with: profile)
        } catch {
            showError(error)
        }
    }
}

// From SwiftUI — use .task modifier
struct ProfileView: View {
    @State private var profile: Profile?

    var body: some View {
        VStack {
            if let profile {
                Text(profile.name)
            } else {
                ProgressView()
            }
        }
        .task {
            // Automatically cancelled when view disappears
            profile = try? await loadProfile()
        }
    }
}
```

### Error Handling

```swift
// async throws — caller must try await
func riskyOperation() async throws -> Data {
    let data = try await fetchData()
    try await validate(data)
    return data
}

// Non-throwing async — never fails
func bestEffortFetch() async -> Data? {
    try? await fetchData()
}

// Typed throws (Swift 6)
func typedOperation() async throws(NetworkError) -> Data {
    guard let url = URL(string: endpoint) else {
        throw .invalidURL
    }
    return try await download(from: url)
}
```

## Task

### Task Creation

```swift
// Inherits actor context and priority from caller
Task {
    await viewModel.loadData()
}

// With explicit priority
Task(priority: .background) {
    await performCleanup()
}

// Detached — does NOT inherit actor context or priority
Task.detached(priority: .utility) {
    await heavyProcessing()
}

// Storing task reference for cancellation
class ViewModel {
    private var loadTask: Task<Void, Never>?

    func startLoading() {
        loadTask?.cancel()
        loadTask = Task {
            await load()
        }
    }

    func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}
```

### Task Value and Result

```swift
// Task that returns a value
let task = Task<User, Error> {
    try await fetchUser(id: "123")
}

// Await the result later
let user = try await task.value

// Task.result gives you a Result type
let result = await task.result  // Result<User, Error>
switch result {
case .success(let user): print(user.name)
case .failure(let error): print(error)
}
```

### Task Cancellation

```swift
// Cooperative cancellation — tasks must check
func processItems(_ items: [Item]) async throws {
    for item in items {
        // Option 1: Throws CancellationError if cancelled
        try Task.checkCancellation()

        // Option 2: Check boolean
        guard !Task.isCancelled else {
            // Clean up and return
            return
        }

        await process(item)
    }
}

// Cancel from outside
let task = Task {
    try await processItems(items)
}
task.cancel()  // Sets isCancelled to true

// withTaskCancellationHandler — run code when cancelled
func downloadFile(url: URL) async throws -> Data {
    let handle = FileHandle(forReadingFrom: url)
    return try await withTaskCancellationHandler {
        try await handle.readToEnd()
    } onCancel: {
        handle.close()  // Called immediately when task is cancelled
    }
}
```

### Task Priority

```swift
// Priority levels (highest to lowest)
Task(priority: .userInitiated) { }  // User is waiting
Task(priority: .high) { }           // Same as .userInitiated
Task(priority: .medium) { }         // Default
Task(priority: .low) { }            // Background work
Task(priority: .utility) { }        // Long-running, user not waiting
Task(priority: .background) { }     // Lowest priority

// Priority escalation happens automatically:
// If a high-priority task awaits a low-priority task,
// the low-priority task's priority is elevated.

// Check current priority
let priority = Task.currentPriority
```

### Task Sleep

```swift
// Sleep for duration (Swift 5.7+)
try await Task.sleep(for: .seconds(2))
try await Task.sleep(for: .milliseconds(500))
try await Task.sleep(for: .nanoseconds(1_000_000))

// Sleep until deadline
try await Task.sleep(until: .now + .seconds(1), clock: .continuous)

// Sleep respects cancellation — throws CancellationError if cancelled during sleep
```

### Task.yield

```swift
// Voluntarily give up the current execution point
// Useful in long-running synchronous loops
func longComputation() async {
    for i in 0..<1_000_000 {
        if i % 1000 == 0 {
            await Task.yield()  // Let other tasks run
        }
        // ... compute
    }
}
```

## async let — Parallel Bindings

```swift
// Parallel execution — both start immediately
func loadDashboard() async throws -> Dashboard {
    async let user = fetchUser()
    async let notifications = fetchNotifications()
    async let feed = fetchFeed()

    // All three run concurrently, await collects results
    return try await Dashboard(
        user: user,
        notifications: notifications,
        feed: feed
    )
}

// async let creates implicit child tasks
// If the enclosing scope exits before await, child tasks are cancelled

// IMPORTANT: You MUST await async let before scope ends
// The compiler enforces this — you cannot ignore the result

// Error handling: if any async let throws, others are cancelled
func loadOrFail() async throws -> (A, B) {
    async let a = fetchA()  // starts immediately
    async let b = fetchB()  // starts immediately
    // If fetchA throws, fetchB is automatically cancelled
    return try await (a, b)
}
```

## TaskGroup

### Basic TaskGroup

```swift
// Non-throwing group
func fetchAllImages(urls: [URL]) async -> [UIImage] {
    await withTaskGroup(of: UIImage?.self) { group in
        for url in urls {
            group.addTask {
                try? await downloadImage(from: url)
            }
        }

        var images: [UIImage] = []
        for await image in group {
            if let image {
                images.append(image)
            }
        }
        return images
    }
}

// Throwing group
func fetchAllUsers(ids: [String]) async throws -> [User] {
    try await withThrowingTaskGroup(of: User.self) { group in
        for id in ids {
            group.addTask {
                try await fetchUser(id: id)
            }
        }

        var users: [User] = []
        for try await user in group {
            users.append(user)
        }
        return users
    }
}
```

### TaskGroup with Order Preservation

```swift
// Results come in completion order, not submission order
// To preserve order, include the index
func fetchUsersOrdered(ids: [String]) async throws -> [User] {
    let indexed = try await withThrowingTaskGroup(
        of: (Int, User).self
    ) { group in
        for (index, id) in ids.enumerated() {
            group.addTask {
                let user = try await fetchUser(id: id)
                return (index, user)
            }
        }

        var results: [(Int, User)] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }

    return indexed.sorted(by: { $0.0 < $1.0 }).map(\.1)
}
```

### TaskGroup with Concurrency Limit

```swift
// Limit concurrent tasks (e.g., max 5 at a time)
func downloadWithLimit(urls: [URL], maxConcurrent: Int = 5) async -> [Data] {
    await withTaskGroup(of: Data?.self) { group in
        var results: [Data] = []
        var iterator = urls.makeIterator()

        // Start initial batch
        for _ in 0..<min(maxConcurrent, urls.count) {
            if let url = iterator.next() {
                group.addTask { try? await download(from: url) }
            }
        }

        // As each completes, start the next
        for await data in group {
            if let data { results.append(data) }
            if let url = iterator.next() {
                group.addTask { try? await download(from: url) }
            }
        }

        return results
    }
}
```

### TaskGroup Cancellation

```swift
// Cancel all remaining tasks when first error occurs
func fetchCriticalData(ids: [String]) async throws -> [Data] {
    try await withThrowingTaskGroup(of: Data.self) { group in
        for id in ids {
            group.addTask { try await fetch(id: id) }
        }

        var results: [Data] = []
        do {
            for try await data in group {
                results.append(data)
            }
        } catch {
            group.cancelAll()  // Cancel remaining tasks
            throw error
        }
        return results
    }
}

// Cancel after getting first result
func firstSuccess(urls: [URL]) async -> Data? {
    await withTaskGroup(of: Data?.self) { group in
        for url in urls {
            group.addTask { try? await download(from: url) }
        }

        for await data in group {
            if let data {
                group.cancelAll()  // Got what we need
                return data
            }
        }
        return nil
    }
}
```

### DiscardingTaskGroup (Swift 5.9+)

```swift
// When you don't need to collect results
try await withThrowingDiscardingTaskGroup { group in
    for connection in connections {
        group.addTask {
            try await handle(connection)
        }
    }
    // No need to iterate — results are discarded
    // If any task throws, the group propagates the error
}
```

## Task-Local Values

```swift
// Declare a task-local value
enum RequestContext {
    @TaskLocal static var requestID: String = "unknown"
    @TaskLocal static var userID: String?
}

// Bind value for a scope
await RequestContext.$requestID.withValue("req-123") {
    await handleRequest()  // requestID is "req-123" here
    // Propagates to all child tasks automatically
}

// Read the value
func logMessage(_ msg: String) {
    let reqID = RequestContext.requestID
    print("[\(reqID)] \(msg)")
}

// Task-local values propagate to child tasks
await RequestContext.$requestID.withValue("req-456") {
    Task {
        print(RequestContext.requestID)  // "req-456" — inherited
    }
    async let result = processRequest()  // Also inherits "req-456"
}
```

## Continuations: Bridging Callback APIs

### withCheckedContinuation

```swift
// Bridge a callback API to async/await
func fetchImage(url: URL) async -> UIImage? {
    await withCheckedContinuation { continuation in
        SDWebImageDownloader.shared.downloadImage(with: url) { image, _, _, _ in
            continuation.resume(returning: image)
        }
    }
}

// With throwing continuation
func performAuthentication() async throws -> AuthToken {
    try await withCheckedThrowingContinuation { continuation in
        authManager.authenticate { result in
            switch result {
            case .success(let token):
                continuation.resume(returning: token)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

// CRITICAL RULES:
// 1. Resume EXACTLY once — never zero, never more than once
// 2. "Checked" variants log a warning if you violate this in debug
// 3. Not resuming = task hangs forever (resource leak)
// 4. Resuming twice = runtime crash
```

### withUnsafeContinuation

```swift
// Same as checked, but without runtime checks — slightly faster
// Use only when you're 100% certain about single-resume semantics
func fastBridge() async -> Data {
    await withUnsafeContinuation { continuation in
        quickFetch { data in
            continuation.resume(returning: data)
        }
    }
}

// Prefer withCheckedContinuation during development
// Switch to withUnsafeContinuation only after thorough testing for performance-critical paths
```

### Continuation with Cancellation

```swift
// Handle cancellation in bridged APIs
func fetchWithCancellation(url: URL) async throws -> Data {
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    } onCancel: {
        // Note: onCancel may be called concurrently
        // The continuation must still be resumed
    }
}
```

## AsyncSequence

### Protocol and Built-in Conformances

```swift
// AsyncSequence protocol
protocol AsyncSequence {
    associatedtype AsyncIterator: AsyncIteratorProtocol
    associatedtype Element
    func makeAsyncIterator() -> AsyncIterator
}

// Iterate with for-await-in
for await line in url.lines {
    print(line)
}

// Built-in AsyncSequences
// URLSession.bytes — byte stream from URL
let (bytes, _) = try await URLSession.shared.bytes(from: url)
for try await byte in bytes {
    process(byte)
}

// FileHandle.bytes — bytes from file
let handle = FileHandle(forReadingAtPath: path)!
for await byte in handle.bytes {
    process(byte)
}

// NotificationCenter.notifications
for await notification in NotificationCenter.default.notifications(named: .myEvent) {
    handleEvent(notification)
}
```

### AsyncSequence Operators

```swift
let urls: [URL] = [...]

// map
let sizes = urls.async.map { url in
    try await fetchSize(for: url)
}

// filter
for try await line in url.lines.filter({ !$0.isEmpty }) {
    process(line)
}

// compactMap
for await number in strings.async.compactMap({ Int($0) }) {
    print(number)
}

// prefix — take first N
for await event in eventStream.prefix(10) {
    handle(event)
}

// first(where:)
let match = await stream.first(where: { $0.isRelevant })

// contains
let hasError = await logStream.contains(where: { $0.isError })

// reduce
let total = await numbers.reduce(0, +)
```

## AsyncStream and AsyncThrowingStream

### Creating AsyncStream

```swift
// Basic AsyncStream with yield
let countdown = AsyncStream<Int> { continuation in
    for i in (1...10).reversed() {
        continuation.yield(i)
        try? await Task.sleep(for: .seconds(1))
    }
    continuation.finish()
}

for await count in countdown {
    print(count)
}

// AsyncStream with onTermination
let notifications = AsyncStream<Notification> { continuation in
    let observer = NotificationCenter.default.addObserver(
        forName: .myEvent,
        object: nil,
        queue: nil
    ) { notification in
        continuation.yield(notification)
    }

    continuation.onTermination = { @Sendable _ in
        NotificationCenter.default.removeObserver(observer)
    }
}
```

### AsyncStream from Delegate

```swift
// Bridge CLLocationManager delegate to AsyncStream
class LocationService {
    func locationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let delegate = Delegate(
                onLocation: { continuation.yield($0) },
                onError: { _ in continuation.finish() }
            )
            let manager = CLLocationManager()
            manager.delegate = delegate
            manager.startUpdatingLocation()

            continuation.onTermination = { @Sendable _ in
                manager.stopUpdatingLocation()
            }

            // Store delegate to prevent deallocation
            continuation.yield(with: .success(CLLocation()))
        }
    }
}
```

### AsyncStream Buffering Policy

```swift
// Buffering policies control behavior when producer is faster than consumer
// .unbounded — buffer everything (default, can consume memory)
let stream1 = AsyncStream<Int>(bufferingPolicy: .unbounded) { continuation in
    for i in 0..<1000 { continuation.yield(i) }
    continuation.finish()
}

// .bufferingOldest(N) — keep oldest N elements, drop new ones
let stream2 = AsyncStream<Int>(bufferingPolicy: .bufferingOldest(10)) { cont in
    for i in 0..<1000 { cont.yield(i) }
    cont.finish()
}

// .bufferingNewest(N) — keep newest N elements, drop old ones
// Best for "latest value" scenarios like UI updates
let stream3 = AsyncStream<Int>(bufferingPolicy: .bufferingNewest(1)) { cont in
    for i in 0..<1000 { cont.yield(i) }
    cont.finish()
}
```

### AsyncStream.Continuation (makeStream pattern)

```swift
// Swift 5.9+: makeStream returns (stream, continuation) pair
let (stream, continuation) = AsyncStream.makeStream(of: Int.self)

// Producer can yield from anywhere
Task {
    for i in 0..<10 {
        continuation.yield(i)
        try await Task.sleep(for: .seconds(1))
    }
    continuation.finish()
}

// Consumer iterates
Task {
    for await value in stream {
        print(value)
    }
}
```

### AsyncThrowingStream

```swift
// Same as AsyncStream but supports throwing
let dataStream = AsyncThrowingStream<Data, Error> { continuation in
    api.startStreaming(
        onData: { data in
            continuation.yield(data)
        },
        onError: { error in
            continuation.finish(throwing: error)
        },
        onComplete: {
            continuation.finish()
        }
    )

    continuation.onTermination = { @Sendable _ in
        api.stopStreaming()
    }
}

// Consume with try
do {
    for try await chunk in dataStream {
        process(chunk)
    }
} catch {
    handleStreamError(error)
}
```

### Bridging Example: Timer

```swift
// Create an async timer stream
func timerStream(interval: Duration) -> AsyncStream<Date> {
    AsyncStream { continuation in
        let timer = Timer.scheduledTimer(withTimeInterval: interval.seconds, repeats: true) { _ in
            continuation.yield(Date.now)
        }
        continuation.onTermination = { @Sendable _ in
            timer.invalidate()
        }
    }
}

// Usage
for await tick in timerStream(interval: .seconds(1)) {
    updateClock(tick)
}
```

### Bridging Example: Combine Publisher

```swift
// Convert Combine publisher to AsyncSequence
extension Publisher where Failure == Never {
    var values: AsyncPublisher<Self> { ... }
    // Built-in since iOS 15
}

// Usage
let publisher = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
for await notification in publisher.values {
    handleOrientationChange(notification)
}

// For throwing publishers
extension Publisher {
    var values: AsyncThrowingPublisher<Self> { ... }
}

for try await value in somePublisher.values {
    process(value)
}
```

### Bridging Example: Callback API to Continuation

```swift
// Complex callback API bridge
func recognizeSpeech() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechAudioBufferRecognitionRequest()

        recognizer?.recognitionTask(with: request) { result, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            if let result, result.isFinal {
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
            // Note: only resume once — ignore non-final results
            // This is safe because we only resume on error or isFinal
        }
    }
}
```
