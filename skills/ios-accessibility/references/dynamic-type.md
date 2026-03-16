# Dynamic Type Reference

Complete reference for Dynamic Type, @ScaledMetric, layout adaptation, color and contrast, motion, and related accessibility settings.

---

## System Text Styles

Always prefer system text styles. They scale automatically with Dynamic Type.

| Text Style | Default Size (points) | Use For |
|---|---|---|
| `.extraLargeTitle2` | 36 | Hero text (iOS 17+) |
| `.extraLargeTitle` | 34 | Large hero text (iOS 17+) |
| `.largeTitle` | 34 | Screen titles, onboarding |
| `.title` | 28 | Primary section titles |
| `.title2` | 22 | Secondary section titles |
| `.title3` | 20 | Tertiary titles |
| `.headline` | 17 (semibold) | Emphasized body text, row titles |
| `.subheadline` | 15 | Secondary information |
| `.body` | 17 | Primary content text |
| `.callout` | 16 | Callout text, annotations |
| `.footnote` | 13 | Footnotes, timestamps |
| `.caption` | 12 | Captions, labels |
| `.caption2` | 11 | Smallest system text |

```swift
Text("Welcome Back").font(.largeTitle)
Text("Your recent activity").font(.headline)
Text("Last updated 5 minutes ago").font(.caption)
```

---

## Custom Fonts with Dynamic Type

Use `relativeTo:` to make custom fonts scale proportionally with a system text style.

```swift
// Custom font that scales like .body
Text("Hello")
    .font(.custom("Avenir-Medium", size: 17, relativeTo: .body))

// Custom font that scales like .headline
Text("Section Title")
    .font(.custom("Avenir-Heavy", size: 17, relativeTo: .headline))

// Fixed size (does NOT scale — use sparingly)
Text("Fixed")
    .font(.custom("Avenir", fixedSize: 12))
```

When using `relativeTo:`, the `size` parameter is the base size at the default (Large) content size category. The font scales proportionally as the user changes their preferred size.

---

## @ScaledMetric

Scale any numeric value proportionally with Dynamic Type.

```swift
struct ProfileView: View {
    // Scales the avatar size with Dynamic Type
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 60

    // Scales spacing
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    // Scales icon size
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: spacing) {
            Image("avatar")
                .resizable()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text("John Doe").font(.title)
                Text("iOS Developer").font(.subheadline)
            }
        }
    }
}
```

- Use `relativeTo:` to tie scaling to a specific text style.
- Without `relativeTo:`, it scales with `.body` by default.
- Useful for: icon sizes, spacing, padding, border widths, corner radii.

---

## Layout Adaptation for Accessibility Sizes

### Detecting Accessibility Sizes

```swift
@Environment(\.dynamicTypeSize) private var typeSize

var body: some View {
    if typeSize.isAccessibilitySize {
        // Vertical layout for very large text
        VStack(alignment: .leading, spacing: 12) {
            labelContent
            valueContent
        }
    } else {
        // Horizontal layout for normal sizes
        HStack {
            labelContent
            Spacer()
            valueContent
        }
    }
}
```

### Using AnyLayout for Clean Switching

```swift
struct AdaptiveSettingsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let value: String

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())

        layout {
            Text(title)
            if !typeSize.isAccessibilitySize {
                Spacer()
            }
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
```

### ViewThatFits (iOS 16+)

```swift
ViewThatFits {
    // Try horizontal first
    HStack {
        Image(systemName: "star.fill")
        Text("Add to Favorites")
    }
    // Fall back to vertical if horizontal doesn't fit
    VStack {
        Image(systemName: "star.fill")
        Text("Add to Favorites")
    }
}
```

---

## DynamicTypeSize Values

```swift
public enum DynamicTypeSize: Hashable, Comparable, CaseIterable {
    case xSmall              // -3
    case small               // -2
    case medium              // -1
    case large               // 0 (default)
    case xLarge              // +1
    case xxLarge             // +2
    case xxxLarge            // +3
    case accessibility1      // AX1
    case accessibility2      // AX2
    case accessibility3      // AX3
    case accessibility4      // AX4
    case accessibility5      // AX5

    var isAccessibilitySize: Bool  // true for AX1-AX5
}
```

### Limiting Dynamic Type Range

```swift
// Limit maximum size (use sparingly — users chose large sizes for a reason)
Text("Tab Label")
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)

// Limit to a specific range
Text("Fixed Header")
    .dynamicTypeSize(.large ... .xxxLarge)
```

Only limit Dynamic Type when there is a genuine layout constraint that cannot be solved by adapting the layout.

---

## Minimum Touch Targets

Apple Human Interface Guidelines require a minimum of 44x44 points for touch targets.

```swift
// Small icon button — expand the tap area
Button(action: showInfo) {
    Image(systemName: "info.circle")
        .font(.body)
}
.frame(minWidth: 44, minHeight: 44)
.contentShape(.rect)  // Make the entire frame tappable

// Scale touch target with Dynamic Type
@ScaledMetric private var minTarget: CGFloat = 44

Button(action: dismiss) {
    Image(systemName: "xmark")
        .font(.caption)
}
.frame(minWidth: minTarget, minHeight: minTarget)
.contentShape(.rect)
```

### Common Mistake

```swift
// BAD: The icon is only ~20x20 points — too small to tap
Button(action: close) {
    Image(systemName: "xmark")
}

// GOOD: Expanded hit area
Button(action: close) {
    Image(systemName: "xmark")
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
}
```

---

## Color and Contrast

### WCAG Contrast Ratios

| Level | Normal Text | Large Text (18pt+ or 14pt+ bold) |
|---|---|---|
| AA (minimum) | 4.5:1 | 3:1 |
| AAA (enhanced) | 7:1 | 4.5:1 |

- iOS standard controls meet AA. Custom colors must be checked.
- Use Xcode Accessibility Inspector or online contrast checkers.
- Test in both light and dark mode.

### Differentiate Without Color

```swift
@Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

HStack {
    Circle()
        .fill(isOnline ? .green : .gray)
    Text(isOnline ? "Online" : "Offline")

    // Add icon when user has enabled "Differentiate Without Color"
    if differentiateWithoutColor {
        Image(systemName: isOnline ? "checkmark.circle" : "xmark.circle")
            .accessibilityHidden(true) // Text already conveys the state
    }
}
```

### Smart Invert Colors

```swift
@Environment(\.accessibilityInvertColors) private var invertColors

// Prevent images and media from being inverted
Image("photo")
    .accessibilityIgnoresInvertColors(true)

AsyncImage(url: avatarURL) { image in
    image.accessibilityIgnoresInvertColors(true)
} placeholder: {
    ProgressView()
}
```

Apply `.accessibilityIgnoresInvertColors(true)` to:
- Photos and user-generated images
- Videos and media players
- Maps
- App icons and logos with specific brand colors

---

## Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// Replace spring animation with simple fade
withAnimation(reduceMotion ? .none : .spring(duration: 0.5)) {
    isExpanded.toggle()
}

// Conditional transition
.transition(reduceMotion ? .opacity : .slide)

// Disable auto-playing animations
TimelineView(.animation(paused: reduceMotion)) { context in
    AnimatedBackground(time: context.date)
}
```

### What to Change When Reduce Motion is On

| Normal | Reduced Motion Alternative |
|---|---|
| Slide transitions | Crossfade (`.opacity`) |
| Spring animations | `.easeInOut` or `.none` |
| Parallax effects | Static |
| Auto-playing animations | Paused (play button shown) |
| Bouncing indicators | Static indicator |
| Hero transitions | Simple fade |

---

## Reduce Transparency

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

Rectangle()
    .fill(reduceTransparency ? .background : .ultraThinMaterial)
```

When Reduce Transparency is on, replace `.ultraThinMaterial`, `.thinMaterial`, etc. with solid backgrounds.

---

## Bold Text

```swift
@Environment(\.legibilityWeight) private var legibilityWeight

Text("Important")
    .fontWeight(legibilityWeight == .bold ? .bold : .regular)
```

Most system text automatically responds to Bold Text. Custom `fontWeight` may need manual handling.

---

## Button Shapes

```swift
@Environment(\.accessibilityShowButtonShapes) private var showButtonShapes

// System Button and Link controls automatically show underlines/shapes.
// Custom interactive elements may need manual handling:
Text("Learn more")
    .underline(showButtonShapes)
    .onTapGesture { showHelp() }
    .accessibilityAddTraits(.isLink)
```

---

## Large Content Viewer

For elements that do not scale with Dynamic Type (tab bars, toolbars, segmented controls), the Large Content Viewer shows a HUD when the user long-presses.

```swift
// Text-based large content
HStack {
    Image(systemName: "house")
    Text("Home")
}
.accessibilityShowsLargeContentViewer {
    Label("Home", systemImage: "house")
}

// Image-based large content
Button(action: search) {
    Image(systemName: "magnifyingglass")
}
.accessibilityShowsLargeContentViewer {
    Label("Search", systemImage: "magnifyingglass")
}
```

Use this for:
- Custom tab bars that don't scale
- Toolbar buttons
- Status bar items
- Any fixed-size control in accessibility sizes
