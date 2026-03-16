# Accessibility Auditing Reference

Xcode Accessibility Inspector, XCTest automated audits, environment values, manual testing checklist, common mistakes, and best practices.

---

## Xcode Accessibility Inspector

Open: Xcode menu > Open Developer Tool > Accessibility Inspector

### Three Modes

**1. Inspect**
- Hover over any element in the Simulator or a connected device.
- Shows: label, value, traits, frame, actions, identifier.
- Verify that every element has the correct label and traits.

**2. Audit**
- Click the Audit button (checkmark icon) to scan the entire screen.
- Reports issues: missing labels, small hit regions, low contrast, clipped text.
- Click any issue to highlight the element.
- Does NOT catch every problem — supplement with manual testing.

**3. Settings Simulation**
- Simulate accessibility settings without changing device settings:
  - Dynamic Type size
  - Bold Text
  - Reduce Motion
  - Reduce Transparency
  - Increase Contrast
  - Differentiate Without Color
  - Invert Colors (Smart/Classic)
  - Button Shapes
- Useful for quick visual checks across settings combinations.

### Inspector Workflow

1. Run the app in Simulator.
2. Open Accessibility Inspector, select the Simulator as the target.
3. Enable Inspect mode, swipe through every element.
4. Verify:
   - Every interactive element has a label.
   - Labels are descriptive (not "button" or "image").
   - Correct traits are assigned.
   - Reading order makes sense.
5. Run Audit on each screen.
6. Simulate large text sizes and verify layout adaptation.
7. Simulate Reduce Motion and verify animations.

---

## XCTest Automated Audits

### performAccessibilityAudit (iOS 17+)

```swift
import XCTest

final class AccessibilityAuditTests: XCTestCase {

    func testHomeScreenAccessibility() throws {
        let app = XCUIApplication()
        app.launch()

        // Audit all categories
        try app.performAccessibilityAudit()
    }

    func testSettingsScreenAccessibility() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()

        // Audit specific categories
        try app.performAccessibilityAudit(for: [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription
        ])
    }
}
```

### Audit Categories

| Category | What It Checks |
|---|---|
| `.contrast` | Text and image contrast ratios meet WCAG AA |
| `.elementDetection` | Interactive elements are properly exposed to assistive tech |
| `.hitRegion` | Touch targets are at least 44x44 points |
| `.sufficientElementDescription` | Elements have meaningful labels (not empty, not just type) |
| `.dynamicType` | Text responds to Dynamic Type size changes |
| `.textClipped` | Text is not clipped or truncated at large sizes |
| `.trait` | Correct traits are assigned (buttons have .isButton, etc.) |

### Auditing All Categories

```swift
// Audit every category (default when no parameter is given)
try app.performAccessibilityAudit()

// Equivalent to:
try app.performAccessibilityAudit(for: .all)
```

### Filtering Known Issues

Some issues may be in system components or third-party SDKs that you cannot fix. Filter them out.

```swift
func testMainScreenAudit() throws {
    let app = XCUIApplication()
    app.launch()

    try app.performAccessibilityAudit(for: .all) { issue in
        // Skip issues in the system tab bar
        if issue.element?.identifier == "TabBar" {
            return false  // false = ignore this issue
        }

        // Skip contrast issues in the navigation bar (system component)
        if issue.auditType == .contrast,
           issue.element?.elementType == .navigationBar {
            return false
        }

        return true  // true = report this issue as a failure
    }
}
```

### Running Audits on Every Screen

```swift
final class FullAppAuditTests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launch()
    }

    func testHomeTabAudit() throws {
        try app.performAccessibilityAudit()
    }

    func testSearchTabAudit() throws {
        app.tabBars.buttons["Search"].tap()
        try app.performAccessibilityAudit()
    }

    func testProfileTabAudit() throws {
        app.tabBars.buttons["Profile"].tap()
        try app.performAccessibilityAudit()
    }

    func testSettingsAudit() throws {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        try app.performAccessibilityAudit()
    }
}
```

### Dynamic Type Audit

```swift
func testDynamicTypeAtAccessibilitySizes() throws {
    let app = XCUIApplication()
    app.launch()

    // Test at the largest accessibility size
    // Set via launch argument or XCUIDevice settings
    try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
}
```

---

## Complete SwiftUI Accessibility Modifiers Reference

### Labels and Descriptions

| Modifier | Purpose |
|---|---|
| `.accessibilityLabel(_:)` | Primary VoiceOver description |
| `.accessibilityLabel(content:)` | Closure to modify existing label (iOS 18+) |
| `.accessibilityHint(_:)` | Describes result of activation |
| `.accessibilityValue(_:)` | Current value of a control |
| `.accessibilityInputLabels(_:)` | Voice Control alternate names |
| `.accessibilityIdentifier(_:)` | UI test identifier (not read by VoiceOver) |

### Traits and Behavior

| Modifier | Purpose |
|---|---|
| `.accessibilityAddTraits(_:)` | Add accessibility traits |
| `.accessibilityRemoveTraits(_:)` | Remove inferred traits |
| `.accessibilityHeading(_:)` | Set heading level (h1-h6) |
| `.accessibilityHidden(_:)` | Hide from accessibility tree |
| `.accessibilitySortPriority(_:)` | Override reading order |

### Structure

| Modifier | Purpose |
|---|---|
| `.accessibilityElement(children:)` | Control child element handling (.ignore, .combine, .contain) |
| `.accessibilityRepresentation { }` | Replace a11y tree with standard control |
| `.accessibilityChildren { }` | Provide synthetic child elements |
| `.accessibilityShowsLargeContentViewer { }` | Large Content Viewer for non-scaling elements |

### Actions

| Modifier | Purpose |
|---|---|
| `.accessibilityAction(_:_:)` | Custom action (named, escape, magicTap) |
| `.accessibilityAction(named:_:)` | Named action in Actions rotor |
| `.accessibilityAdjustableAction(_:)` | Increment/decrement with swipe |
| `.accessibilityScrollAction(_:)` | Custom scroll behavior |
| `.accessibilityActivationPoint(_:)` | Custom activation point within element |

### Focus

| Modifier | Purpose |
|---|---|
| `.accessibilityFocused(_:)` | Bind focus to @AccessibilityFocusState (Bool) |
| `.accessibilityFocused(_:equals:)` | Bind focus to @AccessibilityFocusState (enum) |
| `.accessibilityRespondsToUserInteraction(_:)` | Whether element receives focus |

### Rotor

| Modifier | Purpose |
|---|---|
| `.accessibilityRotor(_:entries:)` | Custom rotor for navigation |
| `.accessibilityRotor(_:textRanges:)` | Rotor for text ranges |
| `.accessibilityRotorEntry(id:in:)` | Mark element as rotor entry |

### Other

| Modifier | Purpose |
|---|---|
| `.accessibilityIgnoresInvertColors(_:)` | Prevent Smart Invert on images/media |
| `.accessibilityTextContentType(_:)` | Content type hint (.console, .fileSystem, .messaging, .narrative, .plain, .sourceCode, .spreadsheet, .wordProcessing) |
| `.accessibilityDirectTouch(_:options:)` | Direct touch interaction |
| `.accessibilityZoomAction(_:)` | Custom zoom behavior |
| `.accessibilityLinkedGroup(_:in:)` | Link elements across containers |
| `.accessibilityChartDescriptor(_:)` | Describe Swift Charts for VoiceOver |

---

## All @Environment Accessibility Values

```swift
// Dynamic Type
@Environment(\.dynamicTypeSize) var dynamicTypeSize          // DynamicTypeSize enum
// dynamicTypeSize.isAccessibilitySize                       // Bool

// Visual Settings
@Environment(\.colorScheme) var colorScheme                  // .light / .dark
@Environment(\.colorSchemeContrast) var contrast             // .standard / .increased
@Environment(\.legibilityWeight) var legibilityWeight        // .regular / .bold
@Environment(\.accessibilityShowButtonShapes) var buttonShapes  // Bool (iOS 17.5+: @Environment)

// Motion and Animation
@Environment(\.accessibilityReduceMotion) var reduceMotion            // Bool
@Environment(\.accessibilityReduceTransparency) var reduceTransparency // Bool
@Environment(\.accessibilityDimFlashingLights) var dimFlashing         // Bool (iOS 17+)
@Environment(\.accessibilityPlayAnimatedImages) var playAnimations     // Bool (iOS 17+)

// Color
@Environment(\.accessibilityDifferentiateWithoutColor) var noColor    // Bool
@Environment(\.accessibilityInvertColors) var invertColors             // Bool

// Interaction
@Environment(\.accessibilityQuickActionsEnabled) var quickActions     // Bool (iOS 17+)
@Environment(\.accessibilitySwitchControlEnabled) var switchControl   // Bool (iOS 17.5+)
@Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled    // Bool (iOS 17.5+)
@Environment(\.accessibilityAssistiveAccessEnabled) var assistiveAccess // Bool (iOS 17+)

// Prefer
@Environment(\.accessibilityPrefersHeadAnchorAlternative) var headAnchorAlt // Bool (visionOS)
```

---

## Manual Testing Checklist

Perform these checks on a real device with VoiceOver enabled.

1. **Navigate the entire screen** with VoiceOver (swipe right repeatedly). Every element should be reachable and announced correctly.

2. **Activate every button** by double-tapping. Confirm the action executes and VoiceOver announces the result.

3. **Check reading order** — does it follow a logical sequence? Use the Rotor > Headings to verify heading structure.

4. **Test all custom actions** — swipe up/down on elements with custom actions and verify they work.

5. **Test adjustable controls** — swipe up/down on sliders, steppers, ratings. Value should update and announce.

6. **Verify modal behavior** — when a modal or alert appears, VoiceOver focus should be trapped inside it. Background content should not be reachable.

7. **Test error states** — trigger validation errors. VoiceOver should announce the error and focus should move to it.

8. **Test with Dynamic Type at AX5** — set the largest accessibility size in Settings > Accessibility > Display & Text Size. Verify no text is clipped, truncated, or overlapping.

9. **Test with Bold Text** — enable in Settings > Accessibility > Display & Text Size > Bold Text. Verify text weight increases.

10. **Test with Increase Contrast** — enable in Settings > Accessibility > Display & Text Size > Increase Contrast. Verify borders and separators are visible.

11. **Test with Reduce Motion** — enable in Settings > Accessibility > Motion > Reduce Motion. Verify animations are replaced with fades or removed.

12. **Test with Differentiate Without Color** — enable in Settings > Accessibility > Display & Text Size. Verify information is not conveyed by color alone.

13. **Test with Smart Invert** — enable in Settings > Accessibility > Display & Text Size > Smart Invert. Verify photos and media are NOT inverted.

14. **Test with Switch Control** — verify the app is usable with Switch Control scanning.

15. **Test with Voice Control** — say "Show names" and verify all interactive elements are labeled and tappable by name.

---

## Common Mistakes and Fixes

### 1. Missing Labels on Icon Buttons

```swift
// BAD: VoiceOver says "button"
Button(action: share) {
    Image(systemName: "square.and.arrow.up")
}

// GOOD: VoiceOver says "Share, button"
Button(action: share) {
    Image(systemName: "square.and.arrow.up")
}
.accessibilityLabel("Share")
```

### 2. Using onTapGesture Without Traits

```swift
// BAD: VoiceOver does not know this is interactive
Text("Learn more")
    .onTapGesture { showDetails() }

// GOOD: Use a Button
Button("Learn more") { showDetails() }

// GOOD: If custom styling needed, add traits
Text("Learn more")
    .onTapGesture { showDetails() }
    .accessibilityAddTraits(.isLink)
    .accessibilityHint("Opens the help article")
```

### 3. Redundant Accessibility Information

```swift
// BAD: VoiceOver says "Delete button, button"
Button("Delete") { delete() }
    .accessibilityAddTraits(.isButton)  // Button already has this trait

// GOOD: Button already has .isButton trait
Button("Delete") { delete() }
```

### 4. Inaccessible Custom Toggle

```swift
// BAD: VoiceOver does not know the state
HStack {
    Text("Airplane Mode")
    Spacer()
    Circle().fill(isOn ? .green : .gray)
}
.onTapGesture { isOn.toggle() }

// GOOD: Use accessibilityRepresentation
HStack {
    Text("Airplane Mode")
    Spacer()
    Circle().fill(isOn ? .green : .gray)
}
.onTapGesture { isOn.toggle() }
.accessibilityRepresentation {
    Toggle("Airplane Mode", isOn: $isOn)
}
```

### 5. Not Grouping Related Elements

```swift
// BAD: VoiceOver requires 4 swipes for one card
VStack {
    Text("iPhone 15 Pro")          // Swipe 1
    Text("$999")                   // Swipe 2
    Text("In stock")               // Swipe 3
    Image(systemName: "star.fill") // Swipe 4
}

// GOOD: Combined into one element
VStack {
    Text("iPhone 15 Pro")
    Text("$999")
    Text("In stock")
    Image(systemName: "star.fill")
        .accessibilityHidden(true)
}
.accessibilityElement(children: .combine)
```

### 6. Color as the Only Indicator

```swift
// BAD: Color-blind users cannot distinguish status
Circle().fill(status == .error ? .red : .green)

// GOOD: Icon + text + color
HStack {
    Image(systemName: status == .error ? "xmark.circle.fill" : "checkmark.circle.fill")
        .foregroundStyle(status == .error ? .red : .green)
    Text(status == .error ? "Error" : "Success")
}
```

### 7. Animations Ignoring Reduce Motion

```swift
// BAD: Animation plays regardless of user preference
withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
    isExpanded.toggle()
}

// GOOD: Respect reduce motion
@Environment(\.accessibilityReduceMotion) private var reduceMotion

withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.3)) {
    isExpanded.toggle()
}
```

### 8. Images Not Protected from Smart Invert

```swift
// BAD: Photo colors are inverted
AsyncImage(url: photoURL) { image in
    image.resizable()
} placeholder: {
    ProgressView()
}

// GOOD: Photo excluded from invert
AsyncImage(url: photoURL) { image in
    image
        .resizable()
        .accessibilityIgnoresInvertColors(true)
} placeholder: {
    ProgressView()
}
```

### 9. No Focus Management on Errors

```swift
// BAD: Error appears but VoiceOver stays on the submit button
if let error = errorMessage {
    Text(error).foregroundStyle(.red)
}

// GOOD: Focus moves to error
@AccessibilityFocusState private var isErrorFocused: Bool

if let error = errorMessage {
    Text(error)
        .foregroundStyle(.red)
        .accessibilityFocused($isErrorFocused)
}

// On error:
errorMessage = "Invalid email address"
isErrorFocused = true
```

### 10. Forgetting accessibilityIdentifier for Tests

```swift
// BAD: Fragile test that breaks when label changes
app.buttons["Submit Order"].tap()

// GOOD: Stable identifier separate from user-facing label
Button("Submit Order") { submit() }
    .accessibilityIdentifier("submitOrderButton")

// Test:
app.buttons["submitOrderButton"].tap()
```

---

## Best Practices for Labels

### Do

- "Delete conversation" (action + object)
- "John's profile photo" (content description)
- "5 unread messages" (meaningful count)
- "Play episode 3: The Beginning" (specific content)
- "Close dialog" (action + context)
- "Sort by date, currently selected" (state in label when no value)

### Don't

- "Button" (just the type)
- "Image" (meaningless)
- "Tap here" (not descriptive)
- "X" (cryptic)
- "btn_delete_msg" (internal identifier)
- "Delete button" (redundant — VoiceOver adds "button" from traits)
- "Double tap to delete" (don't describe the gesture)
- "Red circle" (appearance, not meaning)

---

## Custom Component Accessibility Pattern

When building a reusable custom component, follow this pattern:

```swift
// BAD: Inaccessible custom component
struct RatingView: View {
    @Binding var rating: Int
    let maxRating: Int

    var body: some View {
        HStack {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .gray)
                    .onTapGesture { rating = star }
            }
        }
    }
}

// GOOD: Fully accessible custom component
struct RatingView: View {
    @Binding var rating: Int
    let maxRating: Int

    var body: some View {
        HStack {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .gray)
                    .onTapGesture { rating = star }
            }
        }
        // Treat as a single element
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) out of \(maxRating) stars")
        .accessibilityAddTraits(.isAdjustable)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = min(rating + 1, maxRating)
            case .decrement:
                rating = max(rating - 1, 1)
            @unknown default:
                break
            }
        }
        .accessibilityHint("Swipe up or down to adjust rating")
    }
}
```

This pattern ensures:
- VoiceOver reads one element, not five separate stars.
- The current value is announced.
- Users can adjust with swipe gestures.
- The component is usable without seeing the screen.
