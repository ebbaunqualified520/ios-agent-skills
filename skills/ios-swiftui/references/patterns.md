# SwiftUI Patterns Reference

## ViewModifier Protocol

Create reusable view modifications. Always pair with a View extension for ergonomic API.

```swift
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .blendMode(.softLight)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// Usage
Text("Loading...")
    .shimmer()
```

### Conditional Modifier Pattern

```swift
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// Usage
Text("Hello")
    .if(isHighlighted) { $0.foregroundStyle(.red).bold() }
```

**Warning:** This changes the view identity when the condition toggles, which can break animations. For simple cases, prefer ternary operators directly:

```swift
Text("Hello")
    .foregroundStyle(isHighlighted ? .red : .primary)
    .fontWeight(isHighlighted ? .bold : .regular)
```

### ButtonStyle

```swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.blue, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

// Usage
Button("Continue") { next() }
    .buttonStyle(.primary)
```

---

## @ViewBuilder

Build conditional and composed view content. Used in custom containers, functions, and computed properties.

### In Custom Views

```swift
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 12))
        .shadow(radius: 2)
    }
}

// Usage
Card(title: "Stats") {
    Text("Users: 1,234")
    Text("Revenue: $5,678")
    if showDetails {
        DetailChart()
    }
}
```

### In Functions

```swift
@ViewBuilder
func statusBadge(for status: Status) -> some View {
    switch status {
    case .active:
        Label("Active", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    case .pending:
        Label("Pending", systemImage: "clock.fill")
            .foregroundStyle(.orange)
    case .inactive:
        Label("Inactive", systemImage: "xmark.circle.fill")
            .foregroundStyle(.red)
    }
}
```

### In Computed Properties

```swift
@ViewBuilder
var emptyState: some View {
    if items.isEmpty {
        ContentUnavailableView("No Items",
            systemImage: "tray",
            description: Text("Add items to get started."))
    }
}
```

---

## Preferences and PreferenceKey

Pass data UP the view hierarchy (child to parent). Opposite of environment (top-down).

```swift
// 1. Define the key
struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())  // keep the largest
    }
}

// 2. Set preference in child
struct ChildView: View {
    var body: some View {
        Text("Hello")
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ViewHeightKey.self, value: proxy.size.height)
                }
            }
    }
}

// 3. Read preference in parent
struct ParentView: View {
    @State private var childHeight: CGFloat = 0

    var body: some View {
        VStack {
            ChildView()
            Text("Child height: \(childHeight)")
        }
        .onPreferenceChange(ViewHeightKey.self) { height in
            childHeight = height
        }
    }
}
```

### Practical Use: Equal-Width Buttons

```swift
struct MaxWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct EqualWidthButtonRow: View {
    @State private var maxWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 16) {
            Button("OK") { }
                .frame(minWidth: maxWidth)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MaxWidthKey.self, value: proxy.size.width)
                    }
                }

            Button("Cancel") { }
                .frame(minWidth: maxWidth)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MaxWidthKey.self, value: proxy.size.width)
                    }
                }
        }
        .onPreferenceChange(MaxWidthKey.self) { maxWidth = $0 }
    }
}
```

---

## GeometryReader

Reads the size and position of its container. **Use sparingly** — it proposes all available space to children and can cause layout issues.

```swift
struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.gray.opacity(0.2))

                Capsule()
                    .fill(.blue)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 8)  // constrain height since GeometryReader is greedy
    }
}
```

### Coordinate Spaces

```swift
struct ScrollOffsetReader: View {
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(items) { item in
                    ItemView(item: item)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("scroll")).minY)
                }
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            // react to scroll offset
        }
    }
}
```

**Prefer alternatives when possible:**
- `containerRelativeFrame` (iOS 17+) for sizing relative to container
- `.frame()` modifiers for fixed/flexible sizing
- `ViewThatFits` for responsive layouts
- `overlay` / `background` with `GeometryReader` to measure without affecting layout

---

## SwiftUI Lifecycle

### App Protocol

```swift
@main
struct MyApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
    }
}
```

### Scene Phase

```swift
struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        MainContent()
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    // app is in foreground and interactive
                    refreshData()
                case .inactive:
                    // app is visible but not interactive (e.g., multitasking switcher)
                    break
                case .background:
                    // app is in background — save state
                    saveState()
                @unknown default:
                    break
                }
            }
    }
}
```

---

## View Lifecycle Modifiers

### .onAppear / .onDisappear

```swift
.onAppear {
    analytics.trackScreenView("Home")
}
.onDisappear {
    timer.invalidate()
}
```

### .task (Preferred for Async)

Auto-cancels when view disappears. Restarts when `id` changes.

```swift
// Load once
.task {
    await viewModel.loadData()
}

// Reload when ID changes
.task(id: selectedCategory) {
    await viewModel.loadItems(for: selectedCategory)
}

// Long-running task (e.g., WebSocket listener)
.task {
    for await message in chatService.messages {
        messages.append(message)
    }
}
```

### .onChange

```swift
// iOS 17+ (two-parameter closure)
.onChange(of: searchText) { oldValue, newValue in
    performSearch(newValue)
}

// Immediate trigger variant
.onChange(of: searchText, initial: true) { oldValue, newValue in
    performSearch(newValue)  // also runs on first appearance
}
```

---

## UIKit Interop

### UIViewRepresentable — Hosting UIKit View in SwiftUI

```swift
struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var annotations: [MKAnnotation]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
    }
}
```

### UIViewControllerRepresentable

```swift
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}
```

### UIHostingController — Hosting SwiftUI in UIKit

```swift
// In a UIKit view controller
let swiftUIView = ProfileView(user: user)
let hostingController = UIHostingController(rootView: swiftUIView)

addChild(hostingController)
view.addSubview(hostingController.view)
hostingController.view.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
    hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
])
hostingController.didMove(toParent: self)

// Update the SwiftUI view
hostingController.rootView = ProfileView(user: updatedUser)
```

---

## Performance Tips

### 1. Use Lazy Containers for Large Data

```swift
// BAD — creates ALL views upfront
ScrollView {
    VStack {
        ForEach(thousandsOfItems) { item in
            ExpensiveView(item: item)
        }
    }
}

// GOOD — creates views on demand
ScrollView {
    LazyVStack {
        ForEach(thousandsOfItems) { item in
            ExpensiveView(item: item)
        }
    }
}
```

### 2. Stable Identifiers in ForEach

```swift
// BAD — array index changes on insert/delete, breaks animations and state
ForEach(Array(items.enumerated()), id: \.offset) { ... }

// GOOD — stable, unique identifier
ForEach(items) { item in ... }  // requires Identifiable
ForEach(items, id: \.stableID) { item in ... }
```

### 3. Break Down Large Views

```swift
// BAD — entire body re-evaluates when ANY state changes
struct BigView: View {
    @State private var name = ""
    @State private var items: [Item] = []
    @State private var isEditing = false

    var body: some View {
        VStack {
            TextField("Name", text: $name)  // typing here re-evaluates ALL below
            ForEach(items) { item in
                // 100 lines of complex view code...
            }
        }
    }
}

// GOOD — each subview only re-evaluates when its inputs change
struct BigView: View {
    @State private var name = ""
    @State private var items: [Item] = []

    var body: some View {
        VStack {
            NameField(name: $name)
            ItemList(items: items)
        }
    }
}
```

### 4. Equatable Views

```swift
struct ExpensiveChart: View, Equatable {
    let data: [DataPoint]

    static func == (lhs: ExpensiveChart, rhs: ExpensiveChart) -> Bool {
        lhs.data == rhs.data
    }

    var body: some View {
        // complex rendering...
    }
}

// Usage
ExpensiveChart(data: chartData)
    .equatable()  // skip body if data hasn't changed
```

### 5. Avoid AnyView

```swift
// BAD — destroys type information, prevents efficient diffing
func makeView(for type: ItemType) -> AnyView {
    switch type {
    case .text: return AnyView(TextView())
    case .image: return AnyView(ImageView())
    }
}

// GOOD — preserves type information
@ViewBuilder
func makeView(for type: ItemType) -> some View {
    switch type {
    case .text: TextView()
    case .image: ImageView()
    }
}
```

---

## AsyncImage

Load remote images with built-in loading states.

```swift
AsyncImage(url: URL(string: imageURL)) { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let image):
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    case .failure:
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
    @unknown default:
        EmptyView()
    }
}
.frame(width: 200, height: 200)
.clipShape(.rect(cornerRadius: 12))
```

Short form for simple cases:

```swift
AsyncImage(url: url) { image in
    image.resizable().aspectRatio(contentMode: .fit)
} placeholder: {
    ProgressView()
}
```

**Note:** AsyncImage has no built-in caching beyond URLSession's default cache. For production apps with many images, consider a library like Kingfisher or Nuke.

---

## #Preview Macro (iOS 17+)

Replaces `PreviewProvider` with a simpler syntax.

```swift
#Preview {
    ContentView()
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    ContentView()
        .dynamicTypeSize(.xxxLarge)
}

// Preview with traits
#Preview(traits: .landscapeLeft) {
    ContentView()
}

// Preview in NavigationStack
#Preview {
    NavigationStack {
        DetailView(item: .sample)
    }
}
```

---

## ContentUnavailableView (iOS 17+)

Standard empty/error states.

```swift
// Search results empty
ContentUnavailableView.search(text: searchText)

// Custom empty state
ContentUnavailableView("No Recipes",
    systemImage: "fork.knife",
    description: Text("Add your first recipe to get started."))

// With action
ContentUnavailableView {
    Label("No Connection", systemImage: "wifi.slash")
} description: {
    Text("Check your internet connection and try again.")
} actions: {
    Button("Retry") { retry() }
        .buttonStyle(.borderedProminent)
}
```
