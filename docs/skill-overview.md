# Skill Overview

Detailed description of each skill, what it covers, and when to use it.

## ios-swiftui

**Scope:** Everything related to building user interfaces with SwiftUI.

**SKILL.md covers:**
- 10 core rules (prefer @Observable, use NavigationStack, avoid AnyView, etc.)
- Decision tables: state management, layout containers, navigation patterns, presentation
- Quick patterns: @Observable model, NavigationStack, custom ViewModifier, async data loading
- Anti-patterns: 10 common SwiftUI mistakes
- iOS version feature matrix (iOS 16-18)

**Reference files:**
| File | Content |
|------|---------|
| `layout.md` | VStack/HStack/ZStack, Grid, LazyStacks, ScrollView, List, ForEach, GeometryReader, ViewThatFits |
| `state.md` | @State, @Binding, @Observable, @Environment, @Bindable, ObservableObject migration |
| `navigation.md` | NavigationStack, NavigationSplitView, sheets, alerts, popovers, TabView, deep linking |
| `animation.md` | withAnimation, matchedGeometryEffect, PhaseAnimator, KeyframeAnimator, transitions, springs |
| `patterns.md` | ViewModifier, @ViewBuilder, PreferenceKey, lifecycle, UIKit interop, performance |

---

## ios-architecture

**Scope:** App structure, design patterns, module organization.

**SKILL.md covers:**
- Architecture selection guide (project size → recommended pattern)
- 10 core rules (MVVM default, ViewModels don't import SwiftUI, protocol-based deps, etc.)
- 3 folder structure templates (Simple MVVM, Clean Architecture, TCA)
- Anti-patterns table with fixes
- Testing strategy per architecture

**Reference files:**
| File | Content |
|------|---------|
| `mvvm.md` | MVVM with @Observable, ViewModel patterns, View-ViewModel binding, testing |
| `clean.md` | Clean Architecture layers, Use Cases, DTOs, dependency rule, DI container |
| `tca.md` | Composable Architecture: Reducer, Store, @ObservableState, Effects, testing |
| `modular.md` | SPM local packages, Package.swift, feature modules, build time optimization |
| `patterns.md` | Repository, Coordinator/Router, error handling, POP, Factory DI |

---

## ios-networking

**Scope:** HTTP communication, API clients, authentication, real-time connections.

**SKILL.md covers:**
- 10 core rules (async/await, generic API client, retry, token management)
- Decision guide: 8 scenarios (simple GET → WebSocket)
- Minimal URLSession example + production API client
- HTTP method semantics
- Common mistakes table (9 entries)

**Reference files:**
| File | Content |
|------|---------|
| `urlsession.md` | URLSession async/await, configuration, data/upload/download tasks, background |
| `api-client.md` | Type-safe generic client, endpoint protocol, request building, interceptors |
| `error-retry.md` | Error types, retry with exponential backoff, circuit breaker, timeout handling |
| `advanced.md` | OAuth2 flow, WebSocket, certificate pinning, multipart upload, GraphQL, caching |

---

## ios-data

**Scope:** Data persistence, storage, migrations, sync.

**SKILL.md covers:**
- Storage selection guide (8 scenarios)
- Decision flowchart for persistence layer
- SwiftData and Core Data quick references
- Repository pattern, offline-first architecture
- Migration and performance checklists

**Reference files:**
| File | Content |
|------|---------|
| `swiftdata.md` | @Model, ModelContainer, @Query, #Predicate, relationships, migrations, CloudKit |
| `coredata.md` | NSPersistentContainer, NSFetchRequest, batch operations, lightweight migration |
| `storage.md` | UserDefaults, @AppStorage, FileManager, Keychain, iCloud KV, SQLite/GRDB |

---

## ios-security

**Scope:** Credential storage, encryption, authentication, privacy.

**SKILL.md covers:**
- 15 non-negotiable security rules
- Layered security architecture
- File organization pattern (7 subdirectories)
- Error handling strategy (internal vs user-facing)
- Quick decision guide (15 scenarios)

**Reference files:**
| File | Content |
|------|---------|
| `keychain.md` | SecItem CRUD, access control, Keychain groups, wrapper pattern |
| `biometrics.md` | LAContext, Face ID/Touch ID, fallback to passcode, error handling |
| `cryptokit.md` | Symmetric encryption (AES-GCM), hashing (SHA256), HMAC, key agreement |
| `authentication.md` | Sign in with Apple, OAuth2 PKCE, token refresh, session management |
| `privacy.md` | Privacy manifest, ATT, purpose strings, data minimization, ATS |

---

## ios-concurrency

**Scope:** Async programming, thread safety, Swift 6 migration.

**SKILL.md covers:**
- 10 core rules on async/await, actors, Sendable
- Decision guide (8 scenarios)
- Quick references for each concurrency primitive
- Swift 6 strict concurrency guide
- 8 anti-patterns with BAD/GOOD examples

**Reference files:**
| File | Content |
|------|---------|
| `async-await.md` | Task, TaskGroup, async let, withCheckedContinuation, cancellation |
| `actors.md` | Actor isolation, @MainActor, GlobalActor, nonisolated, reentrancy |
| `patterns.md` | AsyncSequence, AsyncStream, debounce, throttle, background processing |

---

## ios-testing

**Scope:** Unit tests, UI tests, mocking, test infrastructure.

**SKILL.md covers:**
- Framework choice table (Swift Testing vs XCTest)
- Test organization directory structure
- Swift Testing quick start
- UI testing with Page Object pattern
- Protocol-based mocking + URLProtocol
- SwiftData, Combine, async/await testing
- Migration table: XCTest → Swift Testing

**Reference files:**
| File | Content |
|------|---------|
| `swift-testing.md` | @Test, #expect, #require, @Suite, parameterized tests, traits, confirmation |
| `xctest.md` | Assertions, async testing, performance tests, XCTestExpectation |
| `ui-testing.md` | XCUIApplication, XCUIElement, Page Object, accessibility identifiers, launch args |
| `mocking.md` | Protocol mocks, URLProtocol, test doubles, dependency containers, snapshot testing |

---

## ios-accessibility

**Scope:** VoiceOver, Dynamic Type, WCAG compliance, inclusive design.

**SKILL.md covers:**
- 15 non-negotiable accessibility rules
- Quick checklist (14 items) before shipping
- SwiftUI modifier quick reference
- Common patterns (cards, toggles, lists, errors, responsive layout)

**Reference files:**
| File | Content |
|------|---------|
| `voiceover.md` | Labels, hints, values, traits, custom actions, rotors, focus management |
| `dynamic-type.md` | Text styles, @ScaledMetric, layout adaptation, large content viewer |
| `auditing.md` | Xcode Accessibility Inspector, XCTest performAccessibilityAudit, common mistakes |

---

## ios-performance

**Scope:** Memory, CPU, frame rate, launch time, battery, profiling.

**SKILL.md covers:**
- Performance targets table (launch time, FPS, memory, CPU, battery, network, app size)
- Quick diagnosis guide (11 symptoms → instruments → causes)
- Memory management reference (ARC, weak/unowned)
- SwiftUI performance patterns
- @Observable vs ObservableObject comparison
- Instruments workflow (6 steps)
- App launch optimization checklist
- 5 anti-patterns with BAD/GOOD code

**Reference files:**
| File | Content |
|------|---------|
| `memory.md` | ARC deep dive, retain cycles, value vs reference types, copy-on-write, autorelease |
| `swiftui-perf.md` | View identity, body evaluation, @Observable tracking, lazy containers, EquatableView |
| `instruments.md` | Time Profiler, Allocations, Leaks, Energy Log, Core Animation, SwiftUI instrument |
| `optimization.md` | Launch time, network, images, caching, build time, app size reduction |
