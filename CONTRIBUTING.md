# Contributing to iOS Agent Skills

Thank you for your interest in contributing! This project aims to be the most comprehensive and practical iOS skill collection for AI coding agents.

## How to Contribute

### Reporting Issues

- **Incorrect patterns**: If a code example uses deprecated APIs or has bugs, open an issue with the correct approach.
- **Missing coverage**: If an important iOS topic isn't covered, suggest it as a feature request.
- **Compatibility issues**: If a skill doesn't work correctly with a specific agent (Claude Code, Codex, etc.), let us know.

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b add-visionos-patterns`)
3. Make your changes
4. Test with at least one AI coding agent
5. Submit a pull request

### What We're Looking For

**High priority:**
- Updates for new iOS/Xcode releases
- visionOS, watchOS, macOS-specific patterns
- Additional code examples in reference files
- Bug fixes in existing patterns

**Also welcome:**
- Improved decision tables
- New anti-patterns with fixes
- Better explanations of complex topics
- Performance benchmarks

### Skill Structure

Every skill must follow this structure:

```
skills/ios-<topic>/
├── SKILL.md              # Required: core rules + decision tables + patterns
└── references/           # Required: 3+ deep-dive reference files
    └── <topic>.md
```

### SKILL.md Format

```markdown
---
name: ios-<topic>
description: >
  One paragraph describing what the skill covers and when it triggers.
  Include trigger keywords at the end.
---

# iOS <Topic> Skill

## Core Rules
(10-15 numbered rules)

## Decision Tables
(At least one "what to use when" table)

## Quick Patterns
(2-4 copy-paste code examples)

## Anti-Patterns
(5-10 common mistakes with fixes)

## References
(Links to reference files)
```

### Writing Guidelines

- **Be practical, not theoretical.** Every rule should have a code example.
- **Decision tables over prose.** A table that says "use X when Y" is more useful than a paragraph explaining trade-offs.
- **Modern APIs first.** Target iOS 17+ as the baseline. Include pre-iOS 17 alternatives in decision tables where relevant.
- **Anti-patterns are as valuable as patterns.** Show what NOT to do and explain why.
- **Keep it concise.** Agent context windows are limited. Every line should earn its place.

### Code Style

- Swift code examples must compile (or be obviously pseudocode)
- Use meaningful variable names, not `foo`/`bar`
- Include comments only where the intent isn't obvious
- Use `// ...` to indicate omitted code
- Target iOS 17+ / Swift 5.9+ unless showing backward compatibility

### Testing Your Changes

Before submitting, verify that:
1. Your SKILL.md has valid YAML frontmatter
2. All reference files are linked from SKILL.md
3. Code examples are syntactically correct Swift
4. The skill triggers on the keywords listed in its description

## Code of Conduct

Be respectful, constructive, and focused on making iOS development better for everyone.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
