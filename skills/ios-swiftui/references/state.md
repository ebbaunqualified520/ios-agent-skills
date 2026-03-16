# SwiftUI State Management Reference

## @State

Owns a piece of mutable state. The view is the single source of truth. SwiftUI persists the value across re-renders.

```swift
struct CounterView: View {
    @State private var count = 0

    var body: some View {
        Button("Count: \(count)") {
            count += 1
        }
    }
}
```

**Rules:**
- Always declare `private` — `@State` is owned by the view
- Works with value types (Int, String, Bool, structs, enums)
- In iOS 17+, also owns `@Observable` class instances
- Initialized once when the view is first created; subsequent `body` calls do NOT reinitialize it
- If you need to react to external changes, use `.onChange(of:)` or derive state from the source of truth

### @State with @Observable (iOS 17+)

```swift
@Observable
class TimerModel {
    var seconds = 0
    var isRunning = false
}

struct TimerView: View {
    @State private var model = TimerModel()  // view owns the model

    var body: some View {
        Text("\(model.seconds)s")
        Button(model.isRunning ? "Stop" : "Start") {
            model.isRunning.toggle()
        }
    }
}
```

---

## @Binding

A two-way reference to state owned elsewhere. Does NOT own the data.

```swift
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool  // parent owns this value

    var body: some View {
        Toggle(title, isOn: $isOn)
    }
}

// Usage:
struct SettingsView: View {
    @State private var notificationsEnabled = true

    var body: some View {
        ToggleRow(title: "Notifications", isOn: $notificationsEnabled)
    }
}
```

**Creating bindings:**
- From `@State`: `$stateProperty`
- From `@Observable` with `@Bindable`: `$model.property`
- Constant (for previews): `.constant(true)`
- Custom: `Binding(get: { ... }, set: { ... })`

```swift
// Custom binding example — transform values
let uppercasedBinding = Binding(
    get: { text.uppercased() },
    set: { text = $0 }
)
```

---

## @Observable (iOS 17+)

Macro that enables fine-grained observation. SwiftUI tracks which properties each view reads in `body` and only re-renders when those specific properties change.

```swift
@Observable
class UserProfile {
    var name = ""
    var email = ""
    var avatarURL: URL?

    @ObservationIgnored
    var analyticsId = UUID()  // changes won't trigger view updates

    func updateProfile() async throws {
        // network call...
    }
}
```

**How it works internally:**
- The macro adds `@ObservationTracked` to each stored property (synthesized getters/setters that notify the observation system)
- `@ObservationIgnored` opts out a property
- Views that read `model.name` in `body` only re-render when `name` changes, NOT when `email` changes
- This is a massive perf improvement over `ObservableObject` where ANY `@Published` change re-renders ALL observers

### Passing @Observable Objects

```swift
// No wrapper needed when passing as parameter — observation is automatic
struct ProfileView: View {
    var profile: UserProfile  // just a regular property

    var body: some View {
        Text(profile.name)  // tracked automatically
    }
}
```

### @Bindable (iOS 17+)

Creates bindings to properties of an `@Observable` object. Needed when you pass the object as a parameter (not `@State`).

```swift
struct EditProfileView: View {
    @Bindable var profile: UserProfile  // enables $profile.name

    var body: some View {
        Form {
            TextField("Name", text: $profile.name)
            TextField("Email", text: $profile.email)
        }
    }
}
```

**When you need @Bindable:**
- The object is passed in (not `@State`)
- You need `$object.property` bindings (for TextField, Toggle, etc.)

**When you DON'T need it:**
- Reading properties (just use the object directly)
- The object is `@State` (bindings work via `$stateVar.property`)

---

## @Environment

Access system-provided or custom values from the environment.

### System Values

```swift
struct AdaptiveView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @Environment(\.locale) var locale
    @Environment(\.calendar) var calendar
    @Environment(\.isSearching) var isSearching
    @Environment(\.editMode) var editMode
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        if colorScheme == .dark {
            Text("Dark mode")
        }
        Button("Close") { dismiss() }
    }
}
```

### Custom Environment Values (Pre-iOS 18)

```swift
// 1. Define the key
struct AccentThemeKey: EnvironmentKey {
    static let defaultValue: Color = .blue
}

// 2. Extend EnvironmentValues
extension EnvironmentValues {
    var accentTheme: Color {
        get { self[AccentThemeKey.self] }
        set { self[AccentThemeKey.self] = newValue }
    }
}

// 3. Set it
ContentView()
    .environment(\.accentTheme, .purple)

// 4. Read it
@Environment(\.accentTheme) var accentTheme
```

### @Entry Macro (iOS 18+)

Simplifies custom environment values to a single declaration:

```swift
extension EnvironmentValues {
    @Entry var accentTheme: Color = .blue
}

// That's it! Use the same way:
.environment(\.accentTheme, .purple)
@Environment(\.accentTheme) var accentTheme
```

### Environment with @Observable (iOS 17+)

```swift
@Observable
class AppSettings {
    var theme: Theme = .system
    var fontSize: CGFloat = 16
}

// Inject
ContentView()
    .environment(AppSettings())

// Read (note: type-based, not keypath-based)
@Environment(AppSettings.self) var settings
```

---

## Pre-iOS 17 Patterns

### ObservableObject + @Published

```swift
class UserViewModel: ObservableObject {
    @Published var name = ""
    @Published var posts: [Post] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        posts = try await api.fetchPosts()
    }
}
```

### @StateObject

Owns an `ObservableObject`. Creates it once, persists across re-renders.

```swift
struct UserView: View {
    @StateObject private var viewModel = UserViewModel()

    var body: some View {
        List(viewModel.posts) { post in
            Text(post.title)
        }
        .task { await viewModel.load() }
    }
}
```

### @ObservedObject

Observes an `ObservableObject` owned elsewhere (passed in).

```swift
struct PostRow: View {
    @ObservedObject var viewModel: PostRowViewModel

    var body: some View {
        Text(viewModel.title)
    }
}
```

**Danger:** `@ObservedObject` does NOT own the object. If the parent re-creates it, state is lost. Use `@StateObject` for ownership.

### @EnvironmentObject

Shares an `ObservableObject` through the view hierarchy.

```swift
// Inject
ContentView()
    .environmentObject(UserViewModel())

// Read (anywhere in subtree)
@EnvironmentObject var userVM: UserViewModel
```

**Warning:** Crashes at runtime if the object is not in the environment. No compile-time safety.

---

## Decision Matrix: Pre-iOS 17 vs iOS 17+

| Purpose | Pre-iOS 17 | iOS 17+ |
|---|---|---|
| Own a reference-type model | `@StateObject` + `ObservableObject` | `@State` + `@Observable` |
| Observe passed-in model | `@ObservedObject` | just pass it (auto-tracked) |
| Bind to model properties | `$viewModel.property` (via `@Published`) | `@Bindable var model` then `$model.property` |
| Share via environment | `@EnvironmentObject` | `@Environment(ModelType.self)` |
| Granularity | ALL `@Published` changes re-render ALL observers | Only properties read in `body` trigger re-render |

---

## Anti-Patterns

### 1. Using @StateObject with @Observable

```swift
// WRONG
@StateObject private var model = MyObservableModel()  // compiler error or unexpected behavior

// CORRECT (iOS 17+)
@State private var model = MyObservableModel()
```

### 2. Using @ObservedObject with @Observable

```swift
// WRONG — unnecessary, and may cause issues
@ObservedObject var model: MyObservableModel

// CORRECT (iOS 17+) — just pass it
var model: MyObservableModel
// Add @Bindable only if you need $model.property bindings
```

### 3. Initializing @State from a parameter

```swift
// DANGEROUS — @State only initializes once
struct DetailView: View {
    @State private var text: String  // won't update when parent passes new value

    init(initialText: String) {
        _text = State(initialValue: initialText)
    }
}

// BETTER — use @Binding if parent should control it
// or use .onChange(of:) if you need to sync
```

### 4. Mutating @State outside the view

```swift
// WRONG — @State is private to the view
func updateFromOutside(view: MyView) {
    view.someState = newValue  // won't work correctly
}

// CORRECT — use @Binding, @Observable, or callbacks
```

### 5. Storing derived data in @State

```swift
// WRONG — duplicate source of truth
@State private var items: [Item] = []
@State private var filteredItems: [Item] = []  // derived from items!

// CORRECT — compute derived data
var filteredItems: [Item] {
    items.filter { $0.isActive }
}
```
