# Mocking & Test Doubles Reference

## Test Double Types

| Type | Purpose | Example |
|------|---------|---------|
| **Dummy** | Passed but never used | Empty conformance to fill a parameter |
| **Stub** | Returns predetermined values | `MockAPI` with hardcoded responses |
| **Spy** | Records calls for verification | Tracks `callCount`, `receivedArgs` |
| **Mock** | Spy + verification of expectations | Asserts specific calls were made |
| **Fake** | Working implementation (simplified) | In-memory database instead of real DB |

## Protocol-Based Mocking (Primary Pattern)

### Step 1: Define Protocol

```swift
protocol UserRepositoryProtocol: Sendable {
    func fetchUser(id: String) async throws -> User
    func saveUser(_ user: User) async throws
    func deleteUser(id: String) async throws
    func fetchAll() async throws -> [User]
}
```

### Step 2: Production Implementation

```swift
final class UserRepository: UserRepositoryProtocol {
    private let apiClient: APIClientProtocol
    private let cache: CacheProtocol

    init(apiClient: APIClientProtocol, cache: CacheProtocol) {
        self.apiClient = apiClient
        self.cache = cache
    }

    func fetchUser(id: String) async throws -> User {
        if let cached = try? await cache.get(key: "user_\(id)", as: User.self) {
            return cached
        }
        let user = try await apiClient.request(.getUser(id: id))
        try? await cache.set(key: "user_\(id)", value: user)
        return user
    }

    func saveUser(_ user: User) async throws {
        try await apiClient.request(.createUser(user))
    }

    func deleteUser(id: String) async throws {
        try await apiClient.request(.deleteUser(id: id))
    }

    func fetchAll() async throws -> [User] {
        try await apiClient.request(.listUsers)
    }
}
```

### Step 3: Mock (Spy Pattern)

```swift
final class MockUserRepository: UserRepositoryProtocol, @unchecked Sendable {
    // MARK: - fetchUser
    var fetchUserResult: Result<User, Error> = .failure(MockError.notConfigured)
    var fetchUserCallCount = 0
    var fetchUserReceivedIDs: [String] = []

    func fetchUser(id: String) async throws -> User {
        fetchUserCallCount += 1
        fetchUserReceivedIDs.append(id)
        return try fetchUserResult.get()
    }

    // MARK: - saveUser
    var saveUserResult: Result<Void, Error> = .success(())
    var saveUserCallCount = 0
    var saveUserReceivedUsers: [User] = []

    func saveUser(_ user: User) async throws {
        saveUserCallCount += 1
        saveUserReceivedUsers.append(user)
        try saveUserResult.get()
    }

    // MARK: - deleteUser
    var deleteUserResult: Result<Void, Error> = .success(())
    var deleteUserCallCount = 0
    var deleteUserReceivedIDs: [String] = []

    func deleteUser(id: String) async throws {
        deleteUserCallCount += 1
        deleteUserReceivedIDs.append(id)
        try deleteUserResult.get()
    }

    // MARK: - fetchAll
    var fetchAllResult: Result<[User], Error> = .success([])
    var fetchAllCallCount = 0

    func fetchAll() async throws -> [User] {
        fetchAllCallCount += 1
        return try fetchAllResult.get()
    }

    // MARK: - Reset
    func reset() {
        fetchUserCallCount = 0
        fetchUserReceivedIDs = []
        saveUserCallCount = 0
        saveUserReceivedUsers = []
        deleteUserCallCount = 0
        deleteUserReceivedIDs = []
        fetchAllCallCount = 0
    }
}

enum MockError: Error {
    case notConfigured
}
```

### Step 4: Use in Tests

```swift
import Testing
@testable import MyApp

@Suite("UserViewModel")
struct UserViewModelTests {
    let sut: UserViewModel
    let mockRepo: MockUserRepository

    init() {
        mockRepo = MockUserRepository()
        sut = UserViewModel(repository: mockRepo)
    }

    @Test("Loads user on appear")
    func loadUser() async throws {
        mockRepo.fetchUserResult = .success(User.fixture)

        await sut.loadUser(id: "123")

        #expect(sut.user?.name == "Test User")
        #expect(mockRepo.fetchUserCallCount == 1)
        #expect(mockRepo.fetchUserReceivedIDs == ["123"])
    }

    @Test("Shows error on load failure")
    func loadUserError() async {
        mockRepo.fetchUserResult = .failure(APIError.notFound)

        await sut.loadUser(id: "invalid")

        #expect(sut.user == nil)
        #expect(sut.errorMessage == "User not found")
    }

    @Test("Saves user and shows confirmation")
    func saveUser() async throws {
        let user = User.fixture
        sut.user = user

        await sut.saveChanges()

        #expect(mockRepo.saveUserCallCount == 1)
        #expect(mockRepo.saveUserReceivedUsers.first?.id == user.id)
        #expect(sut.showSaveConfirmation)
    }
}
```

## Dummy

```swift
// When you need to satisfy a parameter but don't care about it
struct DummyLogger: LoggerProtocol {
    func log(_ message: String, level: LogLevel) { }
    func error(_ error: Error) { }
}

// Usage: when testing something that requires a logger but you don't care about logs
let sut = PaymentService(logger: DummyLogger(), api: mockAPI)
```

## Fake

```swift
// Working but simplified implementation
final class FakeUserRepository: UserRepositoryProtocol, @unchecked Sendable {
    private var storage: [String: User] = [:]

    func fetchUser(id: String) async throws -> User {
        guard let user = storage[id] else {
            throw RepositoryError.notFound
        }
        return user
    }

    func saveUser(_ user: User) async throws {
        storage[user.id] = user
    }

    func deleteUser(id: String) async throws {
        storage.removeValue(forKey: id)
    }

    func fetchAll() async throws -> [User] {
        Array(storage.values)
    }
}

// Useful when you need real CRUD behavior without a real database
@Test("User lifecycle with fake repository")
func userLifecycle() async throws {
    let repo = FakeUserRepository()
    let user = User.fixture

    try await repo.saveUser(user)
    let fetched = try await repo.fetchUser(id: user.id)
    #expect(fetched.name == user.name)

    try await repo.deleteUser(id: user.id)
    await #expect(throws: RepositoryError.notFound) {
        try await repo.fetchUser(id: user.id)
    }
}
```

## URLProtocol Network Mocking

The correct way to mock network requests. Do NOT mock URLSession directly.

### MockURLProtocol

```swift
final class MockURLProtocol: URLProtocol {
    // Handler returns response + data for any request
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // Track requests for verification
    nonisolated(unsafe) static var receivedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.receivedRequests.append(request)

        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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

    static func reset() {
        requestHandler = nil
        receivedRequests = []
    }
}
```

### Using in Tests

```swift
@Suite("APIClient")
struct APIClientTests {
    let sut: APIClient
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sut = APIClient(session: session)
    }

    @Test("Fetches user successfully")
    func fetchUser() async throws {
        let expectedUser = User(id: "1", name: "Alice", email: "alice@test.com")

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/users/1")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = try JSONEncoder().encode(expectedUser)
            return (response, data)
        }

        let user = try await sut.fetchUser(id: "1")
        #expect(user.name == "Alice")
    }

    @Test("Handles 404 error")
    func notFoundError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: APIError.notFound) {
            try await sut.fetchUser(id: "nonexistent")
        }
    }

    @Test("Handles network failure")
    func networkFailure() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: APIError.networkError) {
            try await sut.fetchUser(id: "1")
        }
    }

    @Test("Sends correct headers")
    func requestHeaders() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(User.fixture))
        }

        sut.setAuthToken("token123")
        _ = try await sut.fetchUser(id: "1")
    }
}
```

## Testing async/await Code

```swift
@Suite("DataLoader")
struct DataLoaderTests {
    @Test("Loads data concurrently")
    func concurrentLoad() async throws {
        let loader = DataLoader(api: mockAPI)

        async let users = loader.fetchUsers()
        async let posts = loader.fetchPosts()

        let (fetchedUsers, fetchedPosts) = try await (users, posts)
        #expect(fetchedUsers.count > 0)
        #expect(fetchedPosts.count > 0)
    }

    @Test("Cancellation stops loading")
    func cancellation() async {
        let loader = DataLoader(api: SlowMockAPI())

        let task = Task {
            try await loader.fetchUsers()
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Timeout after delay")
    @available(iOS 16, *)
    func timeout() async {
        let clock = ContinuousClock()
        let loader = DataLoader(api: mockAPI, timeout: .seconds(1))

        await #expect(throws: DataLoaderError.timeout) {
            try await loader.fetchWithTimeout()
        }
    }
}
```

## Testing Combine Publishers

```swift
import Combine
import Testing
@testable import MyApp

@Suite("SearchViewModel Combine")
struct SearchViewModelCombineTests {
    @Test("Search publishes filtered results")
    func searchResults() async {
        let viewModel = SearchViewModel(api: MockSearchAPI())

        // Collect published values
        var results: [[SearchResult]] = []
        let cancellable = viewModel.$results.sink { results.append($0) }

        viewModel.searchText = "swift"

        // Give debounce time to fire
        try? await Task.sleep(for: .milliseconds(500))

        #expect(results.last?.isEmpty == false)
        cancellable.cancel()
    }

    @Test("Debounces rapid input")
    func debounce() async {
        let mockAPI = MockSearchAPI()
        let viewModel = SearchViewModel(api: mockAPI)

        let cancellable = viewModel.$results.sink { _ in }

        // Rapid typing
        viewModel.searchText = "s"
        viewModel.searchText = "sw"
        viewModel.searchText = "swi"
        viewModel.searchText = "swift"

        try? await Task.sleep(for: .milliseconds(500))

        // Should only call API once (debounced)
        #expect(mockAPI.searchCallCount == 1)
        cancellable.cancel()
    }
}
```

### XCTest + Combine (Expectation Pattern)

```swift
final class CombineXCTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        cancellables = []
    }

    func testPublisherEmitsValue() async {
        let exp = expectation(description: "Value received")
        let publisher = Just("Hello")

        publisher
            .sink { value in
                XCTAssertEqual(value, "Hello")
                exp.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 1)
    }

    func testPublisherCompletes() async {
        let exp = expectation(description: "Completed")

        somePublisher()
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        exp.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 5)
    }
}
```

## Testing SwiftUI Views

### ViewInspector (Third-Party)

```swift
// Package: https://github.com/nicklama/ViewInspector
import ViewInspector
import Testing
@testable import MyApp

@Suite("ProfileView")
struct ProfileViewTests {
    @Test("Displays user name")
    func displaysName() throws {
        let user = User.fixture
        let view = ProfileView(user: user)

        let name = try view.inspect().find(text: "Test User")
        #expect(name != nil)
    }

    @Test("Shows edit button for own profile")
    func editButton() throws {
        let view = ProfileView(user: User.fixture, isOwnProfile: true)

        let button = try view.inspect().find(button: "Edit Profile")
        #expect(button != nil)
    }

    @Test("Hides edit button for other profiles")
    func noEditButton() throws {
        let view = ProfileView(user: User.fixture, isOwnProfile: false)

        XCTAssertThrowsError(try view.inspect().find(button: "Edit Profile"))
    }
}
```

### Snapshot Testing (swift-snapshot-testing)

Point-Free's snapshot testing library. Compare views against reference images.

```swift
// Package: https://github.com/pointfreeco/swift-snapshot-testing
import SnapshotTesting
import SwiftUI
import XCTest
@testable import MyApp

final class ProfileViewSnapshotTests: XCTestCase {
    func testProfileView() {
        let view = ProfileView(user: User.fixture)
        let vc = UIHostingController(rootView: view)

        assertSnapshot(of: vc, as: .image(on: .iPhone13))
    }

    func testProfileViewDarkMode() {
        let view = ProfileView(user: User.fixture)
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = .dark

        assertSnapshot(of: vc, as: .image(on: .iPhone13))
    }

    func testProfileViewAccessibility() {
        let view = ProfileView(user: User.fixture)
        let vc = UIHostingController(rootView: view)

        // Extra large text
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        assertSnapshot(of: vc, as: .image(on: .iPhone13, traits: traits))
    }

    func testProfileViewLandscape() {
        let view = ProfileView(user: User.fixture)
        let vc = UIHostingController(rootView: view)

        assertSnapshot(of: vc, as: .image(on: .iPadPro12_9(.landscape)))
    }

    // Snapshot as text dump (no image comparison)
    func testProfileViewHierarchy() {
        let view = ProfileView(user: User.fixture)
        assertSnapshot(of: view, as: .dump)
    }

    // JSON snapshot of Codable model
    func testUserJSON() {
        let user = User.fixture
        assertSnapshot(of: user, as: .json)
    }
}
```

### Device Configurations for Snapshots

```swift
// Common device configs
.image(on: .iPhoneSe)
.image(on: .iPhone13)
.image(on: .iPhone13Mini)
.image(on: .iPhone13Pro)
.image(on: .iPhone13ProMax)
.image(on: .iPadPro11)
.image(on: .iPadPro12_9)
.image(on: .iPadPro12_9(.landscape))

// Custom size
.image(size: CGSize(width: 375, height: 200))

// With traits
.image(on: .iPhone13, traits: UITraitCollection(userInterfaceStyle: .dark))
```

### Recording Mode

First run generates reference snapshots. Subsequent runs compare against them.

```swift
// Force re-record (set to true, run once, then set back to false)
// isRecording = true

// Or via environment variable (CI-friendly)
// SNAPSHOT_ARTIFACTS=/path/to/artifacts
```

## Testing SwiftData

```swift
import SwiftData
import Testing
@testable import MyApp

@Suite("SwiftData: TodoItem")
struct TodoItemDataTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: TodoItem.self, configurations: config)
        context = ModelContext(container)
    }

    @Test("Insert and fetch")
    func insertAndFetch() throws {
        let item = TodoItem(title: "Buy milk", isCompleted: false)
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<TodoItem>()
        let items = try context.fetch(descriptor)

        #expect(items.count == 1)
        #expect(items.first?.title == "Buy milk")
    }

    @Test("Update item")
    func updateItem() throws {
        let item = TodoItem(title: "Buy milk", isCompleted: false)
        context.insert(item)
        try context.save()

        item.isCompleted = true
        try context.save()

        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.isCompleted }
        )
        let completed = try context.fetch(descriptor)
        #expect(completed.count == 1)
    }

    @Test("Delete item")
    func deleteItem() throws {
        let item = TodoItem(title: "Buy milk", isCompleted: false)
        context.insert(item)
        try context.save()

        context.delete(item)
        try context.save()

        let descriptor = FetchDescriptor<TodoItem>()
        let items = try context.fetch(descriptor)
        #expect(items.isEmpty)
    }

    @Test("Fetch with sort")
    func fetchWithSort() throws {
        let items = [
            TodoItem(title: "C Task", isCompleted: false),
            TodoItem(title: "A Task", isCompleted: false),
            TodoItem(title: "B Task", isCompleted: false),
        ]
        items.forEach { context.insert($0) }
        try context.save()

        var descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.title)]
        )
        let sorted = try context.fetch(descriptor)
        #expect(sorted.map(\.title) == ["A Task", "B Task", "C Task"])
    }
}
```

## Testing Core Data

```swift
import CoreData
import Testing
@testable import MyApp

@Suite("Core Data: Task Entity")
struct TaskEntityTests {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    init() {
        container = NSPersistentContainer(name: "MyApp")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType  // In-memory store
        // Alternative: description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]

        let expectation = XCTestExpectation(description: "Store loaded")
        container.loadPersistentStores { _, error in
            if let error { fatalError("Failed to load store: \(error)") }
            expectation.fulfill()
        }

        context = container.newBackgroundContext()
    }

    @Test("Create and fetch task")
    func createAndFetch() throws {
        try context.performAndWait {
            let task = TaskEntity(context: context)
            task.title = "Test Task"
            task.createdAt = Date()
            try context.save()

            let request: NSFetchRequest<TaskEntity> = TaskEntity.fetchRequest()
            let tasks = try context.fetch(request)
            #expect(tasks.count == 1)
            #expect(tasks.first?.title == "Test Task")
        }
    }
}
```

## Macro-Based Mock Generation

### Spyable (Recommended)

```swift
// Package: https://github.com/Matejkob/swift-spyable
// Automatically generates spy implementations from protocols

@Spyable
protocol UserServiceProtocol {
    func fetchUser(id: String) async throws -> User
    func saveUser(_ user: User) async throws
}

// Generated code (automatic):
// class UserServiceProtocolSpy: UserServiceProtocol {
//     var fetchUserIdCallsCount = 0
//     var fetchUserIdCalled: Bool { fetchUserIdCallsCount > 0 }
//     var fetchUserIdReceivedId: String?
//     var fetchUserIdReceivedInvocations: [String] = []
//     var fetchUserIdReturnValue: User!
//     var fetchUserIdThrowableError: Error?
//     var fetchUserIdClosure: ((String) async throws -> User)?
//     ...
// }

// Usage in tests:
@Test func fetchUser() async throws {
    let spy = UserServiceProtocolSpy()
    spy.fetchUserIdReturnValue = User.fixture

    let sut = ProfileViewModel(service: spy)
    await sut.load()

    #expect(spy.fetchUserIdCallsCount == 1)
    #expect(spy.fetchUserIdReceivedId == "current-user-id")
}
```

### Mockable

```swift
// Package: https://github.com/nicklama/Mockable
// Similar concept with different API

@Mockable
protocol AuthServiceProtocol {
    func login(email: String, password: String) async throws -> Token
    func logout() async
}

// Usage:
let mock = MockAuthServiceProtocol()
given(mock).login(email: .any, password: .any).willReturn(Token.fixture)

let sut = LoginViewModel(auth: mock)
await sut.login()

verify(mock).login(email: .value("test@test.com"), password: .any).called(1)
```

## Test Fixtures and Factories

### Extension-Based Fixtures

```swift
extension User {
    static var fixture: User {
        User(id: "test-id", name: "Test User", email: "test@example.com", age: 30)
    }

    static func fixture(
        id: String = "test-id",
        name: String = "Test User",
        email: String = "test@example.com",
        age: Int = 30
    ) -> User {
        User(id: id, name: name, email: email, age: age)
    }
}

extension Order {
    static var fixture: Order {
        Order(id: "order-1", items: [.fixture], total: 29.99, status: .pending)
    }
}

extension OrderItem {
    static var fixture: OrderItem {
        OrderItem(id: "item-1", name: "Widget", price: 9.99, quantity: 1)
    }
}
```

### JSON Fixtures

```swift
enum JSONFixtures {
    static var userJSON: Data {
        """
        {
            "id": "test-id",
            "name": "Test User",
            "email": "test@example.com",
            "age": 30
        }
        """.data(using: .utf8)!
    }

    static var usersListJSON: Data {
        """
        [
            {"id": "1", "name": "Alice", "email": "alice@test.com", "age": 25},
            {"id": "2", "name": "Bob", "email": "bob@test.com", "age": 30}
        ]
        """.data(using: .utf8)!
    }

    static var errorJSON: Data {
        """
        {"error": "not_found", "message": "User not found"}
        """.data(using: .utf8)!
    }
}
```

### Bundle-Based Fixtures

```swift
extension Bundle {
    static var test: Bundle { Bundle(for: BundleToken.self) }
}
private class BundleToken {}

func loadFixture(_ name: String, extension ext: String = "json") -> Data {
    let url = Bundle.test.url(forResource: name, withExtension: ext)!
    return try! Data(contentsOf: url)
}

// Usage:
let userData = loadFixture("user_response")
```

## Testing @MainActor Code

```swift
@Suite("ProfileViewModel")
struct ProfileViewModelTests {
    @Test("Updates name on main actor")
    @MainActor
    func updateName() async {
        let viewModel = ProfileViewModel()  // @MainActor class
        viewModel.name = "New Name"
        #expect(viewModel.name == "New Name")
    }
}
```

## Clock Injection for Time-Dependent Code

```swift
// Production code
struct RetryService<C: Clock> where C.Duration == Duration {
    let clock: C
    let maxRetries: Int

    func execute(_ operation: () async throws -> Void) async throws {
        for attempt in 0..<maxRetries {
            do {
                try await operation()
                return
            } catch {
                if attempt < maxRetries - 1 {
                    try await clock.sleep(for: .seconds(pow(2, Double(attempt))))
                }
            }
        }
    }
}

// Test with controllable clock
@Test("Retries with exponential backoff")
func retryBackoff() async throws {
    let clock = TestClock()  // From swift-clocks package
    let service = RetryService(clock: clock, maxRetries: 3)

    var attempts = 0
    let task = Task {
        try await service.execute {
            attempts += 1
            if attempts < 3 { throw TestError.retry }
        }
    }

    await clock.advance(by: .seconds(1))  // First retry delay
    await clock.advance(by: .seconds(2))  // Second retry delay

    try await task.value
    #expect(attempts == 3)
}
```
