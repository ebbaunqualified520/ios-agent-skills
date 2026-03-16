# Modular Architecture with SPM -- iOS Architecture Reference

## Overview

Modular architecture splits an iOS app into Swift Package Manager (SPM) local packages. Each module has clear boundaries, explicit dependencies, and its own test target. This improves build times (incremental builds), enforces separation, and enables parallel development.

---

## Module Types

```
MyApp.xcodeproj
├── Packages/
│   ├── CoreKit/           (models, protocols, utilities shared by all)
│   ├── NetworkKit/        (API client, endpoints, DTOs)
│   ├── DesignSystem/      (UI components, colors, fonts, tokens)
│   ├── Features/
│   │   ├── HomeFeature/   (Home screen: view, viewmodel, local models)
│   │   ├── ProfileFeature/
│   │   ├── OrderFeature/
│   │   └── AuthFeature/
│   └── SharedServices/    (analytics, logging, feature flags)
└── App/                   (main target -- ties everything together)
    ├── MyAppApp.swift
    └── DIContainer.swift
```

### Module Categories

| Category | Purpose | Can Import | Example |
|---|---|---|---|
| CoreKit | Domain models, protocols, extensions | Nothing (pure Swift) | `User`, `UserRepositoryProtocol` |
| NetworkKit | API client, DTOs, endpoint definitions | CoreKit | `APIClient`, `UserDTO` |
| DesignSystem | Shared UI components, theme | CoreKit (for models), SwiftUI | `PrimaryButton`, `AppTheme` |
| Feature | One screen or feature area | CoreKit, NetworkKit, DesignSystem | `HomeFeature` |
| SharedServices | Cross-cutting concerns | CoreKit | `AnalyticsService`, `Logger` |
| App | Entry point, DI, navigation | Everything | `MyAppApp`, `AppCoordinator` |

---

## Dependency Rules

```
                    ┌─────────┐
                    │   App   │  (imports everything)
                    └────┬────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐    ┌──────▼──────┐   ┌────▼────┐
   │HomeFeature│   │ProfileFeature│  │OrderFeature│
   └────┬────┘    └──────┬──────┘   └────┬────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐    ┌──────▼──────┐   ┌────▼────────┐
   │NetworkKit│   │DesignSystem │   │SharedServices│
   └────┬────┘    └──────┬──────┘   └────┬────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
                    ┌────▼────┐
                    │ CoreKit │  (no dependencies)
                    └─────────┘
```

**Critical rules:**
1. **Feature modules NEVER import each other.** HomeFeature cannot import ProfileFeature.
2. **Dependencies flow downward only.** CoreKit never imports NetworkKit.
3. **The App target is the only place that imports all modules** and wires them together.
4. **Circular dependencies are impossible** if you follow these rules.

---

## Package.swift Examples

### CoreKit

```swift
// Packages/CoreKit/Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)
```

```swift
// Packages/CoreKit/Sources/CoreKit/Models/User.swift

public struct User: Identifiable, Equatable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var email: String

    public init(id: UUID, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

```swift
// Packages/CoreKit/Sources/CoreKit/Protocols/UserRepositoryProtocol.swift

public protocol UserRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [User]
    func fetchById(_ id: UUID) async throws -> User
}
```

### NetworkKit

```swift
// Packages/NetworkKit/Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NetworkKit", targets: ["NetworkKit"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "NetworkKit",
            dependencies: ["CoreKit"]
        ),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit"]
        ),
    ]
)
```

### Feature Module

```swift
// Packages/Features/HomeFeature/Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HomeFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../NetworkKit"),
        .package(path: "../../DesignSystem"),
    ],
    targets: [
        .target(
            name: "HomeFeature",
            dependencies: ["CoreKit", "NetworkKit", "DesignSystem"]
        ),
        .testTarget(
            name: "HomeFeatureTests",
            dependencies: ["HomeFeature"]
        ),
    ]
)
```

### DesignSystem

```swift
// Packages/DesignSystem/Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["CoreKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        ),
    ]
)
```

---

## Feature Module Internal Structure

```
HomeFeature/
├── Sources/HomeFeature/
│   ├── HomeView.swift
│   ├── HomeViewModel.swift
│   ├── Components/
│   │   ├── StatCard.swift
│   │   └── RecentActivityRow.swift
│   └── Models/
│       └── HomeSection.swift       (feature-local model, not in CoreKit)
├── Tests/HomeFeatureTests/
│   └── HomeViewModelTests.swift
└── Package.swift
```

### Feature Entry Point Pattern

Each feature module exposes a single public entry point view. The App target creates it with injected dependencies.

```swift
// Packages/Features/HomeFeature/Sources/HomeFeature/HomeView.swift

import SwiftUI
import CoreKit

public struct HomeView: View {
    @State private var viewModel: HomeViewModel

    public init(userRepository: UserRepositoryProtocol) {
        _viewModel = State(initialValue: HomeViewModel(userRepository: userRepository))
    }

    public var body: some View {
        // ...
    }
}
```

```swift
// App/MyAppApp.swift -- in the main App target

import SwiftUI
import HomeFeature
import ProfileFeature
import NetworkKit
import CoreKit

@main
struct MyApp: App {
    let apiClient = APIClient(baseURL: URL(string: "https://api.example.com")!)

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView(userRepository: UserRepository(apiClient: apiClient))
                    .tabItem { Label("Home", systemImage: "house") }

                ProfileView(userRepository: UserRepository(apiClient: apiClient))
                    .tabItem { Label("Profile", systemImage: "person") }
            }
        }
    }
}
```

---

## Cross-Feature Communication

Since features cannot import each other, use one of these patterns:

### 1. Closure-Based Callbacks

```swift
// HomeFeature exposes a callback
public struct HomeView: View {
    let onUserSelected: (UUID) -> Void  // App target handles navigation

    public init(userRepository: UserRepositoryProtocol, onUserSelected: @escaping (UUID) -> Void) {
        self.onUserSelected = onUserSelected
        // ...
    }
}

// App target wires it
HomeView(userRepository: repo) { userId in
    // Navigate to ProfileFeature
    router.push(.profile(userId))
}
```

### 2. Protocol-Based Coordinator (in CoreKit)

```swift
// CoreKit/Protocols/AppNavigator.swift
public protocol AppNavigator: AnyObject {
    func showProfile(userId: UUID)
    func showOrder(orderId: UUID)
    func showSettings()
}

// Feature uses it
public struct HomeView: View {
    let navigator: AppNavigator
    // ...
}

// App target implements it
final class AppRouter: AppNavigator, Observable {
    // ...
}
```

### 3. Notification / Event Bus (last resort)

Use sparingly. Prefer explicit protocols or closures.

---

## Import Ordering Convention

Within each module, order imports consistently:

```swift
// 1. System frameworks
import Foundation
import SwiftUI

// 2. Internal modules (alphabetical)
import CoreKit
import DesignSystem
import NetworkKit

// 3. External packages (alphabetical)
import ComposableArchitecture
```

---

## Build Performance Benefits

| Metric | Monolithic | Modular (8 modules) |
|---|---|---|
| Clean build | ~90s | ~90s (same) |
| Incremental (1 file change in 1 feature) | ~30s | ~5s |
| Parallel build | Limited | Modules build in parallel |
| Indexing | Slow | Per-module, faster |

**Key insight:** Modularization does NOT speed up clean builds. It dramatically speeds up incremental builds because Xcode only recompiles the changed module and its dependents.

---

## Access Control in Modules

SPM modules enforce access control strictly. You must mark public everything that needs to be visible outside the module.

```swift
// In CoreKit -- needs to be public
public struct User: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {  // init MUST be public
        self.id = id
        self.name = name
    }
}

// In HomeFeature -- internal by default (only used within the feature)
struct HomeSection {  // no public needed
    let title: String
    let items: [User]
}
```

**Rule:** Only mark `public` what the module's consumers need. Keep internal details `internal` (default) or `private`.

---

## When to Modularize

### Modularize when:
- Build times exceed 30 seconds for incremental changes
- 3+ developers frequently cause merge conflicts in the same files
- You want to enforce architectural boundaries at compile time
- The project has 50k+ lines of code
- You need to share code between app and app extensions (widgets, watch)
- You want independent previews per feature

### Do NOT modularize when:
- Solo developer, small project
- The overhead of managing Package.swift files outweighs benefits
- The team is unfamiliar with SPM
- Rapid prototyping phase (modularize later when architecture stabilizes)

### Incremental modularization strategy:
1. Extract `CoreKit` first (models, protocols) -- smallest risk
2. Extract `DesignSystem` next (shared UI) -- high reuse value
3. Extract `NetworkKit` -- isolates all API concerns
4. Extract features one at a time, starting with the most independent one
5. Keep the monolithic app target shrinking until it only contains DI + navigation

---

## Xcode Integration

### Adding local packages to Xcode project:
1. File -> Add Package Dependencies -> Add Local
2. Select the `Packages/CoreKit` directory
3. In the App target -> General -> Frameworks -> add `CoreKit`

### Or reference in the project's workspace:
```
MyApp.xcworkspace/
├── MyApp.xcodeproj
└── Packages/           (drag entire Packages folder into workspace)
```

### Running tests for a specific module:
```bash
# From the package directory
swift test --package-path Packages/CoreKit

# Or from Xcode: select the module's test scheme
```

---

## Checklist for Creating a New Feature Module

1. Create `Packages/Features/NewFeature/` directory
2. Create `Package.swift` with dependencies on CoreKit, DesignSystem (and NetworkKit if needed)
3. Create `Sources/NewFeature/` with the feature's View + ViewModel
4. Create `Tests/NewFeatureTests/` with at least one ViewModel test
5. Add the package to the Xcode project
6. Add `NewFeature` as a dependency to the App target
7. Wire the feature's entry point view in the App target with injected dependencies
8. Verify: `import NewFeature` compiles. `import HomeFeature` from NewFeature does NOT compile.
