# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-03-16

### Added

- **ios-swiftui** — Layout system, state management (@Observable, @State, @Binding, @Environment), navigation (NavigationStack, NavigationSplitView), animations (springs, transitions, keyframes, PhaseAnimator), ViewModifiers, UIKit interop. 5 reference files.
- **ios-architecture** — MVVM with @Observable, Clean Architecture, The Composable Architecture (TCA), modular architecture with SPM, Repository pattern, Coordinator/Router, Dependency Injection. 5 reference files.
- **ios-networking** — URLSession async/await, type-safe API client, Codable, error handling with retry/backoff, OAuth2, WebSocket, caching, certificate pinning. 4 reference files.
- **ios-data** — SwiftData (@Model, @Query, #Predicate), Core Data, UserDefaults, FileManager, Keychain, iCloud sync, migrations. 3 reference files.
- **ios-security** — Keychain Services, Face ID/Touch ID, CryptoKit encryption, Sign in with Apple, OAuth2, certificate pinning, privacy manifests, data protection. 5 reference files.
- **ios-concurrency** — async/await, structured concurrency (Task, TaskGroup), actors, @MainActor, Sendable, AsyncSequence/AsyncStream, Swift 6 strict concurrency. 3 reference files.
- **ios-testing** — Swift Testing (@Test, #expect, @Suite), XCTest, UI Testing (Page Object pattern), snapshot testing, protocol-based mocking, URLProtocol, SwiftData/Combine/async testing. 4 reference files.
- **ios-accessibility** — VoiceOver (labels, hints, traits, actions, focus), Dynamic Type (@ScaledMetric, layout adaptation), WCAG compliance, accessibility auditing. 3 reference files.
- **ios-performance** — Memory management (ARC, retain cycles), SwiftUI performance (@Observable vs ObservableObject, lazy containers), Instruments profiling, app launch optimization, battery/energy. 4 reference files.
- Cross-agent compatibility: Claude Code, Codex, Gemini CLI
- `AGENTS.md` for Codex/Gemini auto-discovery
- `install.sh` one-command installer
- Documentation: customization guide, compatibility notes, skill overview
