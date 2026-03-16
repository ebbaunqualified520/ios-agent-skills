# iOS Agent Skills

You have access to 9 expert-level iOS development skills. Each skill activates based on the topic you're working on.

## Available Skills

### ios-swiftui
Use when building SwiftUI views, layouts, navigation, animations, or working with state management.
Core rules: Use @Observable (iOS 17+) over ObservableObject. Use NavigationStack (not NavigationView). Use LazyVStack for large collections. Keep body pure. Avoid AnyView. Use .task for async work.
Detailed guidance: `skills/ios-swiftui/SKILL.md`

### ios-architecture
Use when designing app architecture, setting up project structure, or choosing patterns (MVVM, Clean, TCA).
Core rules: Default to MVVM + @Observable. ViewModels must not import SwiftUI. Use protocols for all external dependencies. Domain layer = pure Swift only. Use SPM for modules at 50k+ LOC.
Detailed guidance: `skills/ios-architecture/SKILL.md`

### ios-networking
Use when building API clients, handling HTTP requests, implementing authentication, or working with WebSockets.
Core rules: Use URLSession async/await. Create typed API client with generic request method. Use Codable. Implement retry with exponential backoff. Never store tokens in UserDefaults.
Detailed guidance: `skills/ios-networking/SKILL.md`

### ios-data
Use when persisting data, creating models, querying databases, handling migrations, or syncing with iCloud.
Core rules: Use SwiftData for iOS 17+ projects. Repository pattern for all data access. isStoredInMemoryOnly for test containers. Never expose persistence framework to UI.
Detailed guidance: `skills/ios-data/SKILL.md`

### ios-security
Use when working with Keychain, biometrics, encryption, authentication flows, or privacy features.
Core rules: Use Keychain for all sensitive data. Implement biometrics as convenience (password as fallback). Use CryptoKit (not CommonCrypto). Validate SSL certificates. Add privacy manifest entries.
Detailed guidance: `skills/ios-security/SKILL.md`

### ios-concurrency
Use when writing async/await code, working with actors, implementing background tasks, or migrating to Swift 6.
Core rules: Use async/await over callbacks/Combine. Prefer structured concurrency. Use actors for shared mutable state. Mark UI code @MainActor. Make value types Sendable.
Detailed guidance: `skills/ios-concurrency/SKILL.md`

### ios-testing
Use when writing unit tests, UI tests, creating mocks, or setting up test infrastructure.
Core rules: Use Swift Testing (@Test, #expect) for new tests. Keep XCTest for UI and performance tests. Protocol-based DI for testability. URLProtocol for network mocking. isStoredInMemoryOnly for SwiftData.
Detailed guidance: `skills/ios-testing/SKILL.md`

### ios-accessibility
Use when implementing VoiceOver support, Dynamic Type, or auditing accessibility compliance.
Core rules: Every interactive element needs accessibilityLabel. Use built-in text styles for Dynamic Type. Touch targets minimum 44x44pt. Test with VoiceOver. Support Bold Text and Reduce Motion.
Detailed guidance: `skills/ios-accessibility/SKILL.md`

### ios-performance
Use when optimizing memory, profiling with Instruments, improving launch time, or fixing frame drops.
Core rules: Profile before optimizing. Use weak self in closures capturing self. Prefer @Observable over ObservableObject. Use lazy containers for large lists. Never block main thread.
Detailed guidance: `skills/ios-performance/SKILL.md`

## Quick Reference

| Task | Skill |
|------|-------|
| Build a SwiftUI view | ios-swiftui |
| Choose an architecture | ios-architecture |
| Make an API call | ios-networking |
| Save data locally | ios-data |
| Store a password/token | ios-security |
| Write async code | ios-concurrency |
| Write a test | ios-testing |
| Add VoiceOver support | ios-accessibility |
| Fix a memory leak | ios-performance |
