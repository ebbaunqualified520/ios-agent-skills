# Concurrency Patterns, Swift 6 Migration, and Combine vs async/await

## Swift 6 Strict Concurrency Migration

### Enabling Strict Concurrency

```swift
// In Package.swift — per target
.target(
    name: "MyFeature",
    swiftSettings: [.swiftLanguageMode(.v6)]
)

// Incremental: enable warnings first (Swift 5 mode)
.target(
    name: "MyFeature",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
    ]
)

// In Xcode: Build Settings → Swift Language Version → 6
// Or for warnings: Other Swift Flags → -strict-concurrency=complete
```

### Common Errors and Fixes

```swift
// ERROR: Capture of 'self' with non-sendable type 'MyClass' in a @Sendable closure
class MyClass {
    var data: [String] = []
    func load() {
        Task {
            data = await fetchData()  // Error: self is not Sendable
        }
    }
}

// FIX 1: Make class @MainActor (if it's a UI class)
@MainActor
class MyClass {
    var data: [String] = []
    func load() {
        Task {
            data = await fetchData()  // OK — Task inherits MainActor isolation
        }
    }
}

// FIX 2: Make class an actor (if it manages shared state)
actor MyManager {
    var data: [String] = []
    func load() async {
        data = await fetchData()
    }
}

// FIX 3: Make class final + Sendable (if immutable)
final class MyConfig: Sendable {
    let data: [String]
    init(data: [String]) { self.data = data }
}
```

```swift
// ERROR: Static property 'shared' is not concurrency-safe
class AppManager {
    static let shared = AppManager()  // Warning in Swift 6
}

// FIX 1: Use actor
actor AppManager {
    static let shared = AppManager()  // Actors are Sendable — OK
}

// FIX 2: @MainActor
@MainActor
class AppManager {
    static let shared = AppManager()  // MainActor-isolated — OK
}

// FIX 3: nonisolated(unsafe) — escape hatch
class AppManager {
    nonisolated(unsafe) static let shared = AppManager()
}
```

```swift
// ERROR: Global var 'logger' is not concurrency-safe
var logger = Logger()

// FIX 1: Make it a let (if possible)
let logger = Logger()  // Immutable + Sendable = OK

// FIX 2: Use actor
actor LoggerActor {
    static let shared = LoggerActor()
    private let logger = Logger()
    func log(_ message: String) { logger.log(message) }
}

// FIX 3: nonisolated(unsafe) for known-safe globals
nonisolated(unsafe) var logger = Logger()
```

```swift
// ERROR: Non-sendable type 'ThirdPartyType' passed across concurrency boundary
// When using types from frameworks that haven't adopted Sendable

// FIX: @preconcurrency import
@preconcurrency import ThirdPartyFramework

// This tells the compiler to trust the framework's types
// Remove when the framework adds Sendable annotations
```

### Incremental Adoption Strategy

```
1. Start with Swift 5.10 + StrictConcurrency=complete (warnings only)
2. Fix warnings module by module, starting with leaf modules
3. Add Sendable conformances to your data types
4. Add @MainActor to UI-related classes
5. Convert shared state managers to actors
6. Use @preconcurrency import for third-party frameworks
7. Once all warnings are fixed, switch to Swift 6 language mode
```

## Debouncing with Task Cancellation

```swift
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    func onQueryChanged(_ newQuery: String) {
        query = newQuery

        // Cancel previous search
        searchTask?.cancel()

        guard !newQuery.isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            // Wait 300ms — if another keystroke cancels us, we stop here
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            do {
                let searchResults = try await api.search(query: newQuery)
                // Check cancellation again after network call
                guard !Task.isCancelled else { return }
                results = searchResults
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }
        }
    }
}

// SwiftUI view
struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        List(viewModel.results) { result in
            Text(result.title)
        }
        .searchable(text: $viewModel.query)
        .onChange(of: viewModel.query) { _, newValue in
            viewModel.onQueryChanged(newValue)
        }
    }
}
```

## Throttling with Actor

```swift
actor Throttle {
    private let interval: Duration
    private var lastExecution: ContinuousClock.Instant?

    init(interval: Duration) {
        self.interval = interval
    }

    func execute(_ action: @Sendable () async -> Void) async {
        let now = ContinuousClock.now
        if let last = lastExecution, now - last < interval {
            return  // Skip — too soon
        }
        lastExecution = now
        await action()
    }
}

// Usage
let throttle = Throttle(interval: .seconds(1))

func onScroll() {
    Task {
        await throttle.execute {
            await loadMoreItems()
        }
    }
}
```

## Actor-Based Cache / Shared State Manager

```swift
actor CacheManager<Key: Hashable & Sendable, Value: Sendable> {
    private var cache: [Key: CacheEntry] = [:]
    private let maxAge: Duration

    struct CacheEntry {
        let value: Value
        let timestamp: ContinuousClock.Instant
    }

    init(maxAge: Duration = .seconds(300)) {
        self.maxAge = maxAge
    }

    func get(_ key: Key) -> Value? {
        guard let entry = cache[key] else { return nil }
        if ContinuousClock.now - entry.timestamp > maxAge {
            cache[key] = nil
            return nil
        }
        return entry.value
    }

    func set(_ key: Key, value: Value) {
        cache[key] = CacheEntry(value: value, timestamp: .now)
    }

    func getOrFetch(_ key: Key, fetch: @Sendable () async throws -> Value) async throws -> Value {
        if let cached = get(key) {
            return cached
        }
        let value = try await fetch()
        set(key, value: value)
        return value
    }

    func invalidate(_ key: Key) {
        cache[key] = nil
    }

    func invalidateAll() {
        cache.removeAll()
    }

    func prune() {
        let now = ContinuousClock.now
        cache = cache.filter { now - $0.value.timestamp <= maxAge }
    }
}

// Usage
let userCache = CacheManager<String, User>(maxAge: .minutes(5))

func getUser(id: String) async throws -> User {
    try await userCache.getOrFetch(id) {
        try await api.fetchUser(id: id)
    }
}
```

## Background Data Processing Pattern

```swift
actor DataProcessor {
    private var isProcessing = false
    private var pendingItems: [RawItem] = []

    func enqueue(_ items: [RawItem]) async -> [ProcessedItem] {
        // Add to queue
        pendingItems.append(contentsOf: items)

        // If already processing, wait for it
        guard !isProcessing else {
            return await waitForResults(items)
        }

        return await processQueue()
    }

    private func processQueue() async -> [ProcessedItem] {
        isProcessing = true
        defer { isProcessing = false }

        var results: [ProcessedItem] = []

        // Process in batches to avoid blocking the actor too long
        while !pendingItems.isEmpty {
            let batch = Array(pendingItems.prefix(50))
            pendingItems.removeFirst(min(50, pendingItems.count))

            // Heavy work — offload to detached task to not block actor
            let processed = await Task.detached(priority: .utility) {
                batch.map { self.transform($0) }
            }.value

            results.append(contentsOf: processed)
        }

        return results
    }

    // nonisolated because it's pure computation with no actor state
    nonisolated private func transform(_ item: RawItem) -> ProcessedItem {
        // CPU-intensive transformation
        ProcessedItem(data: item.data.processed())
    }
}
```

## MainActor for UI Updates (3 Ways)

```swift
// Way 1: @MainActor annotation (preferred for classes/functions)
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: Profile?

    func load() async {
        profile = try? await api.fetchProfile()
        // Already on MainActor — UI update is safe
    }
}

// Way 2: MainActor.run (for one-off switches)
func processInBackground() async {
    let result = await heavyComputation()

    await MainActor.run {
        self.label.text = "\(result)"
        self.spinner.stopAnimating()
    }
}

// Way 3: .task modifier in SwiftUI (automatic MainActor context)
struct ProfileView: View {
    @State private var profile: Profile?

    var body: some View {
        Group {
            if let profile {
                Text(profile.name)
            } else {
                ProgressView()
            }
        }
        .task {
            // Runs on MainActor (view context)
            // Automatically cancelled when view disappears
            profile = try? await api.fetchProfile()
        }
        .task(id: userId) {
            // Re-runs when userId changes
            // Previous task is cancelled automatically
            profile = try? await api.fetchProfile(id: userId)
        }
    }
}
```

## Converting Combine to async/await

### Publisher.values

```swift
// Built-in: any Publisher where Failure == Never
let publisher = Just("Hello")
for await value in publisher.values {
    print(value)  // "Hello"
}

// CurrentValueSubject
let subject = CurrentValueSubject<Int, Never>(0)
Task {
    for await value in subject.values {
        print(value)  // 0, then any subsequent values
    }
}
subject.send(1)
subject.send(2)

// NotificationCenter publisher
for await _ in NotificationCenter.default
    .publisher(for: UIApplication.didBecomeActiveNotification)
    .values {
    refreshData()
}
```

### Custom Combine-to-Async Bridge

```swift
// For publishers with Failure != Never
extension Publisher {
    func firstValue() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = self.first()
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break  // Value already delivered
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                    }
                )
        }
    }
}

// Usage
let result = try await somePublisher.firstValue()
```

### AsyncStream from Combine Publisher

```swift
extension Publisher where Failure == Never {
    func toAsyncStream() -> AsyncStream<Output> {
        AsyncStream { continuation in
            let cancellable = self.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}

// Usage
let stream = myPublisher.toAsyncStream()
for await value in stream {
    handle(value)
}
```

## Converting async/await to Combine

```swift
// Wrap async function in a Future
func fetchUserPublisher(id: String) -> AnyPublisher<User, Error> {
    Future { promise in
        Task {
            do {
                let user = try await fetchUser(id: id)
                promise(.success(user))
            } catch {
                promise(.failure(error))
            }
        }
    }
    .eraseToAnyPublisher()
}

// Wrap AsyncSequence in a publisher (custom)
struct AsyncSequencePublisher<S: AsyncSequence>: Publisher
    where S.Element: Sendable {
    typealias Output = S.Element
    typealias Failure = Error

    let sequence: S

    func receive<Sub>(subscriber: Sub) where Sub: Subscriber,
        Failure == Sub.Failure, Output == Sub.Input {
        let subscription = AsyncSubscription(sequence: sequence, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}
```

## When to Use Combine vs async/await

```
Use ASYNC/AWAIT for:
├── One-shot async operations (network request, file read)
├── Sequential async steps (fetch → process → save)
├── Parallel operations (TaskGroup, async let)
├── Simple data flow (ViewModel loads data)
└── New code — always prefer async/await

Use COMBINE for:
├── Complex reactive UI bindings (@Published + sink)
├── Multi-stream merging (merge, combineLatest, zip)
├── Time-based operations (debounce, throttle, delay)
│   (though Task cancellation works for debounce)
├── Existing Combine pipelines (don't rewrite working code)
└── SwiftUI @Published property observation

Use BOTH together:
├── ViewModel uses @Published (Combine) + async methods
├── .values bridges Combine → async when needed
└── AsyncStream bridges async → event stream
```

## Common Anti-Patterns

### Task.detached Overuse

```swift
// BAD: Using detached for no reason
Task.detached {
    await viewModel.loadData()
    // Lost MainActor context, lost priority inheritance
}

// GOOD: Regular Task inherits context
Task {
    await viewModel.loadData()
}

// WHEN TO USE Task.detached:
// Only when you explicitly need to escape the current actor
// Example: CPU-heavy work that should NOT run on MainActor
@MainActor
func processLargeDataset() async {
    let data = largeDataset

    // Correct use of detached — escape MainActor for heavy computation
    let result = await Task.detached(priority: .utility) {
        Self.heavyCompute(data)  // Runs on cooperative pool, not MainActor
    }.value

    self.results = result  // Back on MainActor
}
```

### Blocking Actors

```swift
// BAD: Synchronous heavy work inside actor
actor ImageProcessor {
    func process(_ image: UIImage) -> UIImage {
        applyComplexFilter(image)  // Blocks the actor for seconds
        // No other actor method can run during this time
    }
}

// GOOD: Offload heavy sync work
actor ImageProcessor {
    func process(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .utility) {
            applyComplexFilter(image)
        }.value
    }
}
```

### Forgetting Cancellation

```swift
// BAD: No cancellation support
func syncAllData() async throws {
    for item in allItems {  // Could be thousands
        try await upload(item)
        // If task is cancelled, still runs all items
    }
}

// GOOD: Cooperative cancellation
func syncAllData() async throws {
    for item in allItems {
        try Task.checkCancellation()
        try await upload(item)
    }
}
```

### Holding Actor Lock Across Await

```swift
// CAUTION: Actor state may change across await
actor OrderManager {
    var orders: [Order] = []

    // Risky: reading orders, then awaiting, then using orders
    func processAllOrders() async throws {
        let currentOrders = orders  // Snapshot before await
        for order in currentOrders {
            try await processOrder(order)
            // orders may have changed here due to reentrancy!
        }
    }

    // Better: work with a snapshot or re-check
    func processAllOrdersSafe() async throws {
        while let order = orders.first {
            try await processOrder(order)
            orders.removeFirst()  // Remove after processing
        }
    }
}
```

## Performance Considerations

### Task Creation Overhead

```swift
// Each Task creation has ~1-2 microsecond overhead
// DO NOT create tasks in tight loops for trivial work

// BAD: Task per element for tiny work
for item in items {
    Task { transform(item) }  // Massive overhead for simple transform
}

// GOOD: Batch or use TaskGroup
await withTaskGroup(of: Void.self) { group in
    for chunk in items.chunks(ofCount: 100) {
        group.addTask {
            for item in chunk {
                transform(item)
            }
        }
    }
}
```

### Actor Contention

```swift
// BAD: Fine-grained actor with many callers
actor Counter {
    var count = 0
    func increment() { count += 1 }
}

// If 1000 tasks all await counter.increment(), they serialize
// Total time = 1000 * (time per increment + scheduling overhead)

// BETTER: Batch operations
actor Counter {
    var count = 0
    func incrementBy(_ n: Int) { count += n }
}

// Or use different architecture:
// Partition state across multiple actors
// Use TaskGroup to aggregate results
```

### When NOT to Use async/await

```swift
// 1. Pure synchronous computation
func add(_ a: Int, _ b: Int) -> Int { a + b }  // Don't make this async

// 2. Simple property access
struct User {
    let name: String  // Don't make this an async property
}

// 3. Performance-critical inner loops
// async/await has overhead from potential suspension points
// For tight numerical loops, stay synchronous

// 4. When you need precise timing control
// async/await uses cooperative scheduling — no real-time guarantees
// For audio/video processing, use dedicated threads/queues
```

### Memory Considerations

```swift
// Each Task captures its closure's context
// Large captures = large memory per task

// BAD: Capturing large data in many tasks
let bigData = loadGigabyteFile()
await withTaskGroup(of: Void.self) { group in
    for i in 0..<1000 {
        group.addTask {
            process(bigData, index: i)  // Each task holds reference to bigData
        }
    }
}

// BETTER: Pass slices or references
await withTaskGroup(of: Void.self) { group in
    let chunks = bigData.chunked(into: 1000)
    for chunk in chunks {
        group.addTask {
            process(chunk)  // Each task only holds its chunk
        }
    }
}
```

## Complete Example: Modern ViewModel Pattern

```swift
@MainActor
@Observable
final class ItemListViewModel {
    // State
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    // Dependencies
    private let repository: ItemRepository
    private let cache: CacheManager<String, [Item]>

    // Task management
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(repository: ItemRepository) {
        self.repository = repository
        self.cache = CacheManager(maxAge: .minutes(5))
    }

    func loadItems() {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            error = nil
            defer { isLoading = false }

            do {
                // Try cache first
                if let cached = await cache.get("all") {
                    items = cached
                    return
                }

                let fetched = try await repository.fetchAll()
                guard !Task.isCancelled else { return }

                items = fetched
                await cache.set("all", value: fetched)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
        }
    }

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            loadItems()
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isLoading = true
            defer { isLoading = false }

            do {
                items = try await repository.search(query: query)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
        }
    }

    func deleteItem(_ item: Item) {
        Task {
            do {
                try await repository.delete(item)
                items.removeAll { $0.id == item.id }
                await cache.invalidate("all")
            } catch {
                self.error = error
            }
        }
    }

    func refresh() async {
        await cache.invalidateAll()
        loadItems()
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
    }
}
```
