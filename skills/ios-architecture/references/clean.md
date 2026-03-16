# Clean Architecture -- iOS Architecture Reference

## Overview

Clean Architecture separates an iOS app into three layers with a strict dependency rule: outer layers depend on inner layers, never the reverse. The Domain layer is pure Swift with zero framework imports.

```
┌─────────────────────────────────────┐
│         Presentation Layer          │  SwiftUI Views, ViewModels
│  (depends on Domain)                │
├─────────────────────────────────────┤
│           Domain Layer              │  Entities, Use Cases, Repository protocols
│  (depends on NOTHING)               │  Pure Swift -- no UIKit, no SwiftUI
├─────────────────────────────────────┤
│            Data Layer               │  API clients, DB, Repository implementations
│  (depends on Domain)                │  Conforms to Domain protocols
└─────────────────────────────────────┘
```

---

## The Dependency Rule

**Inner layers NEVER know about outer layers.**

- Domain defines `UserRepositoryProtocol` (protocol).
- Data provides `UserRepository` (concrete class conforming to the protocol).
- Presentation receives the protocol through DI -- it never imports Data directly.
- Domain NEVER imports SwiftUI, UIKit, Alamofire, or any framework.

This means you can:
- Swap networking libraries without touching Domain or Presentation
- Unit test Domain logic with no frameworks
- Replace SwiftUI with UIKit without changing business rules

---

## Domain Layer

### Entities

Pure Swift structs. These represent core business objects.

```swift
// Domain/Entities/User.swift

struct User: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var email: String
    var role: Role

    enum Role: String, Sendable {
        case admin, member, guest
    }
}
```

```swift
// Domain/Entities/Order.swift

struct Order: Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    var items: [OrderItem]
    var status: Status
    let createdAt: Date

    var totalPrice: Decimal {
        items.reduce(0) { $0 + $1.price * Decimal($1.quantity) }
    }

    enum Status: String, Sendable {
        case pending, confirmed, shipped, delivered, cancelled
    }
}

struct OrderItem: Equatable, Sendable {
    let productId: UUID
    let name: String
    let price: Decimal
    let quantity: Int
}
```

### Domain Errors

```swift
// Domain/Errors/DomainError.swift

enum DomainError: Error, Equatable {
    case notFound
    case unauthorized
    case validationFailed(String)
    case serverError
    case networkUnavailable
    case unknown(String)
}
```

### Repository Protocols (defined in Domain)

```swift
// Domain/Repositories/UserRepositoryProtocol.swift

protocol UserRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [User]
    func fetchById(_ id: UUID) async throws -> User
    func create(_ user: User) async throws -> User
    func update(_ user: User) async throws -> User
    func delete(_ id: UUID) async throws
}
```

```swift
// Domain/Repositories/OrderRepositoryProtocol.swift

protocol OrderRepositoryProtocol: Sendable {
    func fetchOrders(for userId: UUID) async throws -> [Order]
    func fetchById(_ id: UUID) async throws -> Order
    func placeOrder(_ order: Order) async throws -> Order
    func cancelOrder(_ id: UUID) async throws
}
```

### Use Cases

A Use Case encapsulates a single business operation. It depends on repository protocols and contains business rules.

```swift
// Domain/UseCases/FetchUserUseCase.swift

protocol FetchUserUseCaseProtocol: Sendable {
    func execute(id: UUID) async throws -> User
}

final class FetchUserUseCase: FetchUserUseCaseProtocol, Sendable {
    private let userRepository: UserRepositoryProtocol

    init(userRepository: UserRepositoryProtocol) {
        self.userRepository = userRepository
    }

    func execute(id: UUID) async throws -> User {
        try await userRepository.fetchById(id)
    }
}
```

```swift
// Domain/UseCases/PlaceOrderUseCase.swift

protocol PlaceOrderUseCaseProtocol: Sendable {
    func execute(userId: UUID, items: [OrderItem]) async throws -> Order
}

final class PlaceOrderUseCase: PlaceOrderUseCaseProtocol, Sendable {
    private let orderRepository: OrderRepositoryProtocol
    private let userRepository: UserRepositoryProtocol

    init(orderRepository: OrderRepositoryProtocol, userRepository: UserRepositoryProtocol) {
        self.orderRepository = orderRepository
        self.userRepository = userRepository
    }

    func execute(userId: UUID, items: [OrderItem]) async throws -> Order {
        // Business rule: verify user exists
        let user = try await userRepository.fetchById(userId)

        // Business rule: guests cannot place orders
        guard user.role != .guest else {
            throw DomainError.unauthorized
        }

        // Business rule: at least one item required
        guard !items.isEmpty else {
            throw DomainError.validationFailed("Order must contain at least one item.")
        }

        let order = Order(
            id: UUID(),
            userId: userId,
            items: items,
            status: .pending,
            createdAt: Date()
        )

        return try await orderRepository.placeOrder(order)
    }
}
```

---

## Data Layer

### DTOs (Data Transfer Objects)

DTOs map to/from JSON. They are NOT used outside the Data layer.

```swift
// Data/Network/DTOs/UserDTO.swift

struct UserDTO: Codable {
    let id: String
    let name: String
    let email: String
    let role: String
    let created_at: String  // API uses snake_case
}
```

### Mappers

Convert between DTOs and Domain entities.

```swift
// Data/Mappers/UserMapper.swift

enum UserMapper {
    static func toDomain(_ dto: UserDTO) throws -> User {
        guard let id = UUID(uuidString: dto.id) else {
            throw DomainError.validationFailed("Invalid user ID")
        }
        guard let role = User.Role(rawValue: dto.role) else {
            throw DomainError.validationFailed("Unknown role: \(dto.role)")
        }
        return User(id: id, name: dto.name, email: dto.email, role: role)
    }

    static func toDTO(_ user: User) -> UserDTO {
        UserDTO(
            id: user.id.uuidString,
            name: user.name,
            email: user.email,
            role: user.role.rawValue,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
    }
}
```

### API Client

```swift
// Data/Network/APIClient.swift

protocol APIClientProtocol: Sendable {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
}

final class APIClient: APIClientProtocol, Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        var urlRequest = URLRequest(url: baseURL.appending(path: endpoint.path))
        urlRequest.httpMethod = endpoint.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = endpoint.body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}
```

### Repository Implementation

```swift
// Data/Repositories/UserRepository.swift

final class UserRepository: UserRepositoryProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchAll() async throws -> [User] {
        let dtos: [UserDTO] = try await apiClient.request(.getUsers)
        return try dtos.map { try UserMapper.toDomain($0) }
    }

    func fetchById(_ id: UUID) async throws -> User {
        let dto: UserDTO = try await apiClient.request(.getUser(id: id))
        return try UserMapper.toDomain(dto)
    }

    func create(_ user: User) async throws -> User {
        let dto: UserDTO = try await apiClient.request(.createUser(body: UserMapper.toDTO(user)))
        return try UserMapper.toDomain(dto)
    }

    func update(_ user: User) async throws -> User {
        let dto: UserDTO = try await apiClient.request(.updateUser(id: user.id, body: UserMapper.toDTO(user)))
        return try UserMapper.toDomain(dto)
    }

    func delete(_ id: UUID) async throws {
        let _: EmptyResponse = try await apiClient.request(.deleteUser(id: id))
    }
}
```

### Network Errors

```swift
// Data/Network/NetworkError.swift

enum NetworkError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(Error)
    case noConnection
}

// MARK: - Map to Domain

extension NetworkError {
    var asDomainError: DomainError {
        switch self {
        case .noConnection:
            return .networkUnavailable
        case .httpError(let code) where code == 401:
            return .unauthorized
        case .httpError(let code) where code == 404:
            return .notFound
        case .httpError(let code) where code >= 500:
            return .serverError
        default:
            return .unknown(localizedDescription)
        }
    }
}
```

---

## Presentation Layer

### ViewModel Using Use Cases

```swift
// Presentation/Features/OrderCreate/OrderCreateViewModel.swift

import Foundation

@Observable
final class OrderCreateViewModel {
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var createdOrder: Order?

    var items: [OrderItem] = []

    private let placeOrderUseCase: PlaceOrderUseCaseProtocol
    private let userId: UUID

    init(userId: UUID, placeOrderUseCase: PlaceOrderUseCaseProtocol) {
        self.userId = userId
        self.placeOrderUseCase = placeOrderUseCase
    }

    func submit() async {
        isSubmitting = true
        errorMessage = nil

        do {
            createdOrder = try await placeOrderUseCase.execute(userId: userId, items: items)
        } catch let error as DomainError {
            errorMessage = error.userFacingMessage
        } catch {
            errorMessage = "An unexpected error occurred."
        }

        isSubmitting = false
    }
}

// MARK: - User-facing error messages

extension DomainError {
    var userFacingMessage: String {
        switch self {
        case .notFound:
            return "The requested item was not found."
        case .unauthorized:
            return "You don't have permission to do this."
        case .validationFailed(let message):
            return message
        case .serverError:
            return "Server error. Please try again later."
        case .networkUnavailable:
            return "No internet connection."
        case .unknown:
            return "Something went wrong."
        }
    }
}
```

---

## DI Container

The DI container wires everything together at the app root.

```swift
// App/DIContainer.swift

import Foundation

final class AppDIContainer: Sendable {
    // MARK: - Network
    private let apiClient: APIClientProtocol

    init(baseURL: URL) {
        self.apiClient = APIClient(baseURL: baseURL)
    }

    // MARK: - Repositories
    func makeUserRepository() -> UserRepositoryProtocol {
        UserRepository(apiClient: apiClient)
    }

    func makeOrderRepository() -> OrderRepositoryProtocol {
        OrderRepository(apiClient: apiClient)
    }

    // MARK: - Use Cases
    func makeFetchUserUseCase() -> FetchUserUseCaseProtocol {
        FetchUserUseCase(userRepository: makeUserRepository())
    }

    func makePlaceOrderUseCase() -> PlaceOrderUseCaseProtocol {
        PlaceOrderUseCase(
            orderRepository: makeOrderRepository(),
            userRepository: makeUserRepository()
        )
    }

    // MARK: - ViewModels
    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(userRepository: makeUserRepository())
    }

    func makeOrderCreateViewModel(userId: UUID) -> OrderCreateViewModel {
        OrderCreateViewModel(userId: userId, placeOrderUseCase: makePlaceOrderUseCase())
    }
}
```

```swift
// App/MyAppApp.swift

import SwiftUI

@main
struct MyApp: App {
    private let container = AppDIContainer(baseURL: URL(string: "https://api.example.com")!)

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: container.makeHomeViewModel())
        }
    }
}
```

---

## File Structure

```
MyApp/
├── App/
│   ├── MyAppApp.swift
│   └── DIContainer.swift
├── Domain/
│   ├── Entities/
│   │   ├── User.swift
│   │   ├── Order.swift
│   │   └── OrderItem.swift
│   ├── UseCases/
│   │   ├── FetchUserUseCase.swift
│   │   └── PlaceOrderUseCase.swift
│   ├── Repositories/
│   │   ├── UserRepositoryProtocol.swift
│   │   └── OrderRepositoryProtocol.swift
│   └── Errors/
│       └── DomainError.swift
├── Data/
│   ├── Network/
│   │   ├── APIClient.swift
│   │   ├── Endpoint.swift
│   │   ├── NetworkError.swift
│   │   └── DTOs/
│   │       ├── UserDTO.swift
│   │       └── OrderDTO.swift
│   ├── Persistence/
│   │   └── (SwiftData / CoreData)
│   ├── Repositories/
│   │   ├── UserRepository.swift
│   │   └── OrderRepository.swift
│   └── Mappers/
│       ├── UserMapper.swift
│       └── OrderMapper.swift
├── Presentation/
│   ├── Features/
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   └── HomeViewModel.swift
│   │   └── OrderCreate/
│   │       ├── OrderCreateView.swift
│   │       └── OrderCreateViewModel.swift
│   ├── Navigation/
│   │   └── Router.swift
│   └── DesignSystem/
│       ├── Components/
│       └── Theme.swift
└── Resources/
    └── Assets.xcassets
```

---

## When to Use Clean Architecture vs Simpler MVVM

### Use Clean Architecture when:
- The project has 10+ screens or complex business rules
- Multiple developers work on the codebase
- The app needs offline support (repository layer manages cache + network)
- You want exhaustive unit testing of business logic
- The data sources may change (e.g., REST to GraphQL)

### Stick with simple MVVM when:
- Solo developer, small project (<10 screens)
- Business logic is minimal (mostly CRUD)
- Rapid prototyping or MVP
- Adding Use Cases would just be pass-through wrappers

### Signs you should migrate from MVVM to Clean:
- ViewModels exceed 200 lines
- Same business logic is duplicated across ViewModels
- You need to reuse logic across platforms (iOS + watchOS + macOS)
- Test setup requires too many mocks because ViewModel depends on too many services

---

## Testing Use Cases

```swift
import Testing
@testable import MyApp

struct PlaceOrderUseCaseTests {
    let mockOrderRepo = MockOrderRepository()
    let mockUserRepo = MockUserRepository()

    var sut: PlaceOrderUseCase {
        PlaceOrderUseCase(orderRepository: mockOrderRepo, userRepository: mockUserRepo)
    }

    @Test
    func guestCannotPlaceOrder() async {
        mockUserRepo.fetchByIdResult = .success(User(id: UUID(), name: "Guest", email: "g@b.com", role: .guest))

        await #expect(throws: DomainError.unauthorized) {
            try await sut.execute(userId: UUID(), items: [.stub()])
        }
    }

    @Test
    func emptyOrderThrowsValidation() async {
        mockUserRepo.fetchByIdResult = .success(User(id: UUID(), name: "Admin", email: "a@b.com", role: .admin))

        await #expect(throws: DomainError.self) {
            try await sut.execute(userId: UUID(), items: [])
        }
    }

    @Test
    func validOrderIsPlaced() async throws {
        let userId = UUID()
        mockUserRepo.fetchByIdResult = .success(User(id: userId, name: "Alice", email: "a@b.com", role: .member))
        mockOrderRepo.placeOrderResult = .success(Order(id: UUID(), userId: userId, items: [.stub()], status: .pending, createdAt: Date()))

        let order = try await sut.execute(userId: userId, items: [.stub()])

        #expect(order.status == .pending)
        #expect(order.userId == userId)
    }
}
```
