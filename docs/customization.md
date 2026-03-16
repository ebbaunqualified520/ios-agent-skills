# Customization Guide

How to adapt iOS Agent Skills to your project's specific needs.

## Adjusting iOS Version Target

By default, skills target **iOS 17+** with modern APIs. To support older versions:

### iOS 16+ (drop @Observable)

In `ios-swiftui/SKILL.md`, update the state management decision table to prefer:
- `@StateObject` + `ObservableObject` instead of `@State` + `@Observable`
- `@ObservedObject` instead of auto-tracked observation
- `@EnvironmentObject` instead of `@Environment` with custom keys

In `ios-data/SKILL.md`, switch default from SwiftData to Core Data.

### iOS 15+ (drop NavigationStack)

In `ios-swiftui/SKILL.md`, update navigation to use `NavigationView` with `isActive` bindings.

## Adding Project Conventions

Append your team's conventions to the relevant SKILL.md:

```markdown
## Project Conventions

- All views must use the `AppTheme` design system
- ViewModels must extend `BaseViewModel`
- Network calls go through `AppAPIClient` (not raw URLSession)
- Use `AppError` as the unified error type
```

## Cherry-Picking Skills

You don't need all 9. Common combinations:

| Project Type | Recommended Skills |
|-------------|-------------------|
| Small UI-focused app | ios-swiftui, ios-data |
| API-heavy app | ios-swiftui, ios-networking, ios-architecture |
| Enterprise app | All except ios-performance (add later) |
| TCA project | ios-architecture, ios-testing, ios-concurrency |
| Accessibility audit | ios-accessibility, ios-swiftui |

## Creating New Skills

Follow the structure in [CONTRIBUTING.md](../CONTRIBUTING.md):

```
skills/ios-<your-topic>/
├── SKILL.md
└── references/
    └── <topic>.md
```

## Extending Reference Files

Reference files are where the deep content lives. To add your team's patterns:

1. Open the relevant reference file (e.g., `skills/ios-networking/references/api-client.md`)
2. Add a section at the end: `## Project-Specific Patterns`
3. Include your team's API client setup, custom interceptors, etc.

This way, when the agent reads the reference, it gets both the general best practices and your project's specifics.
