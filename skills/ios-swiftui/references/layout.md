# SwiftUI Layout Reference

## Stacks

### VStack / HStack / ZStack

```swift
// VStack — vertical, top-to-bottom
VStack(alignment: .leading, spacing: 12) {
    Text("Title").font(.headline)
    Text("Subtitle").font(.subheadline)
}

// HStack — horizontal, leading-to-trailing
HStack(alignment: .firstTextBaseline, spacing: 8) {
    Image(systemName: "star.fill")
    Text("Favorite")
}

// ZStack — overlapping, back-to-front
ZStack(alignment: .bottomTrailing) {
    Image("photo")
    Text("Badge").padding(4).background(.red).clipShape(.capsule)
}
```

**Alignment options:**
- VStack: `.leading`, `.center` (default), `.trailing`
- HStack: `.top`, `.center` (default), `.bottom`, `.firstTextBaseline`, `.lastTextBaseline`
- ZStack: `.center` (default), `.topLeading`, `.top`, `.topTrailing`, `.leading`, `.trailing`, `.bottomLeading`, `.bottom`, `.bottomTrailing`

**Key behavior:** Stacks measure ALL children upfront, then distribute space. For large collections, use Lazy variants.

### Spacer and Divider

```swift
HStack {
    Text("Left")
    Spacer()           // expands to fill available space
    Text("Right")
}

HStack {
    Text("A")
    Spacer(minLength: 20)  // at least 20pt gap
    Text("B")
}

VStack {
    Text("Above")
    Divider()          // thin horizontal line (vertical in HStack)
    Text("Below")
}
```

---

## Lazy Containers

### LazyVStack / LazyHStack

Create views only when they scroll into the visible area. MUST be inside a ScrollView.

```swift
ScrollView {
    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
        Section {
            ForEach(items) { item in
                ItemRow(item: item)
            }
        } header: {
            Text("Section Header")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
        }
    }
}
```

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 12) {
        ForEach(photos) { photo in
            PhotoCard(photo: photo)
                .frame(width: 200, height: 300)
        }
    }
    .padding(.horizontal)
}
```

**pinnedViews options:** `.sectionHeaders`, `.sectionFooters` — stick to the edge during scroll.

**When to use:**
- `VStack` / `HStack`: < 50 items, need all measured at once
- `LazyVStack` / `LazyHStack`: 50+ items in ScrollView
- `List`: 1000+ items, need cell reuse, swipe actions, edit mode

---

## Grid (iOS 16+)

Aligned rows and columns with automatic sizing. Good for small, structured data.

```swift
Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
    GridRow {
        Text("Name")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Status")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Divider()
        .gridCellColumns(2)  // span both columns

    GridRow {
        Text("Alice")
        Text("Active").foregroundStyle(.green)
    }

    GridRow {
        Text("Bob")
        Text("Inactive").foregroundStyle(.red)
    }

    GridRow {
        Color.clear.gridCellUnsizedAxes(.horizontal)  // empty cell
        Text("Unknown")
    }
}
```

**Key APIs:**
- `gridCellColumns(_:)` — span multiple columns
- `gridCellAnchor(_:)` — alignment within cell
- `gridColumnAlignment(_:)` — override column alignment
- `gridCellUnsizedAxes(_:)` — don't contribute to sizing

---

## LazyVGrid / LazyHGrid

Grid layout for scrollable collections. Define columns/rows with `GridItem`.

```swift
// Three equal flexible columns
let columns = [
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible())
]

ScrollView {
    LazyVGrid(columns: columns, spacing: 16) {
        ForEach(photos) { photo in
            PhotoThumbnail(photo: photo)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(.rect(cornerRadius: 8))
        }
    }
    .padding()
}
```

### GridItem Types

```swift
// Fixed width columns
GridItem(.fixed(100))

// Flexible: fills available space, respects min/max
GridItem(.flexible(minimum: 80, maximum: 200))

// Adaptive: fits as many as possible in available space
// Single adaptive item = "responsive grid"
let columns = [GridItem(.adaptive(minimum: 100, maximum: 150))]
// This creates as many 100-150pt columns as fit

// Mixed
let columns = [
    GridItem(.fixed(60)),       // avatar column
    GridItem(.flexible()),      // content fills rest
]
```

### Horizontal Grid

```swift
let rows = [
    GridItem(.fixed(100)),
    GridItem(.fixed(100))
]

ScrollView(.horizontal) {
    LazyHGrid(rows: rows, spacing: 12) {
        ForEach(items) { item in
            ItemCard(item: item)
        }
    }
    .padding()
}
```

---

## ViewThatFits (iOS 16+)

Picks the FIRST child that fits in the available space. No scrolling — purely for layout adaptation.

```swift
ViewThatFits {
    // Try horizontal first
    HStack {
        Image(systemName: "star")
        Text("Mark as Favorite")
    }
    // Fall back to vertical if HStack doesn't fit
    VStack {
        Image(systemName: "star")
        Text("Favorite")
    }
    // Last resort: just icon
    Image(systemName: "star")
}
```

```swift
// Responsive layout: horizontal on wide, vertical on narrow
ViewThatFits(in: .horizontal) {  // only check horizontal axis
    HStack(spacing: 20) {
        InfoCard(); StatsCard(); ActionsCard()
    }
    VStack(spacing: 12) {
        InfoCard(); StatsCard(); ActionsCard()
    }
}
```

---

## List

Full-featured scrollable container with cell reuse, platform styling, and built-in interactions.

```swift
List {
    Section("Favorites") {
        ForEach(favorites) { item in
            NavigationLink(value: item) {
                Label(item.name, systemImage: item.icon)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(item) } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { toggleFavorite(item) } label: {
                    Label("Unfavorite", systemImage: "star.slash")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .leading) {
                Button { pin(item) } label: {
                    Label("Pin", systemImage: "pin")
                }
                .tint(.yellow)
            }
        }
        .onDelete { indexSet in
            favorites.remove(atOffsets: indexSet)
        }
        .onMove { from, to in
            favorites.move(fromOffsets: from, toOffset: to)
        }
    }
}
.listStyle(.insetGrouped)
.searchable(text: $searchText, prompt: "Search items")
.refreshable {
    await loadData()
}
```

### List Styles

```swift
.listStyle(.automatic)       // platform default
.listStyle(.plain)           // no section styling
.listStyle(.grouped)         // iOS grouped sections
.listStyle(.insetGrouped)    // rounded section cards (most common iOS)
.listStyle(.sidebar)         // macOS/iPadOS sidebar style
```

### List Row Customization

```swift
.listRowBackground(Color.blue.opacity(0.1))
.listRowSeparator(.hidden)
.listRowSeparatorTint(.blue)
.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
```

---

## ScrollView

```swift
// Vertical (default)
ScrollView {
    LazyVStack { ... }
}

// Horizontal
ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack { ... }
}

// Both axes
ScrollView([.horizontal, .vertical]) { ... }
```

### Scroll Position (iOS 17+)

```swift
struct ContentView: View {
    @State private var scrollPosition: Int?

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(0..<100) { index in
                    Text("Row \(index)")
                        .id(index)
                }
            }
        }
        .scrollPosition(id: $scrollPosition)
        .onChange(of: scrollPosition) { _, newValue in
            print("Scrolled to: \(newValue ?? -1)")
        }

        Button("Jump to 50") { scrollPosition = 50 }
    }
}
```

### Scroll Target Behavior (iOS 17+)

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 16) {
        ForEach(cards) { card in
            CardView(card: card)
                .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)  // snaps to each card
// .scrollTargetBehavior(.paging)    // page-by-page snapping
```

### containerRelativeFrame (iOS 17+)

Size views relative to the scroll view's visible area.

```swift
ScrollView(.horizontal) {
    LazyHStack {
        ForEach(items) { item in
            ItemView(item: item)
                .containerRelativeFrame(.horizontal, count: 3, spacing: 8)
                // Each item takes 1/3 of visible width
        }
    }
}
```

```swift
// More control: alignment and custom sizing
Text("Centered")
    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
        length * 0.8  // 80% of container on both axes
    }
```

### Scroll Transitions (iOS 17+)

Apply effects as views enter/leave the visible scroll area.

```swift
ScrollView(.horizontal) {
    LazyHStack {
        ForEach(items) { item in
            CardView(item: item)
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.5)
                        .scaleEffect(phase.isIdentity ? 1 : 0.85)
                        .rotationEffect(.degrees(phase.isIdentity ? 0 : phase.value * 5))
                }
        }
    }
}
```

`phase` is `.topLeading`, `.identity`, or `.bottomTrailing`. Use `phase.isIdentity` for the visible state.

---

## ForEach

```swift
// With Identifiable items
ForEach(items) { item in
    Text(item.name)
}

// With explicit id keypath
ForEach(items, id: \.name) { item in
    Text(item.name)
}

// Range-based (constant range only)
ForEach(0..<5) { index in
    Text("Row \(index)")
}

// With index and element using enumerated
ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
    Text("\(index): \(item.name)")
}
```

**Important:** ForEach requires stable, unique IDs. Using array indices as IDs causes bugs when items are reordered or deleted. Always prefer `Identifiable` conformance or a stable `\.id` keypath.
