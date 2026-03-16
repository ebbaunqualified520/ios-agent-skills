# UI Testing Reference

## Overview

UI tests use XCUIApplication to launch and interact with the app as a separate process. They verify user-visible behavior through the accessibility hierarchy. Swift Testing does NOT support UI tests -- use XCTest.

```swift
import XCTest
```

## XCUIApplication

### Basic Launch

```swift
final class LoginUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false  // Stop on first failure
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
}
```

### Launch Arguments and Environment

Use launch arguments to configure the app for testing (disable animations, use mock data, reset state).

```swift
override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()

    // Launch arguments (accessed via CommandLine.arguments or ProcessInfo)
    app.launchArguments = [
        "--uitesting",
        "--reset-state",
        "--disable-animations",
        "--mock-network",
    ]

    // Environment variables (accessed via ProcessInfo.processInfo.environment)
    app.launchEnvironment = [
        "API_BASE_URL": "http://localhost:8080",
        "TEST_USER_TOKEN": "mock-token-123",
        "ANIMATIONS_DISABLED": "1",
    ]

    app.launch()
}
```

### Reading Launch Arguments in App Code

```swift
// In AppDelegate or App struct
@main
struct MyApp: App {
    init() {
        if CommandLine.arguments.contains("--uitesting") {
            // Use mock services
            ServiceContainer.shared.useMocks()
        }
        if CommandLine.arguments.contains("--disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
    }
}
```

## XCUIElement Queries

### Finding Elements by Type

```swift
app.buttons["Login"]                          // Button with label "Login"
app.textFields["Email"]                       // Text field with placeholder/label
app.secureTextFields["Password"]              // Password field
app.staticTexts["Welcome"]                    // Label with text "Welcome"
app.navigationBars["Settings"]                // Navigation bar with title
app.tables                                    // All tables
app.cells                                     // All table/collection view cells
app.switches["Dark Mode"]                     // Toggle switch
app.sliders["Volume"]                         // Slider
app.images["profile_photo"]                   // Image view
app.alerts["Error"]                           // Alert with title "Error"
app.sheets                                    // Sheets/action sheets
app.tabBars.buttons["Home"]                   // Tab bar button
app.toolbars.buttons["Done"]                  // Toolbar button
app.searchFields["Search"]                    // Search field
app.textViews["Notes"]                        // Multi-line text view
app.scrollViews                               // Scroll views
app.collectionViews                           // Collection views
app.pickers                                   // Pickers
app.datePickers                               // Date pickers
app.segmentedControls                         // Segmented controls
app.steppers                                  // Steppers
app.popovers                                  // Popovers
app.menus                                     // Context menus
```

### Finding by Accessibility Identifier (Preferred)

```swift
app.buttons["login_button"]                   // accessibilityIdentifier
app.textFields["email_field"]
app.staticTexts["welcome_message"]
```

### Querying Descendants

```swift
let cell = app.tables.cells.element(boundBy: 0)    // First cell
let label = cell.staticTexts["username"]             // Label inside cell
let button = cell.buttons["delete"]                  // Button inside cell

// Count elements
let cellCount = app.tables.cells.count

// Check existence
let exists = app.buttons["Login"].exists

// Element at index
let thirdCell = app.cells.element(boundBy: 2)
```

### Predicate-Based Queries

```swift
let predicate = NSPredicate(format: "label CONTAINS 'Welcome'")
let welcomeLabel = app.staticTexts.matching(predicate).firstMatch

let enabledButtons = app.buttons.matching(NSPredicate(format: "isEnabled == true"))
```

## Element Interactions

### Tap

```swift
app.buttons["Login"].tap()
app.buttons["Menu"].doubleTap()
app.buttons["Options"].press(forDuration: 1.5)  // Long press
app.buttons["Custom"].tap()                      // Coordinate tap below
```

### Type Text

```swift
let emailField = app.textFields["email_field"]
emailField.tap()
emailField.typeText("user@example.com")

// Clear and type
emailField.tap()
emailField.clearAndTypeText("new@example.com")  // Custom extension below
```

### Clear Text Extension

```swift
extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            tap()
            typeText(text)
            return
        }
        tap()
        let selectAll = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(selectAll)
        typeText(text)
    }
}
```

### Swipe

```swift
app.tables.cells.element(boundBy: 0).swipeLeft()
app.tables.cells.element(boundBy: 0).swipeRight()
app.scrollViews.firstMatch.swipeUp()
app.scrollViews.firstMatch.swipeDown()
```

### Scroll to Element

```swift
let lastCell = app.cells.staticTexts["Item 50"]
while !lastCell.isHittable {
    app.swipeUp()
}
lastCell.tap()
```

### Adjust Sliders and Pickers

```swift
app.sliders["volume"].adjust(toNormalizedSliderPosition: 0.75)

let picker = app.pickers.firstMatch
picker.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "Option 3")
```

### Drag and Drop

```swift
let source = app.cells.element(boundBy: 0)
let destination = app.cells.element(boundBy: 3)
source.press(forDuration: 0.5, thenDragTo: destination)
```

## Waiting for Elements

### waitForExistence (Most Common)

```swift
let welcome = app.staticTexts["Welcome"]
XCTAssertTrue(welcome.waitForExistence(timeout: 5), "Welcome label should appear")
```

### Wait for Element to Disappear

```swift
let spinner = app.activityIndicators["loading"]
let disappeared = NSPredicate(format: "exists == false")
let exp = expectation(for: disappeared, evaluatedWith: spinner)
wait(for: [exp], timeout: 10)
```

### Wait for Property Change

```swift
let button = app.buttons["Submit"]
let enabled = NSPredicate(format: "isEnabled == true")
let exp = expectation(for: enabled, evaluatedWith: button)
wait(for: [exp], timeout: 5)
```

## Accessibility Identifiers

**Always use accessibility identifiers for UI test element lookup.** They are stable, not affected by localization, and do not impact the user-visible accessibility experience.

### SwiftUI

```swift
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .accessibilityIdentifier("login_email_field")

            SecureField("Password", text: $password)
                .accessibilityIdentifier("login_password_field")

            Button("Log In") { login() }
                .accessibilityIdentifier("login_submit_button")

            if showError {
                Text(errorMessage)
                    .accessibilityIdentifier("login_error_label")
            }
        }
        .accessibilityIdentifier("login_view")
    }
}
```

### UIKit

```swift
class LoginViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        emailTextField.accessibilityIdentifier = "login_email_field"
        passwordTextField.accessibilityIdentifier = "login_password_field"
        loginButton.accessibilityIdentifier = "login_submit_button"
        errorLabel.accessibilityIdentifier = "login_error_label"
    }
}
```

### Naming Convention

```
<screen>_<element>_<type>
login_email_field
login_submit_button
home_welcome_label
settings_darkmode_switch
cart_item_0_cell
cart_checkout_button
```

## System Alerts (Permissions)

Handle iOS permission dialogs (location, notifications, camera, etc.).

```swift
override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()

    // Handle system alerts
    addUIInterruptionMonitor(withDescription: "System Alert") { alert in
        if alert.buttons["Allow"].exists {
            alert.buttons["Allow"].tap()
            return true
        }
        if alert.buttons["Don't Allow"].exists {
            alert.buttons["Don't Allow"].tap()
            return true
        }
        return false
    }

    app.launch()
}

// After triggering a permission dialog, you must interact with the app
// for the interruption monitor to fire:
func testLocationPermission() {
    app.buttons["share_location"].tap()
    app.tap()  // Triggers the interruption monitor
    // Continue with test
}
```

### Springboard Alerts (iOS 17+)

```swift
func testNotificationPermission() {
    app.buttons["enable_notifications"].tap()

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allowButton = springboard.buttons["Allow"]
    if allowButton.waitForExistence(timeout: 5) {
        allowButton.tap()
    }
}
```

## Screenshots and Attachments

### Capture Screenshot

```swift
func testHomeScreen() {
    // Navigate to home screen
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "Home Screen"
    attachment.lifetime = .keepAlways  // .deleteOnSuccess (default) or .keepAlways
    add(attachment)
}
```

### Screenshot on Failure

```swift
override func tearDown() {
    if testRun?.hasBeenSkipped == false && testRun?.hasSucceeded == false {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Failure - \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    super.tearDown()
}
```

### Attach Data

```swift
func testExportData() {
    let jsonData = try! JSONEncoder().encode(testResult)
    let attachment = XCTAttachment(data: jsonData, uniformTypeIdentifier: "public.json")
    attachment.name = "Test Result JSON"
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

## Page Object Pattern

Encapsulate screen interactions in dedicated types. This makes tests readable and maintainable.

### Screen Protocol

```swift
protocol Screen {
    var app: XCUIApplication { get }
    init(app: XCUIApplication)
}
```

### Login Screen Page Object

```swift
struct LoginScreen: Screen {
    let app: XCUIApplication

    // MARK: - Elements

    var emailField: XCUIElement {
        app.textFields["login_email_field"]
    }

    var passwordField: XCUIElement {
        app.secureTextFields["login_password_field"]
    }

    var loginButton: XCUIElement {
        app.buttons["login_submit_button"]
    }

    var errorLabel: XCUIElement {
        app.staticTexts["login_error_label"]
    }

    var forgotPasswordLink: XCUIElement {
        app.buttons["login_forgot_password"]
    }

    // MARK: - Actions

    @discardableResult
    func typeEmail(_ email: String) -> Self {
        emailField.tap()
        emailField.typeText(email)
        return self
    }

    @discardableResult
    func typePassword(_ password: String) -> Self {
        passwordField.tap()
        passwordField.typeText(password)
        return self
    }

    @discardableResult
    func tapLogin() -> Self {
        loginButton.tap()
        return self
    }

    @discardableResult
    func tapForgotPassword() -> Self {
        forgotPasswordLink.tap()
        return self
    }

    // MARK: - Assertions

    @discardableResult
    func assertErrorMessage(_ message: String) -> Self {
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(errorLabel.label, message)
        return self
    }

    @discardableResult
    func assertLoginButtonDisabled() -> Self {
        XCTAssertFalse(loginButton.isEnabled)
        return self
    }
}
```

### Home Screen Page Object

```swift
struct HomeScreen: Screen {
    let app: XCUIApplication

    var welcomeLabel: XCUIElement {
        app.staticTexts["home_welcome_label"]
    }

    var profileButton: XCUIElement {
        app.buttons["home_profile_button"]
    }

    var settingsButton: XCUIElement {
        app.navigationBars.buttons["settings"]
    }

    var itemsList: XCUIElement {
        app.tables["home_items_list"]
    }

    func waitForLoad() -> Self {
        XCTAssertTrue(welcomeLabel.waitForExistence(timeout: 10))
        return self
    }

    @discardableResult
    func tapProfile() -> ProfileScreen {
        profileButton.tap()
        return ProfileScreen(app: app)
    }

    @discardableResult
    func tapSettings() -> SettingsScreen {
        settingsButton.tap()
        return SettingsScreen(app: app)
    }

    func assertItemCount(_ count: Int) -> Self {
        XCTAssertEqual(itemsList.cells.count, count)
        return self
    }
}
```

### Using Page Objects in Tests

```swift
final class LoginFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launch()
    }

    func test_login_withValidCredentials_showsHomeScreen() {
        LoginScreen(app: app)
            .typeEmail("user@example.com")
            .typePassword("password123")
            .tapLogin()

        HomeScreen(app: app)
            .waitForLoad()
            .assertItemCount(5)
    }

    func test_login_withWrongPassword_showsError() {
        LoginScreen(app: app)
            .typeEmail("user@example.com")
            .typePassword("wrongpassword")
            .tapLogin()
            .assertErrorMessage("Invalid credentials")
    }

    func test_login_withEmptyFields_disablesButton() {
        LoginScreen(app: app)
            .assertLoginButtonDisabled()
    }

    func test_loginAndNavigateToSettings() {
        LoginScreen(app: app)
            .typeEmail("user@example.com")
            .typePassword("password123")
            .tapLogin()

        let settings = HomeScreen(app: app)
            .waitForLoad()
            .tapSettings()

        settings.assertDarkModeOff()
    }
}
```

## continueAfterFailure

```swift
override func setUp() {
    super.setUp()
    // false = stop test at first failure (recommended for UI tests)
    // true  = continue running after failure (useful for gathering multiple failures)
    continueAfterFailure = false
}
```

## Launch Performance

```swift
func testLaunchPerformance() throws {
    if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
```

## Tips for Reliable UI Tests

1. **Always use accessibility identifiers** -- never match on localized text.
2. **Set `continueAfterFailure = false`** -- fail fast.
3. **Use `waitForExistence(timeout:)`** -- never `sleep()`.
4. **Reset app state via launch arguments** -- tests must be independent.
5. **Disable animations** -- speeds up tests and reduces flakiness.
6. **Take screenshots on failure** -- easier debugging in CI.
7. **Use Page Objects** -- keeps tests readable and maintainable.
8. **Keep UI tests focused** -- test user flows, not every UI detail.
9. **Run UI tests on a single simulator** -- parallel UI tests are flaky.
10. **Mock network in UI tests** -- use launch arguments to switch to mock server.
