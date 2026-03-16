# Compatibility Guide

How to use iOS Agent Skills with different AI coding agents.

## Claude Code (Full Support)

Claude Code natively supports the `SKILL.md` format with reference file routing.

### Installation

```bash
# Option 1: Installer script
git clone https://github.com/koshkinvv/ios-agent-skills.git
cd ios-agent-skills && ./install.sh

# Option 2: Manual copy
cp -r skills/ios-* ~/.claude/skills/

# Option 3: Symlink (always up to date)
ln -s "$(pwd)/skills/ios-swiftui" ~/.claude/skills/ios-swiftui
# repeat for each skill
```

### How It Works

- Skills are loaded based on keyword triggers in the `description` field
- When a skill activates, Claude reads the `SKILL.md`
- For deeper guidance, Claude reads the appropriate reference file based on the routing table
- Multiple skills can activate simultaneously (e.g., ios-swiftui + ios-testing when writing SwiftUI tests)

---

## OpenAI Codex (Full Support)

Codex reads `AGENTS.md` from the repo root and `SKILL.md` files from `.codex/skills/`.

### Installation

```bash
# Option 1: Copy to Codex skills directory
mkdir -p .codex/skills
cp -r skills/ios-* .codex/skills/

# Option 2: Use AGENTS.md (already included in repo root)
# Just clone the repo — Codex will read AGENTS.md automatically
```

---

## Google Gemini CLI (Full Support)

Gemini CLI reads `AGENTS.md` and supports the `SKILL.md` format.

### Installation

```bash
mkdir -p .gemini/skills
cp -r skills/ios-* .gemini/skills/
```

---

## Cursor (Partial Support)

Cursor uses `.cursorrules` files — a single flat file, no reference routing.

### Installation

```bash
# Append the SKILL.md content of skills you want
cat skills/ios-swiftui/SKILL.md >> .cursorrules
cat skills/ios-architecture/SKILL.md >> .cursorrules
# etc.
```

### Limitations

- No automatic reference file routing — all content must be in one file
- Context window may limit how many skills you can include
- Recommended: pick 2-3 most relevant skills for your current project

---

## Windsurf (Partial Support)

```bash
cat skills/ios-swiftui/SKILL.md >> .windsurfrules
```

Same limitations as Cursor.

---

## GitHub Copilot (Partial Support)

```bash
mkdir -p .github
cat skills/ios-swiftui/SKILL.md >> .github/copilot-instructions.md
```

Copilot's instruction file has a smaller effective context — pick 1-2 skills.

---

## Custom / Other Agents

If your agent reads markdown instruction files from a configurable path:

1. Point it to the `skills/` directory
2. Or concatenate the SKILL.md files you need into your agent's instruction format

The SKILL.md format is standard YAML frontmatter + markdown. Any agent that reads markdown instructions can use these skills.
