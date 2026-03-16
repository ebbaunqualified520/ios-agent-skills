---
name: ios-testing
description: >
  iOS testing expert skill covering Swift Testing framework (@Test, #expect, #require, @Suite, parameterized tests, traits),
  XCTest (assertions, async testing, performance testing, XCTestExpectation), UI Testing (XCUIApplication, XCUIElement,
  Page Object pattern, accessibility identifiers), snapshot testing (swift-snapshot-testing), mocking strategies
  (protocol-based mocks, URLProtocol for network, test doubles), and testing patterns for SwiftUI, SwiftData, Combine,
  and async/await code. Use this skill whenever the user writes tests, creates test classes, needs mocking strategies,
  or asks about testing iOS code. Triggers on: test, @Test, #expect, XCTest, XCTestCase, unit test, UI test,
  integration test, mock, stub, spy, fake, snapshot test, test coverage, TDD, testing, assert, XCTAssert,
  Swift Testing, @Suite, parameterized test, test plan, test double, URLProtocol mock, ViewInspector,
  or any iOS testing question.
---

# iOS Testing Skill

## Core Rules

1. **Use Swift Testing (`@Test`, `#expect`) for ALL new unit tests** -- it is the modern framework (Xcode 16+).
2. **Keep XCTest only for UI tests and performance tests** -- Swift Testing does not support these yet.
3. Both frameworks can coexist in the same target -- migrate incrementally, never rewrite working tests.
4. Use **protocol-based dependency injection** for testability.
5. Use **`URLProtocol`** for network mocking (NOT mocking URLSession directly).
6. Use **`isStoredInMemoryOnly: true`** for SwiftData test containers.
7. Name tests descriptively: `@Test("Login succeeds with valid credentials")`.
8. One assertion per test is ideal, but pragmatic grouping is fine.
9. **Test behavior, not implementation details.**
10. Never use `sleep()` in tests -- use expectations, confirmations, or `Clock` injection.

## Framework Choice

| Test Type | Framework | Why |
|-----------|-----------|-----|
| Unit tests (new) | Swift Testing | Modern, less boilerplate, parameterized tests |
| Unit tests (existing) | XCTest | Don't rewrite working tests without reason |
| UI tests | XCTest | Swift Testing doesn't support XCUIApplication |
| Performance tests | XCTest | `measure {}` not available in Swift Testing |
| Snapshot tests | XCTest + swift-snapshot-testing | Point-Free library, XCTest integration |

## Test Organization

```
MyAppTests/                    # Unit test target
  Models/
    UserTests.swift
    OrderTests.swift
  ViewModels/
    LoginViewModelTests.swift
    ProfileViewModelTests.swift
  Services/
    APIClientTests.swift
    AuthServiceTests.swift
  Helpers/
    Mocks/
      MockAPIClient.swift
      MockAuthService.swift
    TestData/
      UserFixtures.swift
      JSONFixtures.swift
MyAppUITests/                  # UI test target
  Screens/                     # Page Objects
    LoginScreen.swift
    HomeScreen.swift
  Flows/
    OnboardingFlowTests.swift
    PurchaseFlowTests.swift
  Helpers/
    XCUIApplication+Launch.swift
```

## Quick Start: Swift Testing

```swift
import Testing
@testable import MyApp

@Suite("AuthService")
struct AuthServiceTests {
    let sut: AuthService
    let mockAPI: MockAPIClient

    init() {
        mockAPI = MockAPIClient()
        sut = AuthService(api: mockAPI)
    }

    @Test("Login succeeds with valid credentials")
    func loginSuccess() async throws {
        mockAPI.loginResult = .success(User.fixture)

        let user = try await sut.login(email: "test@example.com", password: "pass123")

        #expect(user.email == "test@example.com")
        #expect(mockAPI.loginCallCount == 1)
    }

    @Test("Login fails with invalid credentials")
    func loginFailure() async {
        mockAPI.loginResult = .failure(AuthError.invalidCredentials)

        await #expect(throws: AuthError.invalidCredentials) {
            try await sut.login(email: "bad@example.com", password: "wrong")
        }
    }

    @Test("Password validation", arguments: [
        ("short", false),
        ("validPass1!", true),
        ("nouppercase1!", false),
        ("NOLOWERCASE1!", false),
    ])
    func passwordValidation(password: String, isValid: Bool) {
        #expect(sut.isValidPassword(password) == isValid)
    }
}
```

## Quick Start: XCTest (UI Tests)

```swift
import XCTest

final class LoginUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launch()
    }

    func test_login_withValidCredentials_showsHome() {
        let loginScreen = LoginScreen(app: app)

        loginScreen
            .typeEmail("user@example.com")
            .typePassword("password123")
            .tapLogin()

        let homeScreen = HomeScreen(app: app)
        XCTAssertTrue(homeScreen.welcomeLabel.waitForExistence(timeout: 5))
    }
}
```

## Protocol-Based Mocking Pattern

```swift
// 1. Define protocol
protocol APIClientProtocol: Sendable {
    func login(email: String, password: String) async throws -> User
    func fetchProfile(id: String) async throws -> Profile
}

// 2. Production implementation
final class APIClient: APIClientProtocol {
    func login(email: String, password: String) async throws -> User { /* real impl */ }
    func fetchProfile(id: String) async throws -> Profile { /* real impl */ }
}

// 3. Mock for tests
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var loginResult: Result<User, Error> = .failure(TestError.notConfigured)
    var loginCallCount = 0
    var loginReceivedArgs: [(email: String, password: String)] = []

    func login(email: String, password: String) async throws -> User {
        loginCallCount += 1
        loginReceivedArgs.append((email, password))
        return try loginResult.get()
    }

    var fetchProfileResult: Result<Profile, Error> = .failure(TestError.notConfigured)
    var fetchProfileCallCount = 0

    func fetchProfile(id: String) async throws -> Profile {
        fetchProfileCallCount += 1
        return try fetchProfileResult.get()
    }
}
```

## URLProtocol Network Mocking

```swift
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

// Usage in test:
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)
let apiClient = APIClient(session: session)

MockURLProtocol.requestHandler = { request in
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let data = try JSONEncoder().encode(User.fixture)
    return (response, data)
}
```

## SwiftData Testing

```swift
@Test("Saving a user persists it")
func saveUser() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: User.self, configurations: config)
    let context = ModelContext(container)

    let user = User(name: "Test", email: "test@example.com")
    context.insert(user)
    try context.save()

    let descriptor = FetchDescriptor<User>()
    let users = try context.fetch(descriptor)
    #expect(users.count == 1)
    #expect(users.first?.name == "Test")
}
```

## Combine Testing

```swift
@Test("Publisher emits values correctly")
func publisherEmitsValues() async {
    let viewModel = CounterViewModel()
    var received: [Int] = []
    let cancellable = viewModel.$count.sink { received.append($0) }

    viewModel.increment()
    viewModel.increment()

    #expect(received == [0, 1, 2])
    cancellable.cancel()
}
```

## async/await Confirmation (Replaces XCTestExpectation)

```swift
@Test("Notification triggers callback")
func notificationCallback() async {
    await confirmation("callback received") { confirm in
        let observer = NotificationObserver {
            confirm()
        }
        NotificationCenter.default.post(name: .testNotification, object: nil)
    }
}

@Test("Delegate called exactly 3 times")
func delegateCalledThreeTimes() async {
    await confirmation("delegate called", expectedCount: 3) { confirm in
        let delegate = MockDelegate(onCall: { confirm() })
        let sut = DataLoader(delegate: delegate)
        await sut.loadBatch(count: 3)
    }
}
```

## Test Fixtures Pattern

```swift
extension User {
    static var fixture: User {
        User(id: "test-id", name: "Test User", email: "test@example.com")
    }

    static func fixture(
        id: String = "test-id",
        name: String = "Test User",
        email: String = "test@example.com"
    ) -> User {
        User(id: id, name: name, email: email)
    }
}
```

## Common Mistakes to Avoid

1. **Don't test private methods** -- test public behavior instead.
2. **Don't mock what you don't own** -- wrap third-party APIs in your own protocol.
3. **Don't use `sleep()` or `Task.sleep()` for timing** -- use `Clock` injection or expectations.
4. **Don't share mutable state between tests** -- use struct-based `@Suite` with `init()`.
5. **Don't forget `@MainActor` isolation** -- if your SUT is `@MainActor`, your test must be too.
6. **Don't use `XCTAssert` in Swift Testing** -- use `#expect` and `#require`.
7. **Don't force-unwrap in tests** -- use `#require` or `XCTUnwrap`.
8. **Don't test Apple frameworks** -- trust that `UserDefaults.set` works.
9. **Don't write tests after the fact just for coverage** -- write tests that catch real bugs.
10. **Don't ignore flaky tests** -- use `withKnownIssue` to mark them, then fix root cause.

## Migration: XCTest to Swift Testing

| XCTest | Swift Testing |
|--------|--------------|
| `class MyTests: XCTestCase` | `@Suite struct MyTests` |
| `func testSomething()` | `@Test func something()` |
| `override func setUp()` | `init()` |
| `override func tearDown()` | `deinit` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertThrowsError(expr)` | `#expect(throws: ErrorType.self) { expr }` |
| `XCTUnwrap(optional)` | `try #require(optional)` |
| `XCTestExpectation` + `wait` | `confirmation { }` |
| `XCTSkipIf(condition)` | `.enabled(if: !condition)` trait |
| `measure { }` | No equivalent -- keep in XCTest |
| UI tests with XCUIApplication | No equivalent -- keep in XCTest |

## References

- [references/swift-testing.md](references/swift-testing.md) -- Swift Testing framework deep dive
- [references/xctest.md](references/xctest.md) -- XCTest assertions, async, performance
- [references/ui-testing.md](references/ui-testing.md) -- XCUIApplication, Page Object, accessibility
- [references/mocking.md](references/mocking.md) -- Protocol mocks, URLProtocol, snapshot testing
