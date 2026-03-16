# XCTest Framework Reference

## Overview

XCTest is Apple's original test framework. Use it for UI tests, performance tests, and maintaining existing test suites. For new unit tests, prefer Swift Testing.

```swift
import XCTest
@testable import MyApp
```

## XCTestCase Lifecycle

```swift
final class UserServiceTests: XCTestCase {
    var sut: UserService!
    var mockRepo: MockUserRepository!

    // Called ONCE before all tests in the class
    override class func setUp() {
        super.setUp()
        // Expensive one-time setup (database schema, etc.)
    }

    // Called before EACH test method
    override func setUp() {
        super.setUp()
        mockRepo = MockUserRepository()
        sut = UserService(repository: mockRepo)
    }

    // Called after EACH test method
    override func tearDown() {
        sut = nil
        mockRepo = nil
        super.tearDown()
    }

    // Called ONCE after all tests in the class
    override class func tearDown() {
        // One-time cleanup
        super.tearDown()
    }

    func testExample() {
        XCTAssertNotNil(sut)
    }
}
```

### Async setUp/tearDown (Xcode 14.3+)

```swift
final class AsyncTests: XCTestCase {
    var sut: DataLoader!

    override func setUp() async throws {
        try await super.setUp()
        sut = try await DataLoader.create()
    }

    override func tearDown() async throws {
        try await sut.cleanup()
        sut = nil
        try await super.tearDown()
    }
}
```

## Assertions — Complete Reference

### Boolean Assertions

```swift
XCTAssert(expression)                          // expression is true
XCTAssertTrue(expression)                      // expression is true
XCTAssertFalse(expression)                     // expression is false
```

### Equality

```swift
XCTAssertEqual(a, b)                           // a == b
XCTAssertNotEqual(a, b)                        // a != b
XCTAssertEqual(3.14, pi, accuracy: 0.01)       // floating point
XCTAssertNotEqual(3.14, e, accuracy: 0.01)     // floating point
```

### Nil Checks

```swift
XCTAssertNil(expression)                       // expression is nil
XCTAssertNotNil(expression)                    // expression is not nil
```

### Comparison

```swift
XCTAssertGreaterThan(a, b)                     // a > b
XCTAssertGreaterThanOrEqual(a, b)              // a >= b
XCTAssertLessThan(a, b)                        // a < b
XCTAssertLessThanOrEqual(a, b)                 // a <= b
```

### Error Handling

```swift
// Assert that expression throws an error
XCTAssertThrowsError(try riskyOperation()) { error in
    XCTAssertEqual(error as? MyError, .invalidInput)
}

// Assert that expression does NOT throw
XCTAssertNoThrow(try safeOperation())
```

### Failure

```swift
XCTFail("Unexpected code path reached")       // Unconditional failure
```

### Custom Messages

All assertions accept an optional message as the last argument:

```swift
XCTAssertEqual(user.age, 25, "Expected age to be 25 after birthday")
```

## XCTUnwrap

Unwrap an optional or fail the test. Cleaner than force-unwrapping.

```swift
func testUserHasAddress() throws {
    let user = User(name: "Alice", address: Address(city: "NYC"))

    let address = try XCTUnwrap(user.address, "User should have an address")
    XCTAssertEqual(address.city, "NYC")
}
```

## Async Testing

### async/await (Preferred)

```swift
func testFetchUser() async throws {
    let user = try await api.fetchUser(id: "123")
    XCTAssertEqual(user.name, "Alice")
}

func testFetchFailsForInvalidID() async {
    do {
        _ = try await api.fetchUser(id: "invalid")
        XCTFail("Expected error to be thrown")
    } catch {
        XCTAssertEqual(error as? APIError, .notFound)
    }
}
```

### XCTestExpectation (Callback-Based Code)

```swift
func testNotificationReceived() {
    let expectation = expectation(description: "Notification received")

    let observer = NotificationCenter.default.addObserver(
        forName: .dataUpdated, object: nil, queue: .main
    ) { _ in
        expectation.fulfill()
    }

    dataService.refresh()

    waitForExpectations(timeout: 5)
    NotificationCenter.default.removeObserver(observer)
}
```

### fulfillment(of:timeout:) — Modern API (Xcode 15+)

```swift
func testDelegateCallback() async {
    let expectation = expectation(description: "Delegate called")
    let delegate = MockDelegate(onComplete: { expectation.fulfill() })
    let sut = DataLoader(delegate: delegate)

    sut.load()

    await fulfillment(of: [expectation], timeout: 5)
    XCTAssertTrue(delegate.didComplete)
}
```

### Multiple Expectations

```swift
func testMultipleCallbacks() async {
    let loaded = expectation(description: "Data loaded")
    let cached = expectation(description: "Data cached")

    sut.onLoad = { loaded.fulfill() }
    sut.onCache = { cached.fulfill() }

    sut.fetchAndCache()

    await fulfillment(of: [loaded, cached], timeout: 10, enforceOrder: true)
}
```

### Inverted Expectation (Something Should NOT Happen)

```swift
func testNoCallbackOnCancel() async {
    let unexpected = expectation(description: "Callback should not fire")
    unexpected.isInverted = true

    sut.onComplete = { unexpected.fulfill() }
    sut.cancel()

    await fulfillment(of: [unexpected], timeout: 2)
}
```

### Expected Fulfillment Count

```swift
func testCalledExactlyThreeTimes() async {
    let exp = expectation(description: "Called 3 times")
    exp.expectedFulfillmentCount = 3

    sut.onProgress = { exp.fulfill() }
    sut.processItems([1, 2, 3])

    await fulfillment(of: [exp], timeout: 5)
}
```

## Performance Testing

### Basic measure

```swift
func testSortingPerformance() {
    let data = (0..<10_000).map { _ in Int.random(in: 0...100_000) }

    measure {
        _ = data.sorted()
    }
}
```

### With Metrics

```swift
func testMemoryUsage() {
    measure(metrics: [XCTMemoryMetric(), XCTCPUMetric(), XCTClockMetric()]) {
        _ = LargeDataProcessor().process(sampleData)
    }
}
```

### With Options

```swift
func testPerformanceWithOptions() {
    let options = XCTMeasureOptions()
    options.iterationCount = 20

    measure(options: options) {
        _ = heavyComputation()
    }
}
```

### Performance Baselines

Set baselines in Xcode: click the diamond next to `measure` after running once. Xcode stores baselines per device. Tests fail if performance regresses beyond the configured threshold (default 10%).

### startMeasuring / stopMeasuring

```swift
func testOnlyTheCriticalPath() {
    let data = prepareTestData()  // Not measured

    measure {
        startMeasuring()
        _ = sut.process(data)
        stopMeasuring()
    }
}
```

## Skipping Tests

```swift
func testRequiresNetwork() throws {
    try XCTSkipIf(!NetworkMonitor.isConnected, "No network available")
    // Test body runs only if connected
}

func testRequiresSpecificOS() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17,
                      "Requires iOS 17+")
}
```

## Test Naming Conventions

```swift
// Pattern: test_whatIsBeingTested_condition_expectedResult
func test_login_withValidCredentials_returnsUser() { }
func test_login_withEmptyPassword_throwsError() { }
func test_fetchUsers_whenOffline_returnsCachedData() { }
func test_cart_addItem_increasesCount() { }
```

## Additive Assertions Pattern

```swift
func testUserValidation() {
    let errors = UserValidator.validate(User(name: "", email: "bad", age: -1))

    XCTAssertTrue(errors.contains(.nameRequired), "Name validation failed")
    XCTAssertTrue(errors.contains(.invalidEmail), "Email validation failed")
    XCTAssertTrue(errors.contains(.invalidAge), "Age validation failed")
    XCTAssertEqual(errors.count, 3, "Should have exactly 3 errors")
}
```

## Test Bundles and Targets

- **Unit test target** (`MyAppTests`): Links against main app target, uses `@testable import`.
- **UI test target** (`MyAppUITests`): Launches app as separate process, no `@testable import`.
- Tests run in parallel by default at the **target** level (Xcode scheme settings).
- Use **Test Plans** (`.xctestplan`) to configure which tests run, environment variables, and code coverage settings.

## XCTest Lifecycle Summary

```
Class setUp()           -- once per class
  ├── setUp()           -- before each test
  │   ├── test_A()
  │   └── tearDown()    -- after each test
  ├── setUp()
  │   ├── test_B()
  │   └── tearDown()
  └── ...
Class tearDown()        -- once per class
```
