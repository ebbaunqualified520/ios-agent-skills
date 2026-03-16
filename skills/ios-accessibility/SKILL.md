---
name: ios-accessibility
description: >
  iOS accessibility (a11y) expert skill covering VoiceOver support (labels, hints, values, traits, custom actions,
  rotors, focus management), Dynamic Type (text styles, @ScaledMetric, layout adaptation for large sizes),
  color and contrast (WCAG ratios, Differentiate Without Color, Smart Invert), motion and reduce motion,
  accessibility auditing (Xcode Inspector, XCTest performAccessibilityAudit), and SwiftUI accessibility modifiers.
  Use this skill whenever the user implements accessibility features, needs VoiceOver support, handles Dynamic Type,
  adds accessibility labels, or audits an app for a11y compliance. Triggers on: accessibility, a11y, VoiceOver,
  Dynamic Type, accessibilityLabel, accessibilityHint, accessibilityValue, accessibilityTraits, accessibilityAction,
  accessibilityIdentifier, screen reader, assistive technology, reduce motion, high contrast, accessible, WCAG,
  touch target, font scaling, @ScaledMetric, accessibilityElement, AX audit, inclusive design, or any iOS
  accessibility question.
---

# iOS Accessibility Skill

## Core Rules

1. **EVERY interactive element must have a meaningful `accessibilityLabel`.**
   Never use generic labels like "button", "image", or "icon". Describe what it does: "Delete message", "Add to favorites", "Share photo".

2. **Use native SwiftUI controls** (`Button`, `Toggle`, `Link`, `Picker`, `Slider`, `Stepper`) whenever possible. They carry correct accessibility traits automatically.

3. **Custom views with `onTapGesture` MUST add `.accessibilityAddTraits(.isButton)`.**
   Better yet, wrap them in a `Button` so VoiceOver announces them as interactive.

4. **Decorative images must be hidden from VoiceOver.**
   Use `Image(decorative:)` or `.accessibilityHidden(true)`. Never let VoiceOver read "image" for decorative content.

5. **Support Dynamic Type at ALL sizes** including accessibility sizes (AX1-AX5). Use system text styles (`.body`, `.title`, `.headline`) and `@ScaledMetric` for custom dimensions.

6. **Minimum touch target: 44x44 points.** Use `.frame(minWidth: 44, minHeight: 44)` and `.contentShape(.rect)` to expand small icons.

7. **Never re-prompt after `.userCancel`.** When the user dismisses a biometric prompt or permission dialog, respect their decision. Do not show the prompt again immediately.

8. **Test with VoiceOver on a real device**, not just the Simulator. The Simulator does not fully replicate VoiceOver behavior, gestures, or focus management.

9. **Run `performAccessibilityAudit()` in UI tests.** Automated audits catch contrast issues, missing labels, small hit regions, and clipped text.

10. **Add `NSFaceIDUsageDescription`** to Info.plist when using Face ID. Without it the app crashes on first biometric attempt.

11. **Color must not be the sole indicator.** Always pair color with text, icons, or shapes. Check `accessibilityDifferentiateWithoutColor`.

12. **Respect Reduce Motion.** Check `accessibilityReduceMotion` and provide crossfade alternatives to spring/slide animations.

13. **Logical reading order matters.** VoiceOver reads left-to-right, top-to-bottom. Use `.accessibilitySortPriority()` to fix order when layout does not match logical flow.

14. **Move focus to important changes.** When an error appears or content updates, post `AccessibilityNotification.LayoutChanged` or use `@AccessibilityFocusState`.

15. **Group related elements** with `.accessibilityElement(children: .combine)` to reduce swipe count and create meaningful compound descriptions.

---

## Quick Checklist

Before shipping any screen, verify:

- [ ] Every `Button`, `Link`, and tappable element has an `accessibilityLabel`
- [ ] Decorative images use `Image(decorative:)` or `.accessibilityHidden(true)`
- [ ] Section headers are marked with `.accessibilityAddTraits(.isHeader)`
- [ ] Dynamic Type renders correctly at all sizes including `.accessibilityExtraExtraExtraLarge`
- [ ] Touch targets are at least 44x44 points
- [ ] Color is not the only way to convey information (errors, status, selection)
- [ ] Animations respect `accessibilityReduceMotion`
- [ ] Complex interactions have custom actions as swipe alternatives
- [ ] Reading order is logical (matches visual and semantic order)
- [ ] Focus moves to errors, alerts, or newly inserted content
- [ ] Modal views use `.accessibilityAddTraits(.isModal)` to trap focus
- [ ] Adjustable controls (sliders, steppers) work with swipe up/down
- [ ] `accessibilityValue` reflects current state for toggles and sliders
- [ ] `accessibilityHint` is set for non-obvious actions (starts with verb phrase)
- [ ] UI tests include `performAccessibilityAudit()`

---

## SwiftUI Accessibility Modifier Quick Reference

### Labels, Hints, Values

```swift
// Static label
.accessibilityLabel("Delete message")

// Closure label (iOS 18+)
.accessibilityLabel { label in
    Text("Unread") + label
}

// Hint — describes the result of activating
.accessibilityHint("Double tap to delete this message")

// Value — current state of a control
.accessibilityValue("50 percent")

// Input labels — Voice Control alternate names
.accessibilityInputLabels(["Delete", "Remove", "Trash"])
```

### Traits

```swift
.accessibilityAddTraits(.isButton)
.accessibilityAddTraits(.isHeader)
.accessibilityAddTraits(.isLink)
.accessibilityAddTraits(.isSelected)
.accessibilityAddTraits(.isImage)
.accessibilityRemoveTraits(.isImage)
```

### Grouping and Hiding

```swift
// Combine children into one element
.accessibilityElement(children: .combine)

// Hide from VoiceOver
.accessibilityHidden(true)

// Decorative image (hidden automatically)
Image(decorative: "background-pattern")

// Replace entire subtree with custom element
.accessibilityRepresentation {
    Toggle("Wi-Fi", isOn: $isEnabled)
}
```

### Actions

```swift
// Named action (appears in custom actions rotor)
.accessibilityAction(named: "Mark as read") {
    markAsRead()
}

// Adjustable (swipe up/down)
.accessibilityAdjustableAction { direction in
    switch direction {
    case .increment: value += 1
    case .decrement: value -= 1
    @unknown default: break
    }
}
```

### Focus Management

```swift
@AccessibilityFocusState private var isFocused: Bool

TextField("Name", text: $name)
    .accessibilityFocused($isFocused)

// Move focus programmatically
Button("Show Error") {
    errorMessage = "Invalid input"
    isFocused = true
}
```

### Dynamic Type Support

```swift
// System text style (scales automatically)
Text("Hello").font(.body)

// Custom font that scales with Dynamic Type
Text("Hello").font(.custom("Avenir", size: 17, relativeTo: .body))

// Scaled dimension
@ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

// Respond to accessibility sizes
@Environment(\.dynamicTypeSize) private var typeSize

if typeSize.isAccessibilitySize {
    // Switch to vertical layout
}
```

---

## Common Patterns

### Card with Combined Accessibility

```swift
VStack(alignment: .leading) {
    Text(item.title).font(.headline)
    Text(item.subtitle).font(.subheadline)
    Text(item.date).font(.caption)
}
.accessibilityElement(children: .combine)
.accessibilityAddTraits(.isButton)
.accessibilityHint("Double tap to view details")
```

### Custom Toggle

```swift
// BAD: VoiceOver does not know this is interactive
HStack {
    Text("Dark Mode")
    Image(systemName: isDark ? "moon.fill" : "moon")
}
.onTapGesture { isDark.toggle() }

// GOOD: Use a real Toggle
Toggle("Dark Mode", isOn: $isDark)

// GOOD: If custom UI is needed, add representation
HStack {
    Text("Dark Mode")
    Image(systemName: isDark ? "moon.fill" : "moon")
}
.onTapGesture { isDark.toggle() }
.accessibilityRepresentation {
    Toggle("Dark Mode", isOn: $isDark)
}
```

### Swipeable List Row with Actions

```swift
ForEach(messages) { message in
    MessageRow(message: message)
        .accessibilityAction(named: "Delete") {
            delete(message)
        }
        .accessibilityAction(named: "Archive") {
            archive(message)
        }
        .accessibilityAction(named: "Mark as read") {
            markAsRead(message)
        }
}
```

### Error Announcement

```swift
@AccessibilityFocusState private var isErrorFocused: Bool

VStack {
    TextField("Email", text: $email)

    if let error = validationError {
        Text(error)
            .foregroundStyle(.red)
            .accessibilityFocused($isErrorFocused)
    }

    Button("Submit") {
        if !validate() {
            isErrorFocused = true
        }
    }
}
```

### Responsive Layout for Large Type

```swift
struct AdaptiveRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Image(systemName: "star.fill")
                .accessibilityHidden(true)
            Text("Favorites")
            Spacer()
            Text("12 items")
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## References

For detailed API coverage, see:

- [VoiceOver](references/voiceover.md) — labels, hints, values, traits, actions, rotors, focus
- [Dynamic Type](references/dynamic-type.md) — text styles, @ScaledMetric, layout adaptation, color and contrast, motion
- [Auditing](references/auditing.md) — Xcode Inspector, XCTest audits, environment values, best practices
