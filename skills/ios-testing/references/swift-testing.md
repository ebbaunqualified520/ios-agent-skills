# Swift Testing Framework Reference

## Overview

Swift Testing is Apple's modern test framework (Xcode 16+, Swift 6). It uses macros (`@Test`, `@Suite`), expression-based assertions (`#expect`, `#require`), and struct-based test containers. Tests run in parallel by default.

```swift
import Testing
```

## @Test Macro

### Basic Usage

```swift
@Test func addition() {
    #expect(2 + 2 == 4)
}

@Test("User creation with valid data")
func userCreation() {
    let user = User(name: "Alice", email: "alice@example.com")
    #expect(user.name == "Alice")
}
```

### Async and Throwing Tests

```swift
@Test func fetchUser() async throws {
    let user = try await api.fetchUser(id: "123")
    #expect(user.name == "Alice")
}

@Test func decodingInvalidJSON() throws {
    let data = Data("{}".utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(User.self, from: data)
    }
}
```

### @Test with Traits

```swift
@Test(.tags(.networking), .timeLimit(.minutes(1)))
func slowNetworkRequest() async throws {
    let result = try await api.fetchLargePayload()
    #expect(result.count > 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
func ciOnlyTest() {
    // Runs only on CI
}

@Test(.disabled("Blocked by issue #42"))
func disabledTest() {
    // Won't run, shows as skipped
}

@Test(.bug("https://github.com/org/repo/issues/42", "Intermittent failure"))
func bugLinkedTest() {
    // Links test to a known bug
}
```

## #expect Macro

### Boolean Expressions

```swift
#expect(user.isActive)
#expect(array.count == 3)
#expect(name.hasPrefix("Dr."))
#expect(score >= 0 && score <= 100)
```

### With Custom Messages

```swift
#expect(user.age >= 18, "User must be an adult, got age \(user.age)")
```

### Testing Equality (Shows Diff on Failure)

```swift
#expect(actual == expected)
// Failure output: Expectation failed: (["a", "b"]) == (["a", "c"])
```

### Testing Errors

```swift
// Expect any error
#expect(throws: (any Error).self) {
    try dangerousOperation()
}

// Expect specific error type
#expect(throws: NetworkError.self) {
    try api.fetch(url: invalidURL)
}

// Expect specific error value (Equatable)
#expect(throws: NetworkError.timeout) {
    try api.fetch(url: slowURL)
}

// Inspect thrown error
#expect {
    try api.validate(token: "expired")
} throws: { error in
    guard let authError = error as? AuthError else { return false }
    return authError.code == 401
}

// Expect NO error (implicitly -- just call the throwing function)
@Test func noError() throws {
    try validate(input: "good")  // Test fails if this throws
}
```

### Testing Optionals

```swift
// Don't do this:
#expect(user != nil)

// Do this instead -- #require unwraps and stops test if nil:
let user = try #require(user)
#expect(user.name == "Alice")
```

## #require Macro

`#require` is like `#expect` but stops the test immediately on failure. Essential for unwrapping optionals.

```swift
@Test func userProfile() throws {
    let user = try #require(fetchUser(id: "123"))     // Stops if nil
    let address = try #require(user.address)           // Stops if nil
    #expect(address.city == "San Francisco")
}

// Require a condition
@Test func dataIntegrity() throws {
    let items = loadItems()
    try #require(items.count > 0, "Must have at least one item")
    #expect(items[0].isValid)
}

// Require no error thrown
@Test func configLoading() throws {
    let config = try #require(try loadConfig())
    #expect(config.apiKey.isEmpty == false)
}
```

## confirmation (Async Expectations)

Replaces `XCTestExpectation`. Waits for a callback to be called.

```swift
@Test("Notification triggers handler")
func notificationHandler() async {
    await confirmation("handler called") { confirm in
        let observer = NotificationObserver { _ in
            confirm()
        }
        NotificationCenter.default.post(name: .dataUpdated, object: nil)
        _ = observer  // Keep alive
    }
}

// Expected count
@Test("Delegate receives all page loads")
func delegatePageLoads() async {
    await confirmation("page loaded", expectedCount: 3) { confirm in
        let delegate = MockDelegate(onPageLoad: { confirm() })
        let browser = Browser(delegate: delegate)
        await browser.load(urls: [url1, url2, url3])
    }
}

// Zero expected count (should NOT be called)
@Test("Error handler not called on success")
func noErrorOnSuccess() async {
    await confirmation("error handler", expectedCount: 0) { confirm in
        let handler = ErrorHandler(onError: { _ in confirm() })
        await handler.process(validData)
    }
}
```

## withKnownIssue

Mark tests with known intermittent failures. Test runs but failure is expected and does not fail the suite.

```swift
@Test func flakyNetworkTest() async throws {
    withKnownIssue("Server sometimes returns 503") {
        let result = try await api.fetch()
        #expect(result.status == 200)
    }
}

// Conditional known issue
@Test func platformSpecificTest() {
    withKnownIssue("Fails on iOS 17.0", isIntermittent: true) {
        #expect(feature.isAvailable)
    } when: {
        if #available(iOS 17.1, *) { return false }
        return true
    }
}
```

## Parameterized Tests

Run the same test body with different inputs. Arguments must be `Sendable`.

### Single Parameter

```swift
@Test("Email validation", arguments: [
    "user@example.com",
    "admin@test.org",
    "name+tag@domain.co.uk",
])
func validEmails(email: String) {
    #expect(EmailValidator.isValid(email))
}

@Test("Invalid emails", arguments: [
    "", "not-an-email", "@no-local.com", "no-domain@", "spaces in@email.com",
])
func invalidEmails(email: String) {
    #expect(!EmailValidator.isValid(email))
}
```

### Enum Conforming to CaseIterable

```swift
enum UserRole: CaseIterable, Sendable {
    case admin, editor, viewer
}

@Test("All roles have display names", arguments: UserRole.allCases)
func roleDisplayNames(role: UserRole) {
    #expect(role.displayName.isEmpty == false)
}
```

### Two Parameters (Cartesian Product)

By default, all combinations are tested:

```swift
@Test("Arithmetic operations", arguments: [1, 2, 5, 10], [0, 1, -1])
func arithmetic(a: Int, b: Int) {
    #expect(a + b == b + a)  // Commutativity
}
// Runs 4 x 3 = 12 test cases
```

### Two Parameters (Zipped, 1:1)

```swift
@Test("Known results", arguments: zip(
    [2, 3, 4],
    [4, 9, 16]
))
func squares(input: Int, expected: Int) {
    #expect(input * input == expected)
}
// Runs exactly 3 test cases
```

### Custom Collection

```swift
struct LoginCase: Sendable, CustomTestStringConvertible {
    let email: String
    let password: String
    let shouldSucceed: Bool

    var testDescription: String { "\(email) -> \(shouldSucceed ? "success" : "failure")" }
}

let loginCases: [LoginCase] = [
    LoginCase(email: "user@test.com", password: "Valid1!", shouldSucceed: true),
    LoginCase(email: "", password: "Valid1!", shouldSucceed: false),
    LoginCase(email: "user@test.com", password: "", shouldSucceed: false),
]

@Test("Login scenarios", arguments: loginCases)
func loginScenarios(testCase: LoginCase) async throws {
    let result = await authService.login(email: testCase.email, password: testCase.password)
    #expect(result.isSuccess == testCase.shouldSucceed)
}
```

## @Suite

Group related tests. Use structs (not classes). `init()` replaces `setUp`, `deinit` replaces `tearDown`.

### Basic Suite

```swift
@Suite("UserService")
struct UserServiceTests {
    let sut: UserService
    let mockRepo: MockUserRepository

    init() {
        mockRepo = MockUserRepository()
        sut = UserService(repository: mockRepo)
    }

    @Test("Creates user with valid data")
    func createUser() async throws {
        let user = try await sut.create(name: "Alice", email: "alice@test.com")
        #expect(user.name == "Alice")
        #expect(mockRepo.saveCallCount == 1)
    }

    @Test("Rejects duplicate email")
    func rejectDuplicate() async {
        mockRepo.existingEmails = ["taken@test.com"]
        await #expect(throws: UserError.emailTaken) {
            try await sut.create(name: "Bob", email: "taken@test.com")
        }
    }
}
```

### Nested Suites

```swift
@Suite("Cart")
struct CartTests {
    @Suite("Adding items")
    struct AddingItems {
        @Test func addSingleItem() { /* ... */ }
        @Test func addMultipleItems() { /* ... */ }
    }

    @Suite("Removing items")
    struct RemovingItems {
        @Test func removeExistingItem() { /* ... */ }
        @Test func removeNonexistentItem() { /* ... */ }
    }

    @Suite("Checkout")
    struct Checkout {
        @Test func emptyCartCannotCheckout() { /* ... */ }
        @Test func checkoutCalculatesTotal() { /* ... */ }
    }
}
```

### Suite with Traits

```swift
@Suite("Network Tests", .serialized, .tags(.networking))
struct NetworkTests {
    // All tests in this suite run serially (not in parallel)
    // All tests inherit the .networking tag
}
```

## Tags

Custom tags for filtering and organizing tests.

```swift
extension Tag {
    @Tag static var networking: Self
    @Tag static var database: Self
    @Tag static var authentication: Self
    @Tag static var critical: Self
    @Tag static var slow: Self
}

@Test(.tags(.networking, .critical))
func loginAPI() async throws { /* ... */ }

@Test(.tags(.database))
func userPersistence() throws { /* ... */ }

// Run only tagged tests from command line:
// swift test --filter .tags:networking
```

## Traits Reference

| Trait | Usage |
|-------|-------|
| `.tags(...)` | Categorize tests |
| `.enabled(if: Bool)` | Conditionally enable |
| `.disabled(_ comment: String)` | Skip with reason |
| `.bug(_ url: String)` | Link to bug tracker |
| `.bug(_ id: Int)` | Link to bug by ID |
| `.timeLimit(.minutes(N))` | Max execution time |
| `.serialized` | Disable parallel execution (Suite-level) |

## Custom TestScoping Trait

Run custom setup/teardown around tests.

```swift
struct DatabaseFixture: TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        // Setup
        let db = try await TestDatabase.create()
        try await db.loadFixtures()

        // Run test
        try await function()

        // Teardown
        try await db.destroy()
    }
}

extension Trait where Self == DatabaseFixture {
    static var databaseFixture: Self { DatabaseFixture() }
}

@Test(.databaseFixture)
func queryUsers() async throws { /* ... */ }
```

## Parallel Execution

Tests run in **parallel by default** in Swift Testing. This is different from XCTest.

```swift
// Tests in this suite run in parallel (default)
@Suite struct FastTests {
    @Test func test1() { }
    @Test func test2() { }
}

// Force serial execution
@Suite(.serialized) struct SerialTests {
    @Test func step1() { }  // Runs first
    @Test func step2() { }  // Runs after step1
}
```

**Warning:** Because tests run in parallel, they must not share mutable state. Using structs for `@Suite` naturally prevents this.

## Exit Tests (Experimental)

Test that code calls `exit()`, `fatalError()`, or `preconditionFailure()`.

```swift
@Test func invalidConfigurationExits() async {
    await #expect(exitsWith: .failure) {
        Config(apiKey: "")  // Should call fatalError
    }
}
```

## Swift Testing vs XCTest Comparison

| Feature | Swift Testing | XCTest |
|---------|--------------|--------|
| Test container | `@Suite struct` | `class: XCTestCase` |
| Test function | `@Test func name()` | `func testName()` |
| Assertion | `#expect(expr)` | `XCTAssertTrue(expr)` |
| Fatal assertion | `#require(expr)` | `XCTUnwrap(expr)` |
| Expected error | `#expect(throws:) { }` | `XCTAssertThrowsError { }` |
| Async wait | `confirmation { }` | `XCTestExpectation` + `wait` |
| Setup | `init()` | `override func setUp()` |
| Teardown | `deinit` | `override func tearDown()` |
| Parameterized | `@Test(arguments:)` | Manual loop or separate tests |
| Tags | `.tags(...)` | Test plans |
| Skip | `.enabled(if:)` / `.disabled()` | `XCTSkipIf` / `XCTSkipUnless` |
| Parallel | Default on | Default off |
| Performance | Not supported | `measure { }` |
| UI testing | Not supported | XCUIApplication |
| Display name | `@Test("Name")` | Not available |
| Known issue | `withKnownIssue` | Not available |
