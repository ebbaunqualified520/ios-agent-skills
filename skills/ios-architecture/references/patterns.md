# Design Patterns -- iOS Architecture Reference

## Repository Pattern

### Concept

Repository abstracts data access behind a protocol. The rest of the app calls the repository; it does not know whether data comes from a network API, local database, or cache.

```
ViewModel -> Repository (protocol) -> { APIClient, CoreData, UserDefaults, Cache }
```

### Protocol (defined in Domain)

```swift
// Domain/Repositories/ProductRepositoryProtocol.swift

protocol ProductRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [Product]
    func fetchById(_ id: UUID) async throws -> Product
    func search(query: String) async throws -> [Product]
    func save(_ product: Product) async throws
    func delete(_ id: UUID) async throws
}
```

### Implementation with Caching

```swift
// Data/Repositories/ProductRepository.swift

import Foundation

final class ProductRepository: ProductRepositoryProtocol, Sendable {
    private let apiClient: APIClientProtocol
    private let cache: CacheProtocol
    private let database: ProductDatabaseProtocol

    init(
        apiClient: APIClientProtocol,
        cache: CacheProtocol,
        database: ProductDatabaseProtocol
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.database = database
    }

    func fetchAll() async throws -> [Product] {
        // 1. Try cache
        if let cached: [Product] = cache.get(key: "products"), cache.isValid(key: "products") {
            return cached
        }

        // 2. Fetch from network
        do {
            let dtos: [ProductDTO] = try await apiClient.request(.getProducts)
            let products = try dtos.map { try ProductMapper.toDomain($0) }

            // 3. Update cache and database
            cache.set(key: "products", value: products, ttl: 300) // 5 min
            try await database.saveAll(products)

            return products
        } catch {
            // 4. Fallback to database (offline mode)
            let localProducts = try await database.fetchAll()
            if !localProducts.isEmpty { return localProducts }
            throw error
        }
    }

    func fetchById(_ id: UUID) async throws -> Product {
        if let cached: Product = cache.get(key: "product_\(id)") {
            return cached
        }

        let dto: ProductDTO = try await apiClient.request(.getProduct(id: id))
        let product = try ProductMapper.toDomain(dto)
        cache.set(key: "product_\(id)", value: product, ttl: 300)
        return product
    }

    func search(query: String) async throws -> [Product] {
        let dtos: [ProductDTO] = try await apiClient.request(.searchProducts(query: query))
        return try dtos.map { try ProductMapper.toDomain($0) }
    }

    func save(_ product: Product) async throws {
        let dto = ProductMapper.toDTO(product)
        let _: ProductDTO = try await apiClient.request(.updateProduct(id: product.id, body: dto))
        cache.invalidate(key: "products")
        cache.invalidate(key: "product_\(product.id)")
    }

    func delete(_ id: UUID) async throws {
        let _: EmptyResponse = try await apiClient.request(.deleteProduct(id: id))
        cache.invalidate(key: "products")
        cache.invalidate(key: "product_\(id)")
    }
}
```

---

## Coordinator / Router Pattern

### SwiftUI Router with @Observable

```swift
// Navigation/Router.swift

import SwiftUI

@Observable
final class Router {
    var path = NavigationPath()
    var sheet: Sheet?
    var fullScreenCover: FullScreenCover?

    // MARK: - Destinations

    enum Destination: Hashable {
        case profile(userId: UUID)
        case productDetail(productId: UUID)
        case orderHistory
        case settings
    }

    enum Sheet: Identifiable {
        case createProduct
        case editProfile
        case filter(current: FilterOptions)

        var id: String { String(describing: self) }
    }

    enum FullScreenCover: Identifiable {
        case onboarding
        case imageViewer(url: URL)

        var id: String { String(describing: self) }
    }

    // MARK: - Actions

    func push(_ destination: Destination) {
        path.append(destination)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func present(_ sheet: Sheet) {
        self.sheet = sheet
    }

    func presentFullScreen(_ cover: FullScreenCover) {
        self.fullScreenCover = cover
    }

    func dismiss() {
        sheet = nil
        fullScreenCover = nil
    }
}
```

### Router Usage in Views

```swift
struct ContentView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Router.Destination.self) { destination in
                    switch destination {
                    case .profile(let userId):
                        ProfileView(userId: userId)
                    case .productDetail(let productId):
                        ProductDetailView(productId: productId)
                    case .orderHistory:
                        OrderHistoryView()
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .createProduct:
                CreateProductView()
            case .editProfile:
                EditProfileView()
            case .filter(let current):
                FilterView(options: current)
            }
        }
        .fullScreenCover(item: $router.fullScreenCover) { cover in
            switch cover {
            case .onboarding:
                OnboardingView()
            case .imageViewer(let url):
                ImageViewerView(url: url)
            }
        }
        .environment(router)
    }
}

// Child view triggers navigation
struct HomeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button("Profile") {
            router.push(.profile(userId: UUID()))
        }
    }
}
```

### UIKit Coordinator (for UIKit-heavy projects)

```swift
protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController { get }
    func start()
}

final class AppCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    let navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let homeCoordinator = HomeCoordinator(navigationController: navigationController)
        homeCoordinator.delegate = self
        childCoordinators.append(homeCoordinator)
        homeCoordinator.start()
    }
}

extension AppCoordinator: HomeCoordinatorDelegate {
    func homeDidSelectUser(_ userId: UUID) {
        let profileCoordinator = ProfileCoordinator(
            navigationController: navigationController,
            userId: userId
        )
        childCoordinators.append(profileCoordinator)
        profileCoordinator.start()
    }
}
```

---

## Dependency Injection

### 1. Protocol-Based Manual DI (Simplest)

```swift
// Define protocol
protocol AuthServiceProtocol: Sendable {
    func signIn(email: String, password: String) async throws -> User
    func signOut() async throws
    var currentUser: User? { get async }
}

// Live implementation
final class AuthService: AuthServiceProtocol, Sendable {
    func signIn(email: String, password: String) async throws -> User { /* ... */ }
    func signOut() async throws { /* ... */ }
    var currentUser: User? { get async { /* ... */ } }
}

// Mock for tests
final class MockAuthService: AuthServiceProtocol, Sendable {
    var signInResult: Result<User, Error> = .failure(DomainError.unauthorized)
    var signOutCalled = false
    var stubbedCurrentUser: User?

    func signIn(email: String, password: String) async throws -> User {
        try signInResult.get()
    }
    func signOut() async throws { signOutCalled = true }
    var currentUser: User? { get async { stubbedCurrentUser } }
}

// Inject through init
@Observable
final class LoginViewModel {
    private let authService: AuthServiceProtocol

    init(authService: AuthServiceProtocol) {
        self.authService = authService
    }
}
```

### 2. Factory Library Pattern

```swift
// Using the Factory package (https://github.com/hmlongco/Factory)

import Factory

extension Container {
    var apiClient: Factory<APIClientProtocol> {
        self { APIClient(baseURL: URL(string: "https://api.example.com")!) }
            .singleton
    }

    var userRepository: Factory<UserRepositoryProtocol> {
        self { UserRepository(apiClient: self.apiClient()) }
    }

    var authService: Factory<AuthServiceProtocol> {
        self { AuthService(apiClient: self.apiClient()) }
    }
}

// Usage in ViewModel
@Observable
final class ProfileViewModel {
    @ObservationIgnored
    @Injected(\.userRepository) private var userRepository

    // ...
}

// Override in tests
Container.shared.userRepository.register { MockUserRepository() }
```

### 3. SwiftUI Environment

Best for design system values and view-layer dependencies.

```swift
// Define environment key
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// Provide
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.theme, .standard)
        }
    }
}

// Consume
struct MyButton: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Tap me")
            .foregroundStyle(theme.primaryColor)
    }
}
```

### DI Strategy Summary

| Approach | Best For | Testability | Boilerplate |
|---|---|---|---|
| Manual init injection | Small projects, explicit deps | Excellent | Low |
| Factory library | Medium/large projects | Excellent | Medium |
| SwiftUI Environment | Theme, design tokens, view-layer | Good | Low |
| TCA @Dependency | TCA projects | Excellent | Medium |
| Singletons | NEVER | Poor | None (that is the problem) |

---

## Error Handling Patterns

### Typed Error Hierarchy

```swift
// Network layer
enum NetworkError: Error {
    case noConnection
    case timeout
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case invalidURL
}

// Domain layer
enum DomainError: Error, Equatable {
    case notFound
    case unauthorized
    case forbidden
    case validationFailed(String)
    case conflict(String)
    case serverError
    case networkUnavailable
    case unknown(String)
}

// Mapping
extension NetworkError {
    var asDomainError: DomainError {
        switch self {
        case .noConnection, .timeout:
            return .networkUnavailable
        case .httpError(let code, _):
            switch code {
            case 401: return .unauthorized
            case 403: return .forbidden
            case 404: return .notFound
            case 409: return .conflict("Resource conflict.")
            case 500...599: return .serverError
            default: return .unknown("HTTP \(code)")
            }
        case .decodingFailed:
            return .unknown("Invalid response format.")
        case .invalidURL:
            return .unknown("Invalid request.")
        }
    }
}
```

### Typed Throws (Swift 6)

```swift
// Swift 6 typed throws
func fetchUser(id: UUID) throws(DomainError) -> User {
    guard let user = users.first(where: { $0.id == id }) else {
        throw .notFound
    }
    return user
}

// Caller knows exactly which errors are possible
do {
    let user = try fetchUser(id: someId)
} catch .notFound {
    showEmptyState()
} catch .unauthorized {
    redirectToLogin()
}
```

### ViewModel Error State

```swift
@Observable
final class OrderViewModel {
    enum AlertItem: Identifiable {
        case error(String)
        case confirmation(String, action: () async -> Void)

        var id: String {
            switch self {
            case .error(let msg): return "error_\(msg)"
            case .confirmation(let msg, _): return "confirm_\(msg)"
            }
        }
    }

    private(set) var orders: [Order] = []
    private(set) var isLoading = false
    var alert: AlertItem?

    private let orderRepository: OrderRepositoryProtocol

    init(orderRepository: OrderRepositoryProtocol) {
        self.orderRepository = orderRepository
    }

    func loadOrders() async {
        isLoading = true
        do {
            orders = try await orderRepository.fetchAll()
        } catch let error as DomainError {
            alert = .error(error.userFacingMessage)
        } catch {
            alert = .error("An unexpected error occurred.")
        }
        isLoading = false
    }

    func cancelOrder(_ id: UUID) {
        alert = .confirmation("Cancel this order?") { [weak self] in
            do {
                try await self?.orderRepository.cancel(id)
                self?.orders.removeAll { $0.id == id }
            } catch {
                self?.alert = .error("Failed to cancel order.")
            }
        }
    }
}
```

### Result Type for Complex Returns

```swift
// When a function can succeed in different ways or partially fail
enum LoadResult<T> {
    case fresh(T)               // From network, up to date
    case cached(T, age: TimeInterval)  // From cache, may be stale
    case partial(T, errors: [Error])   // Some items failed to load
}

func fetchDashboard() async -> LoadResult<Dashboard> {
    // ...
}
```

---

## Protocol-Oriented Programming

### Protocol Composition

```swift
// Small, focused protocols
protocol Identifiable {
    var id: UUID { get }
}

protocol Timestamped {
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

protocol SoftDeletable {
    var deletedAt: Date? { get }
    var isDeleted: Bool { get }
}

// Compose them
typealias DomainEntity = Identifiable & Timestamped & Sendable & Equatable

struct User: DomainEntity, SoftDeletable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }
}
```

### any vs some vs Generics

```swift
// `some` -- use when the caller does not need to know the concrete type
// Preferred for return types and function parameters in most cases
func makeRepository() -> some UserRepositoryProtocol {
    UserRepository(apiClient: apiClient)
}

// `any` -- use when you need to store heterogeneous types in a collection
// or when the concrete type varies at runtime
var services: [any ServiceProtocol] = [AuthService(), AnalyticsService()]

// Generics -- use when you need to constrain relationships between types
func sync<R: RepositoryProtocol>(_ repository: R, with remote: R.RemoteType) async throws {
    // R.RemoteType is an associated type -- generics preserve type relationships
}

// Rule of thumb:
// - Function parameter with one conforming type -> `some`
// - Collection of mixed types -> `any`
// - Associated types or type relationships -> generics
// - Avoid `any` if `some` works -- `any` has runtime overhead (existential container)
```

### Protocol Extensions with Default Implementations

```swift
protocol Cacheable {
    var cacheKey: String { get }
    var cacheTTL: TimeInterval { get }
}

extension Cacheable {
    var cacheTTL: TimeInterval { 300 } // Default: 5 minutes
}

extension Cacheable where Self: Identifiable {
    var cacheKey: String { "\(type(of: self))_\(id)" }
}

// User gets both defaults for free
struct User: Identifiable, Cacheable {
    let id: UUID
    var name: String
    // cacheKey = "User_<uuid>"
    // cacheTTL = 300
}
```

---

## Service Layer vs Use Cases

| Aspect | Service | Use Case |
|---|---|---|
| Scope | Multiple related operations | Single operation |
| Naming | `UserService`, `AuthService` | `FetchUserUseCase`, `PlaceOrderUseCase` |
| When to use | Small/medium projects, CRUD-heavy | Clean Architecture, complex business logic |
| Testability | Good (protocol-based) | Excellent (single responsibility) |
| Reuse | Multiple ViewModels share the service | Multiple ViewModels share the use case |

```swift
// Service approach (simpler)
protocol UserServiceProtocol {
    func fetchAll() async throws -> [User]
    func fetchById(_ id: UUID) async throws -> User
    func updateProfile(name: String, email: String) async throws -> User
    func changePassword(old: String, new: String) async throws
}

// Use Case approach (more granular)
protocol FetchUserUseCaseProtocol {
    func execute(id: UUID) async throws -> User
}
protocol UpdateProfileUseCaseProtocol {
    func execute(name: String, email: String) async throws -> User
}
protocol ChangePasswordUseCaseProtocol {
    func execute(oldPassword: String, newPassword: String) async throws
}
```

**Recommendation:** Start with Services. Refactor to Use Cases when business logic within a service method exceeds 10-15 lines or needs independent testing.

---

## Code Organization Conventions

### File Naming

| Type | Convention | Example |
|---|---|---|
| View | `<Name>View.swift` | `HomeView.swift` |
| ViewModel | `<Name>ViewModel.swift` | `HomeViewModel.swift` |
| Model | `<Name>.swift` | `User.swift` |
| Protocol | `<Name>Protocol.swift` | `UserRepositoryProtocol.swift` |
| Extension | `<Type>+<Context>.swift` | `String+Validation.swift` |
| DTO | `<Name>DTO.swift` | `UserDTO.swift` |
| Mapper | `<Name>Mapper.swift` | `UserMapper.swift` |
| Mock | `Mock<Name>.swift` | `MockUserRepository.swift` |
| Use Case | `<Verb><Noun>UseCase.swift` | `FetchUserUseCase.swift` |

### Declaration Ordering Within a File

```swift
// 1. Type declaration
final class HomeViewModel {

    // 2. Nested types (enums, structs)
    enum ViewState { ... }

    // 3. Static properties
    static let maxItems = 50

    // 4. Published/observable state (public read)
    private(set) var state: ViewState = .idle
    private(set) var items: [Item] = []

    // 5. Mutable public state (user input)
    var searchQuery = ""

    // 6. Private properties
    private let repository: ItemRepositoryProtocol
    private var loadTask: Task<Void, Never>?

    // 7. Init
    init(repository: ItemRepositoryProtocol) { ... }

    // 8. Public methods (actions)
    func loadItems() async { ... }
    func deleteItem(_ id: UUID) async { ... }

    // 9. Computed properties
    var filteredItems: [Item] { ... }
    var isEmpty: Bool { ... }

    // 10. Private methods
    private func handleError(_ error: Error) { ... }
}
```

### MARK Comments

```swift
final class UserRepository: UserRepositoryProtocol {

    // MARK: - Properties

    private let apiClient: APIClientProtocol
    private let cache: CacheProtocol

    // MARK: - Init

    init(apiClient: APIClientProtocol, cache: CacheProtocol) {
        self.apiClient = apiClient
        self.cache = cache
    }

    // MARK: - UserRepositoryProtocol

    func fetchAll() async throws -> [User] { ... }
    func fetchById(_ id: UUID) async throws -> User { ... }

    // MARK: - Private

    private func invalidateCache() { ... }
}
```

### Extensions for Protocol Conformance

```swift
// Separate extension per protocol conformance

struct User: Identifiable {
    let id: UUID
    var name: String
    var email: String
}

// MARK: - Codable

extension User: Codable {}

// MARK: - Comparable

extension User: Comparable {
    static func < (lhs: User, rhs: User) -> Bool {
        lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - CustomStringConvertible

extension User: CustomStringConvertible {
    var description: String { "\(name) (\(email))" }
}
```

---

## Summary of Pattern Selection

| Need | Pattern | Reference Section |
|---|---|---|
| Abstract data access | Repository | This file (top) |
| Screen-to-screen navigation | Router / Coordinator | This file (middle) |
| Inject dependencies | Protocol + init / Factory / Environment | This file (DI section) |
| Handle errors across layers | Typed error hierarchy | This file (errors) |
| Define clear interfaces | Protocol composition, POP | This file (POP) |
| Organize code consistently | File naming, MARK, ordering | This file (bottom) |
| Choose overall architecture | MVVM / Clean / TCA | SKILL.md (selection guide) |
