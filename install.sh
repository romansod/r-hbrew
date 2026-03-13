#!/usr/bin/env bash
# hbrew installer
# Usage: bash install.sh
# Or: curl -fsSL https://raw.githubusercontent.com/romansod/r-hbrew/main/install.sh | bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
INSTALL_BIN="$LOCAL_BIN/hbrew"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
ZSH_FILE="$ZSH_CUSTOM/hbrew.zsh"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

echo ""
echo -e "${BOLD}Installing hbrew...${NC}"
echo ""

# Copy script to ~/.local/bin (no sudo needed)
mkdir -p "$LOCAL_BIN"
cp "$SCRIPT_DIR/hbrew.sh" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"
echo -e "  ${GREEN}✓${NC} Installed to $INSTALL_BIN"

# Install oh-my-zsh if not already present
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo -e "  ${BOLD}Installing oh-my-zsh...${NC}"
  RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  echo -e "  ${GREEN}✓${NC} oh-my-zsh installed"
else
  echo -e "  ${GREEN}✓${NC} oh-my-zsh already installed"
fi

# Install zsh alias if oh-my-zsh is present
if [[ -d "$ZSH_CUSTOM" ]]; then
  cat > "$ZSH_FILE" <<'EOF'
# hbrew - Homebrew tool manager
# https://github.com/romansod/r-hbrew
alias hbrew="$HOME/.local/bin/hbrew"

# Set a default config repo so 'hbrew' works without flags.
# Uncomment and set your repo:
# export HBREW_REPO="owner/repo"
EOF
  echo -e "  ${GREEN}✓${NC} Shell alias written to $ZSH_FILE"
  echo -e "  ${YELLOW}→${NC}  Set a default repo in $ZSH_FILE by uncommenting HBREW_REPO"
else
  echo -e "  ${YELLOW}Note:${NC} oh-my-zsh not found — add this to your shell config:"
  echo "    alias hbrew="$HOME/.local/bin/hbrew""
fi

echo ""
echo -e "${BOLD}Done.${NC} Run ${BOLD}hbrew -h${NC} to get started."
echo ""
