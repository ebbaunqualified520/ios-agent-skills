#!/usr/bin/env bash
set -euo pipefail

# iOS Agent Skills — Installer
# Installs all 9 iOS skills into your AI coding agent's skills directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}iOS Agent Skills${NC} — Installer"
echo "================================"
echo ""

# Detect agent
AGENT=""
TARGET_DIR=""

if [[ "${1:-}" == "--codex" ]]; then
    AGENT="Codex"
    TARGET_DIR=".codex/skills"
elif [[ "${1:-}" == "--gemini" ]]; then
    AGENT="Gemini CLI"
    TARGET_DIR=".gemini/skills"
elif [[ "${1:-}" == "--target" && -n "${2:-}" ]]; then
    AGENT="Custom"
    TARGET_DIR="$2"
else
    AGENT="Claude Code"
    TARGET_DIR="$HOME/.claude/skills"
fi

echo -e "Agent:  ${GREEN}$AGENT${NC}"
echo -e "Target: ${GREEN}$TARGET_DIR${NC}"
echo ""

# Check source
if [[ ! -d "$SKILLS_SOURCE" ]]; then
    echo -e "${RED}Error:${NC} skills/ directory not found at $SKILLS_SOURCE"
    echo "Make sure you run this script from the ios-agent-skills repository root."
    exit 1
fi

# Create target if needed
mkdir -p "$TARGET_DIR"

# Count skills
SKILL_COUNT=$(find "$SKILLS_SOURCE" -maxdepth 1 -type d -name "ios-*" | wc -l | tr -d ' ')

echo "Installing $SKILL_COUNT skills..."
echo ""

# Install each skill
INSTALLED=0
for skill_dir in "$SKILLS_SOURCE"/ios-*; do
    skill_name=$(basename "$skill_dir")

    if [[ -d "$TARGET_DIR/$skill_name" ]]; then
        echo -e "  ${YELLOW}~${NC} $skill_name (updating)"
        rm -rf "$TARGET_DIR/$skill_name"
    else
        echo -e "  ${GREEN}+${NC} $skill_name"
    fi

    cp -r "$skill_dir" "$TARGET_DIR/$skill_name"
    INSTALLED=$((INSTALLED + 1))
done

echo ""
echo -e "${GREEN}Done!${NC} Installed $INSTALLED skills to $TARGET_DIR"
echo ""

# Count files
FILE_COUNT=$(find "$TARGET_DIR"/ios-* -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
echo "Total files: $FILE_COUNT"
echo ""

echo "Skills will activate automatically when you work on iOS code."
echo "Try asking your agent to: \"Build a SwiftUI login screen with @Observable\""
echo ""
