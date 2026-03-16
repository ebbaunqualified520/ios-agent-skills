# VoiceOver Reference

Complete reference for VoiceOver support in SwiftUI: labels, hints, values, traits, actions, rotors, and focus management.

---

## accessibilityLabel

The primary text VoiceOver reads for an element. This is the single most important accessibility modifier.

```swift
// Static string
Button(action: deleteMessage) {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete message")

// Text view (label is inferred from content)
Text("Settings")  // VoiceOver reads "Settings" automatically

// Closure variant (iOS 18+) — prepend/append to existing label
Image(systemName: "envelope.badge")
    .accessibilityLabel { label in
        Text("Unread") + label
    }
```

### Label Guidelines

| Do | Don't |
|---|---|
| "Delete message" | "Button" |
| "Profile photo of John" | "Image" |
| "Search conversations" | "Search" (too vague in context) |
| "Close" | "X" |
| "Add to cart, $9.99" | "Add to cart" (missing price) |
| "Favorited" / "Not favorited" | "Star" |

- Describe **what** or **who**, not the control type (VoiceOver announces the type from traits).
- Keep labels concise: 2-5 words is ideal.
- For images, describe content not appearance: "Profile photo of John" not "circular image".
- Include state in the label when there is no `accessibilityValue`: "Muted microphone" vs "Microphone".

---

## accessibilityHint

Describes the **result** of activating an element. VoiceOver reads it after a pause, and users can disable hints globally.

```swift
Button("Buy Now") { purchase() }
    .accessibilityHint("Purchases the item and charges your payment method")

Toggle("Notifications", isOn: $notificationsEnabled)
    .accessibilityHint("Enables or disables push notifications for this channel")
```

### Hint Guidelines

- Start with a **verb phrase**: "Opens the settings screen", "Removes the item from your cart".
- Do NOT begin with "Double tap to..." — VoiceOver already says "double tap to activate".
- Only add hints for **non-obvious** actions. A "Delete" button does not need a hint.
- Hints are optional; labels are mandatory.

---

## accessibilityValue

Reports the **current value** of an interactive element. VoiceOver reads it after the label and before the trait.

```swift
// Custom slider
CircularSlider(value: $brightness)
    .accessibilityLabel("Brightness")
    .accessibilityValue("\(Int(brightness * 100)) percent")

// Star rating
StarRating(rating: $rating, maxRating: 5)
    .accessibilityLabel("Rating")
    .accessibilityValue("\(rating) out of 5 stars")

// Toggle state (Toggle does this automatically)
// For custom toggles:
.accessibilityValue(isEnabled ? "On" : "Off")
```

- Use for controls where the **state changes** (sliders, steppers, ratings, toggles).
- Standard controls (`Slider`, `Toggle`, `Stepper`, `Picker`) set their value automatically.

---

## accessibilityInputLabels

Alternate names that Voice Control uses to identify an element. Users can say any of these names.

```swift
Button(action: compose) {
    Image(systemName: "square.and.pencil")
}
.accessibilityLabel("Compose new message")
.accessibilityInputLabels(["Compose", "New message", "Write", "New"])
```

- Order from **most specific** to **most general**.
- The first label is also used as the primary Voice Control label.
- Useful when the `accessibilityLabel` is long but users might say something short.

---

## AccessibilityTraits

Traits tell VoiceOver what kind of element this is and how to interact with it.

### Complete Traits Table

| Trait | VoiceOver Announces | Use When |
|---|---|---|
| `.isButton` | "button" | Element performs an action on tap |
| `.isHeader` | "heading" | Section headers, group titles |
| `.isLink` | "link" | Navigates to web content or deep link |
| `.isImage` | "image" | Meaningful images (not decorative) |
| `.isSelected` | "selected" | Currently selected item in a group (tab, segment) |
| `.isToggle` | "switch button" (iOS 17+) | Custom on/off controls |
| `.isModal` | (traps focus) | Modal views — prevents VoiceOver from reading behind |
| `.isStaticText` | (none, default for Text) | Non-interactive text |
| `.isSearchField` | "search field" | Custom search inputs |
| `.isSummaryElement` | (read on screen appear) | Summary text on the first screen element |
| `.isKeyboardKey` | "key" | Custom keyboard keys |
| `.startsMediaSession` | (silences VoiceOver) | Buttons that start audio/video playback |
| `.allowsDirectInteraction` | (pass-through touches) | Drawing canvas, piano keys, games |
| `.updatesFrequently` | (batches announcements) | Live timers, counters, stock tickers |
| `.playsSound` | (none) | Element plays audio on activation |
| `.causesPageTurn` | (none) | Triggers automatic page navigation |
| `.tabBar` | "tab bar" | Custom tab bar containers |

### Adding and Removing Traits

```swift
// Add a trait
Text("Settings")
    .accessibilityAddTraits(.isHeader)

// Add multiple traits
CustomControl()
    .accessibilityAddTraits([.isButton, .isSelected])

// Remove an automatically inferred trait
Image("hero-photo")
    .accessibilityRemoveTraits(.isImage)
    .accessibilityLabel("Summer landscape with mountains")
```

---

## Heading Levels

Heading levels allow VoiceOver rotor navigation by heading level, similar to HTML h1-h6.

```swift
Text("Account Settings")
    .accessibilityHeading(.h1)

Text("Privacy")
    .accessibilityHeading(.h2)

Text("Data Sharing")
    .accessibilityHeading(.h3)
```

- Use `.h1` for the screen title.
- Use `.h2` for section headers.
- Use `.h3` and below for subsection headers.
- VoiceOver rotor lets users jump between headings of the same level.

---

## accessibilityElement(children:)

Controls how child views appear in the accessibility tree.

```swift
// .combine — merge children into one element
// VoiceOver reads: "John Doe, Senior Developer, Engineering"
HStack {
    Text("John Doe").font(.headline)
    Text("Senior Developer").font(.subheadline)
    Text("Engineering").font(.caption)
}
.accessibilityElement(children: .combine)

// .ignore — hide children; you provide the label yourself
VStack {
    Image(systemName: "star.fill")
    Text("5 stars")
}
.accessibilityElement(children: .ignore)
.accessibilityLabel("Rating: 5 out of 5 stars")

// .contain — keep children as separate elements inside a container
// Useful for logical grouping without merging
VStack {
    Text("Section Title").accessibilityAddTraits(.isHeader)
    ForEach(items) { item in
        ItemRow(item: item)
    }
}
.accessibilityElement(children: .contain)
```

---

## Custom Actions

Custom actions appear in the VoiceOver Actions rotor (swipe up/down). They provide alternatives to swipe gestures, long presses, or hidden controls.

### Named Actions

```swift
MessageRow(message: message)
    .accessibilityAction(named: "Reply") { reply(to: message) }
    .accessibilityAction(named: "Forward") { forward(message) }
    .accessibilityAction(named: "Delete") { delete(message) }
    .accessibilityAction(named: "Mark as unread") { markUnread(message) }
```

### Adjustable Action (Increment/Decrement)

```swift
CustomStepper(value: $quantity)
    .accessibilityLabel("Quantity")
    .accessibilityValue("\(quantity)")
    .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
            quantity = min(quantity + 1, 99)
        case .decrement:
            quantity = max(quantity - 1, 0)
        @unknown default:
            break
        }
    }
```

VoiceOver users swipe up to increment, down to decrement.

### Escape Action

Override the two-finger scrub (Z gesture) to dismiss custom presentations.

```swift
.accessibilityAction(.escape) {
    dismiss()
}
```

### Magic Tap

Two-finger double tap. Used for the primary action of the screen (play/pause, answer/end call).

```swift
.accessibilityAction(.magicTap) {
    togglePlayback()
}
```

---

## Rotor Support

Custom rotors let users navigate between specific types of content by rotating two fingers.

```swift
struct ArticleView: View {
    let headings: [Heading]

    var body: some View {
        ScrollView {
            content
        }
        .accessibilityRotor("Headings") {
            ForEach(headings) { heading in
                AccessibilityRotorEntry(heading.title, id: heading.id)
            }
        }
    }
}
```

### System Rotors

```swift
// Navigate between bold text ranges
.accessibilityRotor(.boldText) {
    ForEach(boldRanges) { range in
        AccessibilityRotorEntry(range.text, textRange: range.nsRange)
    }
}

// Available system rotors: .boldText, .heading, .italicText, .image,
// .landmark, .link, .list, .misspelledWord, .table, .textField
```

### Multiple Custom Rotors

```swift
ScrollView {
    content
}
.accessibilityRotor("Comments") {
    ForEach(comments) { comment in
        AccessibilityRotorEntry(comment.author, id: comment.id)
    }
}
.accessibilityRotor("Code Blocks") {
    ForEach(codeBlocks) { block in
        AccessibilityRotorEntry(block.language, id: block.id)
    }
}
```

---

## accessibilityRepresentation

Replace the accessibility subtree of a custom view with a standard control.

```swift
// Custom circular toggle
ZStack {
    Circle().fill(isOn ? Color.green : Color.gray)
    Image(systemName: isOn ? "checkmark" : "xmark")
}
.onTapGesture { isOn.toggle() }
.accessibilityRepresentation {
    Toggle("Wi-Fi", isOn: $isOn)
}
```

VoiceOver treats this as a native Toggle with all correct traits, value, and behavior. The custom visual remains unchanged.

---

## accessibilityChildren

Create a synthetic accessibility container with children from a different part of the view hierarchy.

```swift
Canvas { context, size in
    // Draw chart bars
}
.accessibilityChildren {
    ForEach(dataPoints) { point in
        Rectangle()
            .accessibilityLabel("\(point.label)")
            .accessibilityValue("\(point.value) units")
    }
}
```

Useful for `Canvas`, custom drawing, or SpriteKit scenes where there are no real SwiftUI subviews.

---

## @AccessibilityFocusState

Programmatically move VoiceOver focus.

```swift
struct FormView: View {
    enum Field: Hashable {
        case name, email, error
    }

    @AccessibilityFocusState private var focusedField: Field?
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            TextField("Name", text: $name)
                .accessibilityFocused($focusedField, equals: .name)

            TextField("Email", text: $email)
                .accessibilityFocused($focusedField, equals: .email)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusedField, equals: .error)
            }

            Button("Submit") {
                if !validate() {
                    errorMessage = "Please enter a valid email"
                    focusedField = .error
                }
            }
        }
    }
}
```

### Boolean Variant

```swift
@AccessibilityFocusState private var isAlertFocused: Bool

Text("New notification received")
    .accessibilityFocused($isAlertFocused)

// Move focus
isAlertFocused = true
```

---

## Sort Priority

Override the default reading order (top-to-bottom, leading-to-trailing).

```swift
HStack {
    // Read second (lower priority = read later)
    StatusIcon()
        .accessibilitySortPriority(1)

    // Read first (higher priority = read sooner)
    Text("Message title")
        .accessibilitySortPriority(2)
}
```

Higher values are read first. Default is 0.

---

## AccessibilityNotification

Post notifications to inform VoiceOver about content changes.

```swift
// Announce a transient message (toast, status update)
AccessibilityNotification.Announcement("Message sent successfully")
    .post()

// Content in the current view changed (focus moves to element if provided)
AccessibilityNotification.LayoutChanged(newContentElement)
    .post()

// Entirely new screen appeared (focus moves to first element)
AccessibilityNotification.ScreenChanged(nil)
    .post()

// Page scrolled — announce new page content
AccessibilityNotification.PageScrolled("Page 3 of 10")
    .post()
```

### Usage Patterns

```swift
// After loading content
func onContentLoaded() {
    isLoading = false
    AccessibilityNotification.LayoutChanged(nil).post()
}

// After showing an error
func showError(_ message: String) {
    errorMessage = message
    // Let VoiceOver read the error
    AccessibilityNotification.Announcement(message).post()
}
```

---

## Hiding from VoiceOver

### Decorative Images

```swift
// SwiftUI decorative initializer — hidden automatically
Image(decorative: "background-gradient")

// SF Symbol used as decoration
Image(systemName: "chevron.right")
    .accessibilityHidden(true)
```

### Container Hiding

```swift
// Hide an entire view subtree
DecorationOverlay()
    .accessibilityHidden(true)
```

### When to Hide

- Background images and patterns
- Redundant icons next to text labels (e.g., chevron in a navigation row)
- Animated decorations (confetti, particle effects)
- Dividers and spacers that VoiceOver would read as blank elements
- Tab bar badges when the count is already in the label

### When NOT to Hide

- Meaningful images (photos, charts, diagrams)
- Status icons (error, warning, success) unless the state is conveyed in text
- Interactive elements (even if they look like decoration)
