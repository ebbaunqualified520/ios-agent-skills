# Actors, @MainActor, GlobalActor, and Sendable Reference

## Actor Fundamentals

### Declaring an Actor

```swift
// Actor — reference type with built-in serial access
actor BankAccount {
    let id: String
    private(set) var balance: Decimal

    init(id: String, initialBalance: Decimal) {
        self.id = id
        self.balance = initialBalance
    }

    func deposit(_ amount: Decimal) {
        balance += amount
    }

    func withdraw(_ amount: Decimal) throws {
        guard balance >= amount else {
            throw BankError.insufficientFunds
        }
        balance -= amount
    }
}

// Usage — requires await to cross isolation boundary
let account = BankAccount(id: "123", initialBalance: 1000)
try await account.withdraw(500)
let currentBalance = await account.balance
```

### Actor Isolation Rules

```swift
actor DataStore {
    var items: [Item] = []

    // Methods on an actor are isolated by default
    // They can access actor state directly without await
    func addItem(_ item: Item) {
        items.append(item)  // No await needed — same isolation domain
    }

    func processAll() async {
        for item in items {
            await externalProcess(item)  // await needed for external async calls
        }
    }

    // Accessing from outside requires await
    // let store = DataStore()
    // await store.addItem(item)          // await required
    // let count = await store.items.count // await required
}
```

### Actor Properties and Subscripts

```swift
actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]

    // Computed properties are actor-isolated
    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    func set(_ value: Value, for key: Key) {
        storage[key] = value
    }

    func removeAll() {
        storage.removeAll()
    }
}

// From outside — all access requires await
let cache = Cache<String, Data>()
await cache.set(data, for: "key")
let value = await cache["key"]
let empty = await cache.isEmpty
```

## Actor Reentrancy

### Understanding Reentrancy

```swift
// Actors are REENTRANT — state can change across await points
actor ImageDownloader {
    private var cache: [URL: UIImage] = [:]

    // BUG: Race condition due to reentrancy
    func image(from url: URL) async throws -> UIImage {
        if let cached = cache[url] {
            return cached
        }

        // Suspension point — another call to image(from:) can start here
        let (data, _) = try await URLSession.shared.data(from: url)
        let image = UIImage(data: data)!

        // By the time we get here, another task might have already cached the image
        // This is OK here (just overwrites), but could be problematic in other cases
        cache[url] = image
        return image
    }

    // FIXED: Track in-progress downloads to avoid duplicates
    private var inProgress: [URL: Task<UIImage, Error>] = [:]

    func imageDeduped(from url: URL) async throws -> UIImage {
        if let cached = cache[url] {
            return cached
        }

        if let existing = inProgress[url] {
            return try await existing.value
        }

        let task = Task {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)!
        }

        inProgress[url] = task

        do {
            let image = try await task.value
            cache[url] = image
            inProgress[url] = nil
            return image
        } catch {
            inProgress[url] = nil
            throw error
        }
    }
}
```

### Reentrancy Patterns

```swift
actor StateMachine {
    enum State { case idle, loading, loaded(Data), failed(Error) }
    private(set) var state: State = .idle

    func load() async {
        // Check precondition BEFORE suspension
        guard case .idle = state else { return }

        state = .loading

        // SUSPENSION POINT — state could be modified by another caller
        // But we set .loading above, so other callers will see .loading and return

        do {
            let data = try await fetchData()
            // Re-check state after suspension — it might have been cancelled
            if case .loading = state {
                state = .loaded(data)
            }
        } catch {
            state = .failed(error)
        }
    }

    func reset() {
        state = .idle
    }
}
```

## @MainActor

### On Functions and Properties

```swift
// Single function on MainActor
@MainActor
func updateUI(with data: Data) {
    label.text = String(data: data, encoding: .utf8)
    activityIndicator.stopAnimating()
}

// Call from async context
Task {
    let data = try await fetchData()
    await updateUI(with: data)  // await because crossing to MainActor
}

// MainActor property
class ViewController: UIViewController {
    @MainActor var displayText: String = "" {
        didSet { label.text = displayText }
    }
}
```

### On Classes

```swift
// Entire class isolated to MainActor
@MainActor
final class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: ItemRepository

    init(repository: ItemRepository) {
        self.repository = repository
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await repository.fetchAll()
        } catch {
            self.error = error
        }
    }

    // nonisolated to opt out of MainActor for non-UI work
    nonisolated func formatItem(_ item: Item) -> String {
        "\(item.name) - \(item.price)"
    }
}
```

### MainActor.run

```swift
// Explicitly run a block on MainActor
func processInBackground() async {
    let data = await heavyComputation()

    // Switch to MainActor for UI update
    await MainActor.run {
        self.label.text = "Done: \(data.count) items"
        self.progressView.isHidden = true
    }
}

// MainActor.run returns a value
func fetchAndFormat() async -> String {
    let data = await fetchData()
    return await MainActor.run {
        formatter.string(from: data)
    }
}

// Prefer @MainActor annotation over MainActor.run when possible
// MainActor.run is useful for one-off UI updates in otherwise non-MainActor code
```

### SwiftUI and MainActor

```swift
// SwiftUI Views are implicitly @MainActor (Swift 5.10+)
struct ContentView: View {
    @State private var items: [Item] = []

    var body: some View {
        List(items) { item in
            Text(item.name)
        }
        .task {
            // .task runs on MainActor (since the view is MainActor)
            items = await fetchItems()
        }
    }
}

// @Observable is MainActor-isolated by default in SwiftUI context
@Observable
@MainActor
final class AppState {
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }

    func signIn(email: String, password: String) async throws {
        currentUser = try await authService.signIn(email: email, password: password)
    }
}
```

## GlobalActor Protocol

### Creating a Custom GlobalActor

```swift
// Define a global actor for database operations
@globalActor
actor DatabaseActor {
    static let shared = DatabaseActor()
}

// Use it to isolate functions to the database actor
@DatabaseActor
func saveToDB(_ item: Item) async throws {
    try await db.insert(item)
}

@DatabaseActor
func fetchFromDB(id: String) async throws -> Item {
    try await db.fetch(id: id)
}

// Isolate entire class
@DatabaseActor
final class DatabaseRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func save(_ item: Item) async throws {
        try await db.insert(item)
    }

    func fetch(id: String) async throws -> Item {
        try await db.fetch(id: id)
    }
}
```

### GlobalActor Protocol Definition

```swift
// GlobalActor protocol
protocol GlobalActor {
    associatedtype ActorType: Actor
    static var shared: ActorType { get }
}

// MainActor conforms to GlobalActor
@globalActor
final actor MainActor: GlobalActor {
    static let shared = MainActor()
    // ...
}
```

## nonisolated Keyword

### Opting Out of Actor Isolation

```swift
actor UserManager {
    let apiKey: String  // let properties are implicitly nonisolated
    var users: [User] = []

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // This can be called without await because it doesn't access actor state
    nonisolated func makeURL(for endpoint: String) -> URL {
        URL(string: "https://api.example.com/\(endpoint)?key=\(apiKey)")!
    }

    // Conforming to protocol from outside actor
    // Hashable/Equatable often need nonisolated
    nonisolated var description: String {
        "UserManager(apiKey: \(apiKey))"
    }
}

// Usage — no await needed for nonisolated members
let manager = UserManager(apiKey: "abc")
let url = manager.makeURL(for: "users")  // No await
let desc = manager.description            // No await
let key = manager.apiKey                  // No await (let property)
```

### nonisolated with @MainActor Classes

```swift
@MainActor
final class ViewModel: ObservableObject {
    @Published var data: [Item] = []

    // Protocol conformance that doesn't need MainActor
    nonisolated func hash(into hasher: inout Hasher) {
        // Can only access nonisolated properties here
    }

    // Utility that doesn't touch UI state
    nonisolated func validate(input: String) -> Bool {
        !input.isEmpty && input.count <= 100
    }
}
```

### nonisolated(unsafe) — Swift 6

```swift
// For global/static mutable state that you know is safe
// Used as escape hatch during Swift 6 migration
nonisolated(unsafe) var globalLogger = Logger()

// Only use when you can guarantee thread safety through other means
// (e.g., the variable is only written once during initialization)
```

## Sendable Protocol

### Automatic Sendable Conformance

```swift
// Value types with all Sendable members — automatically Sendable
struct Point: Sendable {
    let x: Double
    let y: Double
}

// Enums with Sendable associated values — automatically Sendable
enum Result<T: Sendable>: Sendable {
    case success(T)
    case failure(Error)  // Error is Sendable
}

// Tuples of Sendable types are Sendable
// Optional<Sendable> is Sendable
// Array<Sendable>, Dictionary<Sendable, Sendable>, Set<Sendable> are Sendable
```

### Making Reference Types Sendable

```swift
// Option 1: final class with only let (immutable) stored properties
final class APIConfig: Sendable {
    let baseURL: URL
    let apiKey: String
    let timeout: TimeInterval

    init(baseURL: URL, apiKey: String, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

// Option 2: Actors are implicitly Sendable
actor SessionManager: Sendable {
    // Actor isolation provides thread safety
    var token: String?
    func setToken(_ t: String) { token = t }
}

// Option 3: @unchecked Sendable — you guarantee safety
final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.withLock { _count }
    }

    func increment() {
        lock.withLock { _count += 1 }
    }
}
```

### @Sendable Closures

```swift
// Closures that cross isolation boundaries must be @Sendable
actor Processor {
    func process(transform: @Sendable (Data) -> Data) async -> Data {
        let raw = await fetchRawData()
        return transform(raw)
    }
}

// @Sendable closures cannot capture mutable local variables
var count = 0
let task = Task { @Sendable in
    // Cannot capture mutable 'count' — compiler error in strict mode
    // count += 1
}

// Fix: capture as let or use actor
let currentCount = count
let task2 = Task { @Sendable in
    print(currentCount)  // OK — capturing immutable value
}

// Task closures are implicitly @Sendable
Task {
    // This closure is @Sendable
    // Cannot capture mutable local variables
}

// @Sendable function types
typealias Transform = @Sendable (Data) -> Data
typealias AsyncTransform = @Sendable (Data) async throws -> Data
```

### @unchecked Sendable — Escape Hatch

```swift
// When you need to make a non-Sendable type work across boundaries
// You take responsibility for thread safety

// Wrapping a non-Sendable type you don't own
final class SendableFormatter: @unchecked Sendable {
    private let formatter: DateFormatter  // DateFormatter is not Sendable
    private let lock = NSLock()

    init() {
        formatter = DateFormatter()
        formatter.dateStyle = .medium
    }

    func string(from date: Date) -> String {
        lock.withLock {
            formatter.string(from: date)
        }
    }
}

// When to use @unchecked Sendable:
// 1. Wrapping thread-safe types that haven't adopted Sendable yet
// 2. Types using locks/queues for internal synchronization
// 3. Objective-C types that are thread-safe but can't be marked Sendable
// 4. During migration as a temporary measure

// CAUTION: If you're wrong about thread safety, you get data races
// No compiler help — you're on your own
```

### Sendable Conformance Strategies

```swift
// Strategy 1: Make everything value types (preferred)
struct UserProfile: Sendable {
    let id: UUID
    let name: String
    let preferences: Preferences  // Preferences must also be Sendable
}

// Strategy 2: Use actors for shared mutable state
actor UserSession: Sendable {
    var profile: UserProfile?
    var token: String?
}

// Strategy 3: Immutable reference types
final class Route: Sendable {
    let path: String
    let method: HTTPMethod
    let handler: @Sendable (Request) async throws -> Response
}

// Strategy 4: Protocol with Sendable constraint
protocol Repository: Sendable {
    associatedtype Entity: Sendable
    func fetch(id: String) async throws -> Entity
    func save(_ entity: Entity) async throws
}

// Strategy 5: Generic Sendable wrapper
struct SendableBox<T: Sendable>: Sendable {
    let value: T
}
```

### @preconcurrency for Legacy Code

```swift
// Import frameworks that haven't adopted Sendable yet
@preconcurrency import SomeLegacyFramework

// Suppress Sendable warnings for specific types
@preconcurrency
protocol LegacyDelegate: AnyObject {
    func didComplete(with result: LegacyResult)
}

// @preconcurrency on import tells the compiler:
// "Trust that types from this module are safe to use across concurrency boundaries"
// This silences Sendable warnings for that module's types

// Use during migration — remove when the framework adds Sendable support
```

## Distributed Actors (Advanced)

```swift
// For cross-process/cross-network communication
distributed actor Player {
    typealias ActorSystem = SomeActorSystem

    distributed var name: String
    distributed var score: Int

    distributed func makeMove(_ move: Move) throws -> GameState {
        // ...
    }
}

// Calling distributed actors always requires try+await
// because the call may fail due to network issues
let player: Player = ...
let state = try await player.makeMove(.attack)
```

## Common Actor Patterns

### Actor-Based Service

```swift
actor NetworkService {
    private let session: URLSession
    private var activeRequests: [UUID: Task<Data, Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: URL) async throws -> Data {
        let id = UUID()
        let task = Task {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw APIError.badStatus
            }
            return data
        }

        activeRequests[id] = task

        do {
            let data = try await task.value
            activeRequests[id] = nil
            return data
        } catch {
            activeRequests[id] = nil
            throw error
        }
    }

    func cancelAll() {
        activeRequests.values.forEach { $0.cancel() }
        activeRequests.removeAll()
    }
}
```

### Actor Isolation and Protocol Conformance

```swift
// Actors can conform to protocols
// Methods may need nonisolated or async adjustments

protocol Describable {
    var description: String { get }
}

actor Counter: Describable {
    var count = 0

    func increment() { count += 1 }

    // Protocol requires synchronous property — use nonisolated
    // Can only access nonisolated/let properties
    nonisolated var description: String {
        "Counter instance"  // Cannot access 'count' here
    }
}

// For protocols requiring access to actor state:
protocol DataProvider {
    func fetchData() async throws -> [Data]
}

actor APIProvider: DataProvider {
    private var cache: [Data] = []

    func fetchData() async throws -> [Data] {
        // Can access actor state because method is async
        if !cache.isEmpty { return cache }
        cache = try await loadFromNetwork()
        return cache
    }
}
```

### Actor vs Class Comparison

```swift
// Class — no protection, data races possible
class UnsafeCounter {
    var count = 0
    func increment() { count += 1 }  // Data race if called from multiple threads
}

// Class + Lock — manual protection, error-prone
class LockedCounter {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func increment() { lock.withLock { _count += 1 } }
}

// Class + Serial Queue — GCD approach
class QueueCounter {
    private let queue = DispatchQueue(label: "counter")
    private var _count = 0
    var count: Int { queue.sync { _count } }
    func increment() { queue.sync { _count += 1 } }
}

// Actor — compiler-enforced protection, no boilerplate
actor SafeCounter {
    var count = 0
    func increment() { count += 1 }
}

// Actor wins: less code, compiler-enforced, no deadlock risk
// Use actors for ALL new shared mutable state
```
