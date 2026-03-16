# SwiftUI Performance Reference

## View Identity

SwiftUI uses two types of identity to track views across updates:

### Structural Identity (Default)
SwiftUI infers identity from a view's position in the view hierarchy. The first `Text` in a `VStack` is always "the first Text" across body evaluations.

```swift
var body: some View {
    VStack {
        Text("Hello")    // Identity: VStack.child[0]
        Text("World")    // Identity: VStack.child[1]
    }
}
```

**Problem with conditional views**: `if/else` changes the view type, so SwiftUI treats it as a **different view** — destroying state and re-creating.

```swift
// BAD: State destroyed on toggle (different view types in if/else)
var body: some View {
    if isLoggedIn {
        ProfileView()   // Type: _ConditionalContent<ProfileView, LoginView>.TrueContent
    } else {
        LoginView()     // Type: _ConditionalContent<ProfileView, LoginView>.FalseContent
    }
}

// BETTER: Use opacity or offset to maintain identity
var body: some View {
    ZStack {
        ProfileView().opacity(isLoggedIn ? 1 : 0)
        LoginView().opacity(isLoggedIn ? 0 : 1)
    }
}
```

### Explicit Identity (ForEach, .id())
Use stable, unique identifiers for `ForEach` to enable efficient diffing.

```swift
// BAD: Using array index as id — inserts/deletes cause wrong animations
ForEach(Array(items.enumerated()), id: \.offset) { index, item in
    ItemRow(item: item)
}

// BAD: Using unstable id (random, hash of mutable data)
ForEach(items, id: \.hashValue) { item in
    ItemRow(item: item)
}

// GOOD: Stable, unique identifier
struct Item: Identifiable {
    let id: UUID  // Stable across updates
    var name: String
}

ForEach(items) { item in  // Uses item.id automatically
    ItemRow(item: item)
}
```

### .id() Modifier — Identity Reset
Changing a view's `.id()` tells SwiftUI it's a **new view** — all state is destroyed and recreated.

```swift
// Force ScrollView to scroll to top when category changes
ScrollView {
    content
}
.id(selectedCategory)  // New category = new ScrollView = scroll position reset

// Force view recreation (useful for resetting complex state)
ComplexEditorView(document: doc)
    .id(doc.id)  // New document = fresh editor state
```

## Avoiding Unnecessary Redraws

### Rule 1: Extract Subviews to Localize Invalidation

When a `@State` or `@Binding` changes, SwiftUI re-evaluates the **entire body** of the view owning that state. Smaller views = less re-evaluation.

```swift
// BAD: Counter change re-evaluates entire view including expensive list
struct DashboardView: View {
    @State private var counter = 0
    @State private var items: [Item] = []

    var body: some View {
        VStack {
            Text("Count: \(counter)")     // Changed
            Button("+1") { counter += 1 }

            // This expensive section is ALSO re-evaluated!
            ForEach(items) { item in
                ComplexItemView(item: item)
            }
        }
    }
}

// GOOD: Counter is isolated — items list NOT re-evaluated
struct DashboardView: View {
    var body: some View {
        VStack {
            CounterSection()  // Only this re-evaluates on counter change
            ItemsSection()    // Untouched
        }
    }
}

struct CounterSection: View {
    @State private var counter = 0

    var body: some View {
        VStack {
            Text("Count: \(counter)")
            Button("+1") { counter += 1 }
        }
    }
}
```

### Rule 2: Minimize State Scope

Place `@State` in the **lowest possible** view in the hierarchy. State should live where it's used, not at the top.

```swift
// BAD: Search text state at navigation level — every keystroke re-evaluates tabs
struct MainTabView: View {
    @State private var searchText = ""  // Too high in hierarchy!

    var body: some View {
        TabView {
            SearchView(searchText: $searchText)  // Re-evaluates all tabs
            SettingsView()                        // on every keystroke
        }
    }
}

// GOOD: Search text state in SearchView — only search re-evaluates
struct SearchView: View {
    @State private var searchText = ""  // Scoped to where it's used

    var body: some View {
        VStack {
            TextField("Search", text: $searchText)
            ResultsList(query: searchText)
        }
    }
}
```

### Rule 3: Use let Properties for Unchanging Data

Views initialized with `let` properties only re-evaluate when the parent passes new values.

```swift
// This view only re-evaluates if the parent passes a different Post
struct PostRow: View {
    let post: Post  // Immutable — no internal state changes

    var body: some View {
        VStack(alignment: .leading) {
            Text(post.title).font(.headline)
            Text(post.summary).font(.subheadline)
        }
    }
}
```

## EquatableView and .equatable()

Use `EquatableView` to give SwiftUI a custom equality check — it skips body evaluation if the view is "equal" to its previous value.

```swift
// Conform to Equatable with custom logic
struct ExpensiveChartView: View, Equatable {
    let dataPoints: [DataPoint]
    let title: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Only re-render if data actually changed (ignore title changes)
        lhs.dataPoints.count == rhs.dataPoints.count &&
        lhs.dataPoints.last?.value == rhs.dataPoints.last?.value
    }

    var body: some View {
        // Expensive chart rendering
        Chart(dataPoints) { point in
            LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
        }
    }
}

// Usage: wrap in EquatableView
EquatableView(content: ExpensiveChartView(dataPoints: data, title: title))

// Or use the modifier
ExpensiveChartView(dataPoints: data, title: title)
    .equatable()
```

**Caveats**:
- Only use when body evaluation is genuinely expensive
- The equality check itself must be fast (don't compare 10,000 elements)
- Not needed for simple views — SwiftUI already optimizes well
- Behavior may differ between SwiftUI versions

## @Observable vs ObservableObject

### ObservableObject (iOS 14+) — Coarse-Grained Updates

```swift
class UserStore: ObservableObject {
    @Published var name = "Alice"
    @Published var email = "alice@example.com"
    @Published var avatar: UIImage?
    @Published var settings = Settings()
}

struct ProfileHeader: View {
    @ObservedObject var store: UserStore

    var body: some View {
        // This body re-evaluates when ANY @Published property changes
        // Even if only `settings` changed, this view re-evaluates
        Text(store.name)
    }
}
```

### @Observable (iOS 17+) — Fine-Grained Updates

```swift
@Observable
class UserStore {
    var name = "Alice"
    var email = "alice@example.com"
    var avatar: UIImage?
    var settings = Settings()
}

struct ProfileHeader: View {
    var store: UserStore  // No property wrapper needed

    var body: some View {
        // This body ONLY re-evaluates when `name` changes
        // Changes to email, avatar, settings do NOT trigger this view
        Text(store.name)
    }
}
```

### Migration Guidance

| Aspect | ObservableObject | @Observable |
|--------|-----------------|-------------|
| Minimum iOS | 14 | 17 |
| Observation granularity | Per-object (any change) | Per-property (only accessed) |
| View wrapper | `@ObservedObject` / `@StateObject` | None (or `@Bindable` for bindings) |
| Property annotation | `@Published` | None needed |
| Environment | `@EnvironmentObject` | `@Environment` |
| Computed properties | Not observable | Observable (if they read observed stored props) |
| Collections of models | Each change triggers | Only accessed items trigger |

### Performance Impact

For a view model with 10 properties and 5 views each reading 2 properties:
- **ObservableObject**: Any property change → all 5 views re-evaluate = up to 5 unnecessary updates
- **@Observable**: Property change → only views reading that property re-evaluate = 0-1 unnecessary updates

## LazyVStack vs VStack vs List

| Container | Creates Views | Cell Reuse | Best For |
|-----------|--------------|------------|----------|
| `VStack` | All at once | No | <50 items, simple content |
| `LazyVStack` | On demand | No | 50-10,000 items in ScrollView |
| `List` | On demand | Yes | 10,000+ items, swipe actions, sections |

### Decision Guide

```swift
// <50 static items: VStack is fine
VStack {
    ForEach(menuItems) { item in  // 15 items — all created, no issue
        MenuRow(item: item)
    }
}

// 50-10,000 items: LazyVStack in ScrollView
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(posts) { post in  // 2,000 posts — only visible ones created
            PostCard(post: post)
        }
    }
}

// 10,000+ items or need swipe/edit: List
List {
    ForEach(contacts) { contact in  // 50,000 contacts — cells reused
        ContactRow(contact: contact)
    }
    .onDelete { offsets in /* ... */ }
}
```

### LazyVStack Gotchas

```swift
// GOTCHA 1: Avoid .id() that changes — forces full rebuild
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item)
            .id(item.hashValue)  // If items mutate, ALL cells rebuild!
    }
}

// GOTCHA 2: GeometryReader inside LazyVStack — measured at zero initially
// The cell size is unknown until scrolled into view. Use fixed sizes when possible.

// GOTCHA 3: ScrollViewReader + scrollTo with LazyVStack
// Cannot scroll to items that haven't been created yet.
// Workaround: use List or set a fixedSize on LazyVStack items.
```

## Image Optimization

### AsyncImage Limitations
- No disk caching (re-downloads on every appearance)
- No cancellation customization
- No placeholder sizing before load
- No progressive loading

```swift
// Built-in AsyncImage — fine for prototyping, NOT for production lists
AsyncImage(url: imageURL) { phase in
    switch phase {
    case .success(let image):
        image.resizable().aspectRatio(contentMode: .fill)
    case .failure:
        Image(systemName: "photo")
    case .empty:
        ProgressView()
    @unknown default:
        EmptyView()
    }
}
.frame(width: 80, height: 80)
.clipped()
```

### Production Image Loading (Nuke)

```swift
import NukeUI

// Nuke: disk + memory cache, deduplication, progressive JPEG, resize pipeline
LazyImage(url: imageURL) { state in
    if let image = state.image {
        image.resizable().aspectRatio(contentMode: .fill)
    } else {
        Color.gray.opacity(0.2)  // Placeholder with correct size
    }
}
.processors([.resize(width: 160)])  // Downsample before decode
.priority(.high)
.frame(width: 80, height: 80)
.clipped()
```

### Image Format Comparison

| Format | Size vs JPEG | Decode Speed | iOS Support | Best For |
|--------|-------------|--------------|-------------|----------|
| JPEG | baseline | fast | All | Photos, complex images |
| PNG | 2-5x larger | fast | All | Screenshots, transparency |
| WebP | 25-34% smaller | medium | iOS 14+ | Network images |
| HEIF | ~50% smaller | medium | iOS 11+ | Photo library, on-device |
| AVIF | 50-60% smaller | slow | iOS 16+ | Bandwidth-constrained |
| SVG | tiny (vector) | CPU-dependent | iOS 13+ (limited) | Icons, simple graphics |

### Downsampling (Critical for Memory)

A 4000x3000 photo decoded at full resolution consumes ~48MB of memory (4000 * 3000 * 4 bytes). If displayed at 160x120 points, that's 47.9MB wasted.

```swift
// Downsample at decode time — use only needed memory
func downsample(imageAt url: URL, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
    let maxDimension = max(pointSize.width, pointSize.height) * scale
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    return UIImage(cgImage: cgImage)
}
```

## .task Modifier vs .onAppear

### .onAppear + Task (Manual Cancellation)

```swift
// BAD: Task continues running after view disappears
struct UserView: View {
    @State private var user: User?

    var body: some View {
        content
            .onAppear {
                Task {
                    user = try? await api.fetchUser(id)
                    // If view disappears during fetch, result is discarded
                    // but the network request completed unnecessarily
                }
            }
    }
}
```

### .task (Auto-Cancellation)

```swift
// GOOD: Task automatically cancelled when view disappears
struct UserView: View {
    let userID: String
    @State private var user: User?

    var body: some View {
        content
            .task {
                // Cancelled automatically if view disappears
                user = try? await api.fetchUser(userID)
            }
    }
}

// BETTER: .task(id:) restarts when dependency changes
struct UserView: View {
    let userID: String
    @State private var user: User?

    var body: some View {
        content
            .task(id: userID) {
                // Restarts when userID changes (previous task cancelled)
                user = try? await api.fetchUser(userID)
            }
    }
}
```

### Task Cancellation Handling

```swift
.task {
    do {
        let data = try await api.fetchLargeDataset()

        // Check cancellation before expensive processing
        try Task.checkCancellation()

        let processed = try await process(data)
        self.results = processed
    } catch is CancellationError {
        // View disappeared — no action needed
    } catch {
        self.errorMessage = error.localizedDescription
    }
}
```

## Profiling SwiftUI with Instruments

### SwiftUI Instrument (Xcode 16+ / WWDC 2023-2025)

The dedicated SwiftUI instrument shows:
- **Body evaluations**: how many times each view's body is called and why
- **Cause & Effect graph**: traces which state change caused which view update
- **Hitch risk**: identifies views likely to cause frame drops
- **View identity changes**: when SwiftUI destroys and recreates views

### What to Look For

1. **High body evaluation count**: A view re-evaluating 100x per second is suspect
2. **Cascading updates**: One state change causing 20+ view updates
3. **Expensive body**: A single body evaluation taking >2ms
4. **Identity thrashing**: Views being destroyed/recreated unnecessarily

### Debugging Tips

```swift
// Add to any view to see when body is evaluated
let _ = Self._printChanges()  // Prints which property triggered re-evaluation

// Example output:
// CounterView: @self, @identity, _count changed.
// ProfileView: @self changed.  ← re-evaluated but no state changed — parent rebuilt it
```

### Performance Testing

```swift
// Measure view creation time
func testListPerformance() {
    let items = (0..<1000).map { Item(id: $0, name: "Item \($0)") }

    measure {
        let _ = List(items) { item in
            ItemRow(item: item)
        }
    }
}
```

## SwiftUI Performance Checklist

- [ ] Views are small (body evaluations are cheap)
- [ ] `@State` lives at the lowest possible level
- [ ] `ForEach` uses stable, unique identifiers
- [ ] Large lists use `LazyVStack` or `List`
- [ ] Images are downsampled to display size
- [ ] Production image loading uses caching library (Nuke/SDWebImage)
- [ ] `.task` used instead of `.onAppear` + `Task {}`
- [ ] `@Observable` used instead of `ObservableObject` (iOS 17+)
- [ ] No `VStack` with 100+ items in `ScrollView`
- [ ] No `GeometryReader` where `fixedSize` or `frame` works
- [ ] `Self._printChanges()` checked for unexpected re-evaluations
- [ ] Profiled with SwiftUI instrument on real device
