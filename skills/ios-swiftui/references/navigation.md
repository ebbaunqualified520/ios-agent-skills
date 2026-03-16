# SwiftUI Navigation Reference

## NavigationStack (iOS 16+)

Replaces `NavigationView`. Manages a push/pop stack of views.

### Basic Usage

```swift
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe)
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }
}
```

### Programmatic Navigation with NavigationPath

```swift
struct AppView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe, path: $path)
                }
                .navigationDestination(for: Category.self) { category in
                    CategoryView(category: category)
                }
        }
    }

    // Push programmatically
    func showRecipe(_ recipe: Recipe) {
        path.append(recipe)
    }

    // Pop to root
    func popToRoot() {
        path = NavigationPath()
    }

    // Pop one level
    func goBack() {
        path.removeLast()
    }
}
```

`NavigationPath` is a type-erased collection — it can hold any `Hashable` value. For type-safe paths, use a concrete array:

```swift
@State private var path: [Recipe] = []  // only Recipe values

NavigationStack(path: $path) { ... }
```

### navigationDestination(item:) (iOS 17+)

Navigate based on an optional binding — useful for item-triggered navigation:

```swift
@State private var selectedRecipe: Recipe?

NavigationStack {
    RecipeList(selection: $selectedRecipe)
        .navigationDestination(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
}
```

---

## NavigationLink

### Value-Based (Preferred)

```swift
// Push destination is resolved by .navigationDestination(for:)
NavigationLink(value: item) {
    Label(item.name, systemImage: "doc")
}
```

### View-Based (Legacy but still useful for simple cases)

```swift
NavigationLink {
    DetailView(item: item)
} label: {
    Text(item.name)
}
```

**Rule:** Prefer value-based links for programmatic navigation and deep linking. View-based links are fine for simple, static navigation.

---

## NavigationSplitView (iOS 16+)

Multi-column navigation for iPad and Mac. Falls back to stack on iPhone.

### Two-Column

```swift
struct MailView: View {
    @State private var selectedFolder: Folder?
    @State private var selectedMessage: Message?

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(folders, selection: $selectedFolder) { folder in
                Label(folder.name, systemImage: folder.icon)
            }
            .navigationTitle("Mail")
        } detail: {
            // Detail
            if let selectedFolder {
                MessageList(folder: selectedFolder, selection: $selectedMessage)
            } else {
                ContentUnavailableView("Select a Folder",
                    systemImage: "folder",
                    description: Text("Pick a folder from the sidebar."))
            }
        }
    }
}
```

### Three-Column

```swift
NavigationSplitView {
    // Sidebar (column 1)
    List(categories, selection: $selectedCategory) { category in
        Text(category.name)
    }
} content: {
    // Content (column 2)
    if let category = selectedCategory {
        List(category.items, selection: $selectedItem) { item in
            Text(item.name)
        }
    }
} detail: {
    // Detail (column 3)
    if let item = selectedItem {
        ItemDetailView(item: item)
    }
}
```

### Column Visibility and Style

```swift
@State private var columnVisibility: NavigationSplitViewVisibility = .all

NavigationSplitView(columnVisibility: $columnVisibility) {
    Sidebar()
} detail: {
    Detail()
}
.navigationSplitViewStyle(.balanced)       // equal widths
// .navigationSplitViewStyle(.prominentDetail)  // detail gets more space (default)
```

Visibility options: `.all`, `.doubleColumn`, `.detailOnly`, `.automatic`

---

## TabView

### Basic Tabs

```swift
struct MainView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(2)
                .badge(3)  // notification badge
        }
    }
}
```

### Tab Type (iOS 18+)

```swift
TabView {
    Tab("Home", systemImage: "house") {
        HomeView()
    }

    Tab("Search", systemImage: "magnifyingglass") {
        SearchView()
    }

    TabSection("Settings") {
        Tab("General", systemImage: "gear") {
            GeneralSettingsView()
        }
        Tab("Privacy", systemImage: "lock") {
            PrivacySettingsView()
        }
    }
}
.tabViewStyle(.sidebarAdaptable)  // sidebar on iPad, tab bar on iPhone
```

---

## Navigation Modifiers

### Navigation Title and Toolbar

```swift
.navigationTitle("Recipes")
.navigationBarTitleDisplayMode(.large)    // .large, .inline, .automatic
.toolbarTitleDisplayMode(.inline)         // iOS 17+ alternative

.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button("Add", systemImage: "plus") { addItem() }
    }

    ToolbarItem(placement: .topBarLeading) {
        EditButton()
    }

    ToolbarItem(placement: .bottomBar) {
        Text("\(items.count) items")
    }

    ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focusedField = nil }
    }
}

.toolbarBackground(.visible, for: .navigationBar)
.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
.toolbarColorScheme(.dark, for: .navigationBar)
```

### Searchable

```swift
struct SearchableList: View {
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                Text(item.name)
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                         prompt: "Search recipes")
            .searchScopes($searchScope) {
                Text("All").tag(SearchScope.all)
                Text("Favorites").tag(SearchScope.favorites)
                Text("Recent").tag(SearchScope.recent)
            }
            .searchSuggestions {
                ForEach(suggestions) { suggestion in
                    Text(suggestion.name)
                        .searchCompletion(suggestion.name)
                }
            }
        }
    }
}
```

---

## Sheets and Presentations

### Sheet

```swift
struct ParentView: View {
    @State private var showSheet = false
    @State private var selectedItem: Item?

    var body: some View {
        Button("Show Sheet") { showSheet = true }

        // Boolean-based
        .sheet(isPresented: $showSheet) {
            SheetContent()
        }

        // Item-based (auto-presents when non-nil)
        .sheet(item: $selectedItem) { item in
            ItemDetail(item: item)
        }
    }
}
```

### Presentation Detents (Half-sheets, iOS 16+)

```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.medium, .large])              // snap to half or full
        .presentationDetents([.height(200), .fraction(0.7)])  // custom sizes
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(20)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))  // interact with content behind
        .interactiveDismissDisabled()  // prevent swipe dismiss
}
```

### fullScreenCover

```swift
.fullScreenCover(isPresented: $showFullScreen) {
    FullScreenView()
}
```

No swipe-to-dismiss by default. Must provide explicit dismiss mechanism.

### Popover

```swift
.popover(isPresented: $showPopover, arrowEdge: .top) {
    PopoverContent()
        .frame(width: 300, height: 200)
}
```

On iPhone, popovers automatically become sheets.

### Alert

```swift
.alert("Delete Item?", isPresented: $showDeleteAlert) {
    Button("Delete", role: .destructive) { deleteItem() }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This action cannot be undone.")
}

// With associated data
.alert("Error", isPresented: $showError, presenting: errorDetails) { details in
    Button("Retry") { retry(details) }
    Button("Cancel", role: .cancel) { }
} message: { details in
    Text(details.message)
}
```

### Confirmation Dialog

```swift
.confirmationDialog("Share Photo", isPresented: $showShareOptions, titleVisibility: .visible) {
    Button("Copy Link") { copyLink() }
    Button("Save to Photos") { savePhoto() }
    Button("Share via Messages") { shareMessages() }
    Button("Delete", role: .destructive) { deletePhoto() }
}
```

---

## Dismissal

```swift
struct SheetContent: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form { ... }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save()
                            dismiss()
                        }
                    }
                }
        }
    }
}
```

---

## Deep Linking

```swift
@main
struct MyApp: App {
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView()
                    .navigationDestination(for: DeepLink.self) { link in
                        link.destination
                    }
            }
            .onOpenURL { url in
                if let link = DeepLink(url: url) {
                    path.append(link)
                }
            }
        }
    }
}

enum DeepLink: Hashable {
    case recipe(id: String)
    case profile(username: String)

    init?(url: URL) {
        guard url.scheme == "myapp" else { return nil }
        switch url.host {
        case "recipe":
            self = .recipe(id: url.lastPathComponent)
        case "profile":
            self = .profile(username: url.lastPathComponent)
        default:
            return nil
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .recipe(let id): RecipeDetailView(id: id)
        case .profile(let username): ProfileView(username: username)
        }
    }
}
```

---

## Anti-Patterns

1. **Nesting NavigationStack inside NavigationStack** — produces double navigation bars, broken back buttons, and unpredictable behavior. Only ONE NavigationStack at the root.

2. **Mixing value-based and view-based NavigationLinks** — pick one style per navigation context for consistency.

3. **Using NavigationView** — deprecated. Use NavigationStack (push/pop) or NavigationSplitView (multi-column).

4. **Putting NavigationStack inside a sheet** — this is actually CORRECT for modal flows that need their own navigation. Just don't nest stacks in the main hierarchy.

5. **Forgetting `.navigationDestination`** — value-based NavigationLinks silently do nothing without a matching destination.
