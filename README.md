<p align="center">
  <h1 align="center">iOS Agent Skills</h1>
  <p align="center">
    <strong>9 expert-level iOS development skills for AI coding agents</strong>
  </p>
  <p align="center">
    From SwiftUI to security — one install, full coverage.
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
    <a href="#compatibility"><img src="https://img.shields.io/badge/Claude_Code-compatible-blueviolet" alt="Claude Code"></a>
    <a href="#compatibility"><img src="https://img.shields.io/badge/Codex-compatible-green" alt="Codex"></a>
    <a href="#compatibility"><img src="https://img.shields.io/badge/Gemini_CLI-compatible-orange" alt="Gemini CLI"></a>
    <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple" alt="iOS 17+">
    <img src="https://img.shields.io/badge/Swift-5.9%2B-FA7343?logo=swift&logoColor=white" alt="Swift 5.9+">
  </p>
</p>

---

## Why This?

Most iOS agent skills give you **one topic in one file**. This collection gives you **9 interconnected skills** with **36 deep-dive reference files** — the equivalent of a senior iOS engineer's knowledge base, structured for AI agents.

| | ios-agent-skills | Single-topic skills | .cursorrules |
|---|:---:|:---:|:---:|
| Topics covered | **9** | 1 | 1 |
| Reference depth per topic | 3-7 files | 1 file | 1 file |
| Total content | ~23,500 lines | ~300 lines | ~100 lines |
| Decision tables | Yes | Rare | No |
| Anti-patterns with fixes | Yes | Sometimes | No |
| Cross-referenced | Yes | No | No |
| iOS version matrix | Yes | No | No |

## Skills

| Skill | What It Covers | Files |
|-------|---------------|-------|
| **[ios-swiftui](skills/ios-swiftui/)** | Layout, state management, navigation, animations, ViewModifiers, UIKit interop | 6 |
| **[ios-architecture](skills/ios-architecture/)** | MVVM, Clean Architecture, TCA, SPM modules, Repository pattern, DI | 6 |
| **[ios-networking](skills/ios-networking/)** | URLSession async/await, API client design, Codable, retry/backoff, WebSocket | 5 |
| **[ios-data](skills/ios-data/)** | SwiftData, Core Data, UserDefaults, FileManager, Keychain, iCloud sync | 4 |
| **[ios-security](skills/ios-security/)** | Keychain Services, Face ID/Touch ID, CryptoKit, Sign in with Apple, ATS | 6 |
| **[ios-concurrency](skills/ios-concurrency/)** | async/await, actors, Sendable, TaskGroup, Swift 6 strict concurrency | 4 |
| **[ios-testing](skills/ios-testing/)** | Swift Testing, XCTest, UI tests, protocol mocking, URLProtocol, snapshot tests | 5 |
| **[ios-accessibility](skills/ios-accessibility/)** | VoiceOver, Dynamic Type, WCAG compliance, accessibility audit | 4 |
| **[ios-performance](skills/ios-performance/)** | Memory/ARC, Instruments profiling, SwiftUI perf, launch time, battery | 5 |

**Total: 9 skills, 45 files, ~23,500 lines of production-tested patterns and guidance.**

## Quick Start

### Claude Code

```bash
# Install all skills (recommended)
git clone https://github.com/koshkinvv/ios-agent-skills.git
cd ios-agent-skills && ./install.sh

# Or install manually
git clone https://github.com/koshkinvv/ios-agent-skills.git ~/.claude/skills/ios-agent-skills
```

After installation, skills activate automatically when you work on iOS code. Ask Claude Code to build a SwiftUI view, architect a feature module, write tests, or optimize performance — the relevant skill kicks in.

### Cherry-Pick Specific Skills

```bash
# Only install what you need
cp -r skills/ios-swiftui ~/.claude/skills/
cp -r skills/ios-testing ~/.claude/skills/
```

### Other Agents

See the [Compatibility](#compatibility) section below.

## How It Works

Each skill follows a consistent structure:

```
skills/ios-swiftui/
├── SKILL.md              # Core rules, decision tables, quick patterns
└── references/
    ├── layout.md         # Deep dive: stacks, grids, scroll views
    ├── state.md          # Deep dive: @State, @Observable, @Environment
    ├── navigation.md     # Deep dive: NavigationStack, sheets, deep linking
    ├── animation.md      # Deep dive: springs, transitions, keyframes
    └── patterns.md       # Deep dive: ViewModifier, lifecycle, UIKit interop
```

**SKILL.md** is loaded when the skill triggers. It contains:
- **Core Rules** — 10-15 non-negotiable best practices
- **Decision Tables** — "what to use when" guides
- **Quick Patterns** — copy-paste production code
- **Anti-Patterns** — common mistakes with fixes
- **Reference Routing** — which reference file to read for each task

**Reference files** provide deep, topic-specific guidance with extensive code examples. The agent reads them on demand based on the routing table.

## What's Inside

### Decision Tables

Every skill includes decision tables that eliminate guesswork:

```
State Management — What to Use When (from ios-swiftui)

| Scenario                          | iOS 17+                  | Pre-iOS 17        |
|-----------------------------------|--------------------------|-------------------|
| Simple value owned by view        | @State                   | @State            |
| Reference-type model owned by view| @State + @Observable     | @StateObject      |
| Reference-type model passed in    | just pass it             | @ObservedObject   |
| Shared model via environment      | @Environment + custom key| @EnvironmentObject|
```

### Architecture Selection

```
From ios-architecture:

| Project Size                    | Recommended              |
|---------------------------------|--------------------------|
| Small (1 dev, <10 screens)      | MVVM + @Observable       |
| Medium (2-4 devs, 10-30 screens)| MVVM + Clean layers      |
| Large (5+ devs, 30+ screens)    | Clean + SPM modules / TCA|
```

### Anti-Patterns

Every skill documents what NOT to do and why:

```
From ios-concurrency:

BAD:  Task { @MainActor in self.data = await fetch() }
GOOD: @MainActor func updateUI() { ... }  // isolate at declaration, not call site
```

## Compatibility

These skills use the standard `SKILL.md` format (YAML frontmatter + markdown) established by [Anthropic](https://github.com/anthropics/skills).

| Agent | How to Install | Status |
|-------|---------------|--------|
| **Claude Code** | `./install.sh` or copy to `~/.claude/skills/` | Full support |
| **OpenAI Codex** | Copy skills to `.codex/skills/` or use `AGENTS.md` | Full support |
| **Gemini CLI** | Copy skills to `.gemini/skills/` or use `AGENTS.md` | Full support |
| **Cursor** | Append SKILL.md content to `.cursorrules` | Partial (no reference routing) |
| **Windsurf** | Copy to `.windsurfrules` | Partial |
| **GitHub Copilot** | Use `.github/copilot-instructions.md` | Partial |

An `AGENTS.md` file is included in the repo root for agents that read it automatically (Codex, Gemini CLI).

## Customization

These skills target **iOS 17+** with modern APIs (@Observable, Swift Testing, SwiftData, async/await). To customize:

- **Support older iOS versions**: Adjust decision tables to prefer pre-iOS 17 patterns
- **Use specific architecture**: Keep only the skills relevant to your stack
- **Add project conventions**: Extend SKILL.md files with your team's naming conventions, folder structure, or code style

See [docs/customization.md](docs/customization.md) for detailed guidance.

## Tech Stack Coverage

| Technology | Version | Covered In |
|-----------|---------|-----------|
| SwiftUI | iOS 17-18 | ios-swiftui |
| @Observable | iOS 17+ | ios-swiftui, ios-architecture |
| NavigationStack | iOS 16+ | ios-swiftui |
| Swift Testing | Xcode 16+ | ios-testing |
| XCTest / XCUITest | All | ios-testing |
| SwiftData | iOS 17+ | ios-data |
| Core Data | All | ios-data |
| async/await | iOS 15+ | ios-concurrency, ios-networking |
| Actors / Sendable | iOS 15+ | ios-concurrency |
| Swift 6 strict concurrency | Swift 6 | ios-concurrency |
| URLSession async | iOS 15+ | ios-networking |
| TCA (Composable Architecture) | 1.x | ios-architecture |
| SPM modules | All | ios-architecture |
| Keychain Services | All | ios-security, ios-data |
| CryptoKit | iOS 13+ | ios-security |
| Face ID / Touch ID | iOS 11+ | ios-security |
| VoiceOver | All | ios-accessibility |
| Dynamic Type | All | ios-accessibility |
| Instruments | All | ios-performance |

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Areas where help is especially appreciated:
- Adding visionOS, watchOS, or macOS-specific patterns
- Updating for new iOS/Xcode releases
- Adding more code examples to reference files
- Translations of documentation

## License

[MIT](LICENSE) — use freely in personal and commercial projects.

## Acknowledgments

Built with patterns and best practices from:
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [Swift Evolution Proposals](https://github.com/swiftlang/swift-evolution)
- [Point-Free](https://www.pointfree.co/) (TCA patterns)
- [Hacking with Swift](https://www.hackingwithswift.com/) (SwiftUI patterns)
- The iOS developer community
