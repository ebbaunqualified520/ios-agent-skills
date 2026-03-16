# MVVM with @Observable -- iOS Architecture Reference

## Overview

MVVM (Model-View-ViewModel) is Apple's recommended pattern for SwiftUI apps. The ViewModel holds UI state and business logic; the View observes and renders it. Since iOS 17, `@Observable` replaces `ObservableObject` with simpler, more performant observation.

---

## @Observable ViewModel Pattern (iOS 17+)

```swift
// MARK: - ViewModel (import Foundation, NEVER SwiftUI)

import Foundation

@Observable
final class HomeViewModel {
    // MARK: - State
    private(set) var users: [User] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Dependencies
    private let userRepository: UserRepositoryProtocol

    // MARK: - Init
    init(userRepository: UserRepositoryProtocol) {
        self.userRepository = userRepository
    }

    // MARK: - Actions
    func loadUsers() async {
        isLoading = true
        errorMessage = nil

        do {
            users = try await userRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteUser(_ user: User) async {
        do {
            try await userRepository.delete(user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = "Failed to delete user."
        }
    }
}
```

```swift
// MARK: - View

import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel

    init(userRepository: UserRepositoryProtocol) {
        _viewModel = State(initialValue: HomeViewModel(userRepository: userRepository))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    userList
                }
            }
            .navigationTitle("Users")
            .task {
                await viewModel.loadUsers()
            }
        }
    }

    private var userList: some View {
        List(viewModel.users) { user in
            UserRow(user: user)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteUser(user) }
                    }
                }
        }
    }
}
```

---

## ObservableObject Pattern (Pre-iOS 17 / iOS 15-16 Support)

```swift
import Foundation
import Combine

final class HomeViewModel: ObservableObject {
    @Published private(set) var users: [User] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let userRepository: UserRepositoryProtocol

    init(userRepository: UserRepositoryProtocol) {
        self.userRepository = userRepository
    }

    @MainActor
    func loadUsers() async {
        isLoading = true
        errorMessage = nil

        do {
            users = try await userRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// View uses @StateObject instead of @State
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    init(userRepository: UserRepositoryProtocol) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(userRepository: userRepository))
    }

    var body: some View { /* same as above */ }
}
```

---

## @Observable vs ObservableObject Comparison

| Aspect | @Observable (iOS 17+) | ObservableObject (iOS 15+) |
|---|---|---|
| Import | `import Observation` (auto) | `import Combine` |
| Declaration | `@Observable class` | `class: ObservableObject` |
| Properties | Automatic tracking | Must mark `@Published` |
| View storage | `@State` | `@StateObject` / `@ObservedObject` |
| Observation | Per-property (granular) | Whole-object (any @Published change triggers view update) |
| Performance | Better (only re-renders affected views) | Worse (entire view body re-evaluated) |
| Child view injection | Pass directly or `@Environment` | `@ObservedObject` or `@EnvironmentObject` |

**Rule: Use @Observable for iOS 17+. Use ObservableObject only if supporting iOS 15/16.**

---

## ViewModel Responsibilities

A ViewModel MUST:
- Hold all UI state (loading, error, data, form fields)
- Call services/repositories (never raw URLSession)
- Transform domain models into view-friendly formats
- Handle user actions (tap, submit, delete)

A ViewModel must NEVER:
- Import SwiftUI
- Create views or manage navigation directly
- Access UIKit components
- Hold references to views
- Perform raw networking (delegate to a service)

---

## Async/Await Patterns in ViewModels

### Loading + Error State Pattern

```swift
@Observable
final class ProductListViewModel {
    enum ViewState {
        case idle
        case loading
        case loaded([Product])
        case error(String)
    }

    private(set) var state: ViewState = .idle
    var searchQuery = ""

    private let productRepository: ProductRepositoryProtocol

    init(productRepository: ProductRepositoryProtocol) {
        self.productRepository = productRepository
    }

    func loadProducts() async {
        state = .loading
        do {
            let products = try await productRepository.fetchAll()
            state = .loaded(products)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    var filteredProducts: [Product] {
        guard case .loaded(let products) = state else { return [] }
        if searchQuery.isEmpty { return products }
        return products.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
}
```

### Task Cancellation

```swift
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: [SearchResult] = []

    private let searchService: SearchServiceProtocol
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchServiceProtocol) {
        self.searchService = searchService
    }

    func search() {
        searchTask?.cancel()
        searchTask = Task {
            // Debounce
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                results = try await searchService.search(query: query)
            } catch is CancellationError {
                // Expected, ignore
            } catch {
                results = []
            }
        }
    }
}
```

### Multiple Concurrent Loads

```swift
@Observable
final class DashboardViewModel {
    private(set) var stats: DashboardStats?
    private(set) var recentOrders: [Order] = []
    private(set) var isLoading = false

    private let statsService: StatsServiceProtocol
    private let orderRepository: OrderRepositoryProtocol

    init(statsService: StatsServiceProtocol, orderRepository: OrderRepositoryProtocol) {
        self.statsService = statsService
        self.orderRepository = orderRepository
    }

    func loadDashboard() async {
        isLoading = true

        async let statsResult = statsService.fetchStats()
        async let ordersResult = orderRepository.fetchRecent(limit: 10)

        do {
            let (stats, orders) = try await (statsResult, ordersResult)
            self.stats = stats
            self.recentOrders = orders
        } catch {
            // Handle partial failure if needed
        }

        isLoading = false
    }
}
```

---

## File Structure Convention

```
Features/
└── Home/
    ├── HomeView.swift              (SwiftUI view)
    ├── HomeViewModel.swift         (state + logic)
    └── Components/                 (subviews used only by HomeView)
        ├── UserRow.swift
        └── StatsCard.swift
```

Rules:
- One ViewModel per screen (not per view)
- Subviews in `Components/` receive plain data, not the whole ViewModel
- Keep feature folders flat -- avoid deep nesting

---

## Passing Data to Subviews

```swift
// GOOD: Subview takes plain values
struct UserRow: View {
    let name: String
    let email: String
    let avatarURL: URL?

    var body: some View {
        HStack {
            AsyncImage(url: avatarURL) { image in
                image.resizable().frame(width: 40, height: 40)
            } placeholder: {
                Image(systemName: "person.circle")
            }
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(email).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// BAD: Subview takes entire ViewModel
struct UserRow: View {
    @Bindable var viewModel: HomeViewModel  // Do NOT do this
    let index: Int
    // ...
}
```

---

## Testing ViewModels

```swift
// MARK: - Mock

final class MockUserRepository: UserRepositoryProtocol {
    var fetchAllResult: Result<[User], Error> = .success([])
    var deleteCalledWith: UUID?

    func fetchAll() async throws -> [User] {
        try fetchAllResult.get()
    }

    func delete(_ id: UUID) async throws {
        deleteCalledWith = id
    }
}

// MARK: - Tests

import Testing
@testable import MyApp

struct HomeViewModelTests {
    let mockRepository = MockUserRepository()

    @Test
    func loadUsers_success() async {
        let users = [User(id: UUID(), name: "Alice", email: "a@b.com")]
        mockRepository.fetchAllResult = .success(users)
        let vm = HomeViewModel(userRepository: mockRepository)

        await vm.loadUsers()

        #expect(vm.users == users)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test
    func loadUsers_failure_setsError() async {
        mockRepository.fetchAllResult = .failure(URLError(.notConnectedToInternet))
        let vm = HomeViewModel(userRepository: mockRepository)

        await vm.loadUsers()

        #expect(vm.users.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test
    func deleteUser_removesFromList() async {
        let user = User(id: UUID(), name: "Bob", email: "b@b.com")
        mockRepository.fetchAllResult = .success([user])
        let vm = HomeViewModel(userRepository: mockRepository)
        await vm.loadUsers()

        await vm.deleteUser(user)

        #expect(vm.users.isEmpty)
        #expect(mockRepository.deleteCalledWith == user.id)
    }
}
```

---

## Common Pitfalls

### 1. ViewModel imports SwiftUI
**Problem:** Couples business logic to UI framework, prevents unit testing without UI host.
**Fix:** Import Foundation only. Use `@Observable` from the Observation framework (auto-imported).

### 2. Creating ViewModel inside `var body`
**Problem:** ViewModel gets recreated on every view update, losing state.
**Fix:** Use `@State` (for @Observable) or `@StateObject` (for ObservableObject) -- both survive view re-creation.

### 3. Not using `private(set)` on state properties
**Problem:** Views can mutate ViewModel state directly, bypassing logic.
**Fix:** Mark all state properties `private(set)`. Expose mutation through methods.

### 4. Blocking the main thread
**Problem:** Synchronous work in ViewModel freezes UI.
**Fix:** All service calls must be `async`. Use `.task { }` in views to launch.

### 5. Not handling task cancellation
**Problem:** View disappears but async work continues, updating a deallocated ViewModel.
**Fix:** `.task { }` automatically cancels when the view disappears. For manual tasks, check `Task.isCancelled`.

### 6. Sharing ViewModel across unrelated views
**Problem:** Tight coupling, unclear ownership, lifecycle bugs.
**Fix:** One ViewModel per screen. Pass data down as plain values, not the ViewModel itself.

### 7. Using singletons for services
**Problem:** Cannot replace with mocks in tests. Hidden dependencies.
**Fix:** Inject protocols through the initializer. Use a DI container at the app root.

### 8. Putting navigation logic in ViewModel
**Problem:** ViewModel should not know about view hierarchy.
**Fix:** ViewModel exposes state (e.g., `shouldShowDetail: Bool`). The View reacts with `.navigationDestination` or `.sheet`.
