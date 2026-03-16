# SwiftUI Animation Reference

## Implicit Animation

Attach `.animation()` to a view. Any change to the specified value animates all animatable properties.

```swift
struct PulsingCircle: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: isExpanded ? 200 : 100, height: isExpanded ? 200 : 100)
            .opacity(isExpanded ? 0.7 : 1.0)
            .animation(.spring(duration: 0.5, bounce: 0.3), value: isExpanded)
            .onTapGesture { isExpanded.toggle() }
    }
}
```

**Rule:** Always use `.animation(_:value:)` (with value parameter). The deprecated `.animation(_:)` without a value applies to ALL state changes, causing unexpected animations.

---

## Explicit Animation

Wrap state changes in `withAnimation` to animate all views affected by that change.

```swift
Button("Toggle") {
    withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
        isExpanded.toggle()
    }
}
```

### Completion Handler (iOS 17+)

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    isVisible = false
} completion: {
    // runs after animation finishes
    removeItem()
}
```

**When to use which:**
- **Implicit** (`.animation`): Animate one specific view property tied to one value
- **Explicit** (`withAnimation`): Animate multiple views or coordinate changes

---

## Animation Types

### Spring Animations (Preferred)

```swift
.spring()                                     // default spring
.spring(duration: 0.5, bounce: 0.3)           // custom duration and bounciness
.spring(response: 0.5, dampingFraction: 0.7)  // physics-based

// Presets (iOS 17+)
.bouncy                           // .spring(duration: 0.5, bounce: 0.3)
.bouncy(duration: 0.4)
.smooth                           // .spring(duration: 0.5, bounce: 0)
.smooth(duration: 0.3)
.snappy                           // .spring(duration: 0.35, bounce: 0.15)
.snappy(duration: 0.25)

// Interactive spring (for gesture-driven animations)
.interactiveSpring(response: 0.3, dampingFraction: 0.8)
```

### Timing Curve Animations

```swift
.easeInOut(duration: 0.3)
.easeIn(duration: 0.3)
.easeOut(duration: 0.3)
.linear(duration: 0.3)
```

### Animation Modifiers

```swift
.animation(.spring().delay(0.2))          // start after 0.2s
.animation(.spring().speed(1.5))          // 1.5x speed
.animation(.linear(duration: 1).repeatCount(3, autoreverses: true))
.animation(.linear(duration: 1).repeatForever(autoreverses: true))
```

---

## Transitions

Define how a view appears/disappears when inserted/removed from the hierarchy.

```swift
struct NotificationBanner: View {
    @State private var showBanner = false

    var body: some View {
        VStack {
            if showBanner {
                BannerView()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(duration: 0.4), value: showBanner)
    }
}
```

### Built-in Transitions

```swift
.transition(.opacity)                    // fade in/out
.transition(.scale)                      // scale from center
.transition(.scale(scale: 0.5, anchor: .bottom))
.transition(.slide)                      // slide from leading edge
.transition(.move(edge: .top))           // slide from specific edge
.transition(.push(from: .bottom))        // iOS 16+, push with offset
.transition(.offset(x: 100, y: 0))      // specific offset
```

### Combining and Asymmetric Transitions

```swift
// Combined — both applied
.transition(.scale.combined(with: .opacity))

// Asymmetric — different insert and removal
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
))
```

### Custom Transition

```swift
struct SlideAndFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(y: phase == .willAppear ? 30 : (phase == .didDisappear ? -30 : 0))
    }
}

extension AnyTransition {
    static var slideAndFade: AnyTransition {
        .modifier(
            active: SlideAndFadeModifier(opacity: 0, offsetY: 30),
            identity: SlideAndFadeModifier(opacity: 1, offsetY: 0)
        )
    }
}
```

---

## matchedGeometryEffect

Creates a seamless "hero" animation between two views by morphing one into the other.

```swift
struct CardExpansion: View {
    @Namespace private var animation
    @State private var isExpanded = false
    @State private var selectedItem: Item?

    var body: some View {
        ZStack {
            if let item = selectedItem {
                // Expanded state
                ExpandedCardView(item: item)
                    .matchedGeometryEffect(id: item.id, in: animation)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                            selectedItem = nil
                        }
                    }
            } else {
                // Grid of cards
                LazyVGrid(columns: columns) {
                    ForEach(items) { item in
                        CardView(item: item)
                            .matchedGeometryEffect(id: item.id, in: animation)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                                    selectedItem = item
                                }
                            }
                    }
                }
            }
        }
    }
}
```

**Rules:**
- Use `@Namespace` to create the namespace
- The `id` must be the same for both source and destination views
- Only ONE view with a given `id` should have `isSource: true` (default) at a time
- Wrap the state change in `withAnimation` for the transition to animate
- Works best when both views exist in a `ZStack` or `if/else` within the same parent

### Matched Geometry for Tab Indicator

```swift
struct CustomTabBar: View {
    @Namespace private var tabAnimation
    @State private var selectedTab = 0
    let tabs = ["Home", "Search", "Profile"]

    var body: some View {
        HStack {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                Button(title) {
                    withAnimation(.snappy) { selectedTab = index }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background {
                    if selectedTab == index {
                        Capsule()
                            .fill(.blue.opacity(0.2))
                            .matchedGeometryEffect(id: "tab", in: tabAnimation)
                    }
                }
            }
        }
    }
}
```

---

## PhaseAnimator (iOS 17+)

Automatically cycles through a sequence of phases, applying different modifiers at each phase.

```swift
struct PulsingIcon: View {
    var body: some View {
        PhaseAnimator([false, true]) { phase in
            Image(systemName: "heart.fill")
                .font(.largeTitle)
                .foregroundStyle(phase ? .red : .pink)
                .scaleEffect(phase ? 1.2 : 1.0)
        } animation: { phase in
            phase ? .spring(duration: 0.3) : .spring(duration: 0.6)
        }
    }
}
```

### With Trigger (animates on value change)

```swift
struct CelebrationEffect: View {
    @State private var triggerCount = 0

    var body: some View {
        VStack {
            PhaseAnimator(CelebrationPhase.allCases, trigger: triggerCount) { phase in
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .scaleEffect(phase.scale)
                    .rotationEffect(.degrees(phase.rotation))
                    .foregroundStyle(phase.color)
            } animation: { phase in
                switch phase {
                case .initial: .spring(duration: 0.1)
                case .grow: .spring(duration: 0.3, bounce: 0.5)
                case .spin: .easeInOut(duration: 0.4)
                case .settle: .spring(duration: 0.5)
                }
            }

            Button("Celebrate") { triggerCount += 1 }
        }
    }
}

enum CelebrationPhase: CaseIterable {
    case initial, grow, spin, settle

    var scale: CGFloat {
        switch self {
        case .initial: 1.0
        case .grow: 1.8
        case .spin: 1.5
        case .settle: 1.0
        }
    }

    var rotation: Double {
        switch self {
        case .initial: 0
        case .grow: 0
        case .spin: 360
        case .settle: 360
        }
    }

    var color: Color {
        switch self {
        case .initial: .yellow
        case .grow: .orange
        case .spin: .red
        case .settle: .yellow
        }
    }
}
```

---

## KeyframeAnimator (iOS 17+)

Fine-grained control over animation timing. Each track animates one property independently.

```swift
struct BounceEffect: View {
    @State private var trigger = false

    var body: some View {
        Text("Hello!")
            .font(.largeTitle)
            .keyframeAnimator(initialValue: AnimationValues(), trigger: trigger) { content, value in
                content
                    .scaleEffect(y: value.verticalStretch)
                    .offset(y: value.offsetY)
            } keyframes: { _ in
                KeyframeTrack(\.offsetY) {
                    SpringKeyframe(-100, duration: 0.3, spring: .bouncy)
                    CubicKeyframe(0, duration: 0.2)
                    SpringKeyframe(-40, duration: 0.2, spring: .bouncy)
                    CubicKeyframe(0, duration: 0.15)
                }

                KeyframeTrack(\.verticalStretch) {
                    LinearKeyframe(0.8, duration: 0.1)
                    SpringKeyframe(1.2, duration: 0.2, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                }
            }
            .onTapGesture { trigger.toggle() }
    }
}

struct AnimationValues {
    var offsetY: CGFloat = 0
    var verticalStretch: CGFloat = 1.0
}
```

### Keyframe Types

```swift
LinearKeyframe(targetValue, duration: 0.3)       // linear interpolation
SpringKeyframe(targetValue, duration: 0.3, spring: .bouncy)  // spring physics
CubicKeyframe(targetValue, duration: 0.3)        // cubic ease
MoveKeyframe(targetValue)                        // instant jump (no interpolation)
```

---

## sensoryFeedback (iOS 17+)

Haptic feedback tied to value changes.

```swift
.sensoryFeedback(.impact, trigger: tapCount)
.sensoryFeedback(.success, trigger: isCompleted)
.sensoryFeedback(.warning, trigger: errorOccurred)
.sensoryFeedback(.error, trigger: failedAttempts)
.sensoryFeedback(.selection, trigger: selectedIndex)
.sensoryFeedback(.increase, trigger: value)
.sensoryFeedback(.decrease, trigger: value)

// Conditional feedback
.sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: dropCompleted) { oldValue, newValue in
    newValue == true  // only trigger when becoming true
}
```

---

## SymbolEffect (iOS 17+)

Animate SF Symbols with built-in effects.

```swift
// Continuous effects
Image(systemName: "wifi")
    .symbolEffect(.variableColor.iterative)

Image(systemName: "bell.fill")
    .symbolEffect(.pulse)

Image(systemName: "arrow.down.circle")
    .symbolEffect(.bounce, value: downloadCount)

// Triggered effects
Image(systemName: "checkmark.circle")
    .symbolEffect(.bounce, value: isComplete)

// Replace with animation
Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    .contentTransition(.symbolEffect(.replace))

// Discrete effects — appear/disappear
Image(systemName: "bell.fill")
    .symbolEffect(.bounce.up, options: .repeating, value: hasNotification)

// Multiple options
Image(systemName: "wifi")
    .symbolEffect(.variableColor.iterative.reversing, options: .repeat(3).speed(2))
```

### Symbol Effect Types

| Effect | Behavior |
|---|---|
| `.bounce` | Spring bounce (one-shot, trigger with value) |
| `.pulse` | Gentle pulse (continuous) |
| `.variableColor` | Animate layers of multi-layer symbols |
| `.scale` | Scale up/down |
| `.appear` / `.disappear` | Fade + scale in/out |
| `.replace` | Cross-fade between symbols (via `.contentTransition`) |

---

## ContentTransition

Animate changes between different content within the same view.

```swift
Text("\(count)")
    .contentTransition(.numericText())        // smooth number transitions
    .contentTransition(.numericText(value: count))  // direction-aware (iOS 17+)

Image(systemName: isFavorite ? "heart.fill" : "heart")
    .contentTransition(.symbolEffect(.replace))

Text(status.description)
    .contentTransition(.interpolate)           // morph between text
```

---

## Practical Examples

### Staggered List Animation

```swift
struct StaggeredList: View {
    @State private var items: [Item] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ItemRow(item: item)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .animation(.spring(duration: 0.4).delay(Double(index) * 0.05),
                                   value: items.count)
                }
            }
        }
        .task {
            withAnimation {
                items = await fetchItems()
            }
        }
    }
}
```

### Animated Tab Switching

```swift
struct AnimatedContentView: View {
    @State private var selectedTab = 0
    @Namespace private var namespace

    var body: some View {
        VStack(spacing: 0) {
            // Tab content with transition
            TabView(selection: $selectedTab) {
                HomeTab().tag(0)
                SearchTab().tag(1)
                ProfileTab().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.smooth, value: selectedTab)

            // Custom tab bar
            HStack {
                ForEach(0..<3) { index in
                    tabButton(index: index)
                }
            }
            .padding()
        }
    }

    func tabButton(index: Int) -> some View {
        Button {
            withAnimation(.snappy) { selectedTab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tabIcon(index))
                    .symbolEffect(.bounce, value: selectedTab == index)
                if selectedTab == index {
                    Capsule()
                        .fill(.blue)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "indicator", in: namespace)
                }
            }
        }
    }
}
```
