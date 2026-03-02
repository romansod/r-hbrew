#!/usr/bin/env bash
# hbrew - Homebrew-based tool manager
# Reads a YAML config (local file or GitHub repo) and manages brew-based tools.
# https://github.com/romansod/r-hbrew

set -euo pipefail

VERSION="1.0.0"

# ── Colors ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hbrew"
DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hbrew/tools.yaml"

mkdir -p "$CACHE_DIR"

# ── Argument parsing ──────────────────────────────────────────────────────────
CONFIG_FILE=""
REPO=""
CONFIG_PATH=""
ACTION="status"

usage() {
  cat <<EOF

${BOLD}hbrew${NC} v${VERSION} — Homebrew tool manager

${BOLD}USAGE${NC}
  hbrew [OPTIONS]

${BOLD}OPTIONS${NC}
  --config FILE              Use a local config file
  --repo OWNER/REPO          Fetch config from a GitHub repo
  --config-path PATH         Path within the repo (default: tools.yaml or configs/tools.yaml)
  --install-all              Install all tools listed in config
  --update-all               Update all installed tools via brew upgrade
  --uninstall-all            Uninstall all (non-special) tools listed in config
  -h, --help                 Show this help

${BOLD}STATUS${NC} (default, no action flag)
  Shows each tool's installation status, version, and whether an update is
  available. If using --repo, also shows whether the remote config has changed.

${BOLD}CONFIG FORMAT${NC}
  tools:
    - name: atuin
      brew: atuin
      notes: "Run atuin import auto after install"

    - name: homebrew
      special: homebrew

${BOLD}EXAMPLES${NC}
  hbrew                                     # Show status using default config
  hbrew --config ~/my-tools.yaml            # Show status for custom config
  hbrew --repo romansod/hippocampus         # Show status from GitHub repo
  hbrew --repo romansod/hippocampus --install-all
  hbrew --update-all

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)        CONFIG_FILE="$2"; shift 2 ;;
    --repo)          REPO="$2"; shift 2 ;;
    --config-path)   CONFIG_PATH="$2"; shift 2 ;;
    --install-all)   ACTION="install"; shift ;;
    --update-all)    ACTION="update"; shift ;;
    --uninstall-all) ACTION="uninstall"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}" >&2; usage; exit 1 ;;
  esac
done

# ── Config resolution ─────────────────────────────────────────────────────────
CONFIG_UPDATED=false
CONFIG_SOURCE=""

resolve_config() {
  if [[ -n "$REPO" ]]; then
    local cached="$CACHE_DIR/tools.yaml"
    local hash_file="$CACHE_DIR/tools.yaml.sha"
    local prev_hash="" new_hash raw_url

    if [[ -n "$CONFIG_PATH" ]]; then
      raw_url="https://raw.githubusercontent.com/${REPO}/HEAD/${CONFIG_PATH}"
    else
      # Try tools.yaml at root, then configs/tools.yaml
      local root_url="https://raw.githubusercontent.com/${REPO}/HEAD/tools.yaml"
      local conf_url="https://raw.githubusercontent.com/${REPO}/HEAD/configs/tools.yaml"
      if curl -fsSL --head "$root_url" -o /dev/null 2>/dev/null; then
        raw_url="$root_url"
      else
        raw_url="$conf_url"
      fi
    fi

    # Try gh api first (supports private repos), fall back to curl for public
    local fetch_ok=false
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
      local api_path="${REPO}/contents/${raw_url##*/raw.githubusercontent.com/${REPO}/HEAD/}"
      # Use gh api to download file content (handles private repos)
      if gh api "repos/${REPO}/contents/${raw_url##*HEAD/}" --jq '.content' 2>/dev/null \
          | base64 -d > "$cached" 2>/dev/null && [[ -s "$cached" ]]; then
        fetch_ok=true
      fi
    fi
    if [[ "$fetch_ok" == false ]]; then
      if ! curl -fsSL "$raw_url" -o "$cached" 2>/dev/null; then
        echo -e "${RED}Error: could not fetch config from ${raw_url}${NC}" >&2
        echo -e "${DIM}Tip: for private repos, ensure 'gh auth login' has been run.${NC}" >&2
        exit 1
      fi
    fi

    [[ -f "$hash_file" ]] && prev_hash=$(cat "$hash_file")
    new_hash=$(shasum -a 256 "$cached" | awk '{print $1}')
    echo "$new_hash" > "$hash_file"

    if [[ -n "$prev_hash" && "$prev_hash" != "$new_hash" ]]; then
      CONFIG_UPDATED=true
    fi

    CONFIG_FILE="$cached"
    CONFIG_SOURCE="github:${REPO}"

  elif [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] || { echo -e "${RED}Error: config not found: $CONFIG_FILE${NC}" >&2; exit 1; }
    CONFIG_SOURCE="$CONFIG_FILE"

  else
    if [[ ! -f "$DEFAULT_CONFIG" ]]; then
      echo -e "${YELLOW}No config found.${NC}"
      echo -e "Create ${DEFAULT_CONFIG} or use ${BOLD}--config FILE${NC} / ${BOLD}--repo OWNER/REPO${NC}"
      exit 1
    fi
    CONFIG_FILE="$DEFAULT_CONFIG"
    CONFIG_SOURCE="$DEFAULT_CONFIG"
  fi
}

# ── YAML parser (Python stdlib only) ─────────────────────────────────────────
# Each tool is output as 4 lines: name, brew, special, notes — then a blank line.
# This avoids any bash field-splitting issues.
parse_config() {
  python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    text = f.read()

tools = []
current = None

for line in text.split('\n'):
    if re.match(r'\s*-\s+name:', line):
        if current is not None:
            tools.append(current)
        current = {'name': '', 'brew': '', 'special': '', 'notes': ''}
        current['name'] = re.split(r'name:\s*', line, 1)[1].strip()
    elif current is not None:
        for key in ('brew', 'special'):
            m = re.match(r'\s+' + key + r':\s*(.*)', line)
            if m:
                current[key] = m.group(1).strip()
        m = re.match(r'\s+notes:\s*(.*)', line)
        if m:
            val = m.group(1).strip()
            val = re.sub(r'^["\']|["\']$', '', val)
            current['notes'] = val

if current is not None:
    tools.append(current)

for t in tools:
    print(t['name'])
    print(t['brew'])
    print(t['special'])
    print(t['notes'])
    print('')  # blank line separator
PYEOF
}

# ── Read next tool from the config stream (4 fields + blank line) ─────────────
# Usage: read_tool name_var brew_var special_var notes_var < FD
# Returns 1 when no more tools
_read_tool() {
  local -n _n=$1 _b=$2 _s=$3 _nt=$4
  IFS= read -r _n || return 1
  IFS= read -r _b
  IFS= read -r _s
  IFS= read -r _nt
  IFS= read -r _blank  # consume blank separator
  [[ -z "$_n" ]] && return 1
  return 0
}

# ── Homebrew helpers ──────────────────────────────────────────────────────────
BREW_BIN=""

find_brew() {
  [[ -n "$BREW_BIN" ]] && return 0
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$p" ]]; then BREW_BIN="$p"; return 0; fi
  done
  if command -v brew &>/dev/null; then BREW_BIN=$(command -v brew); return 0; fi
  return 1
}

BREW_LIST_CACHE=""
BREW_OUTDATED_CACHE=""

load_brew_caches() {
  find_brew || return 0
  BREW_LIST_CACHE=$("$BREW_BIN" list --formula 2>/dev/null || true)
  BREW_OUTDATED_CACHE=$("$BREW_BIN" outdated --formula 2>/dev/null || true)
}

is_installed() {
  local name=$1 brew=$2 special=$3
  if [[ "$special" == "homebrew" ]]; then
    find_brew && return 0 || return 1
  fi
  [[ -n "$brew" ]] && echo "$BREW_LIST_CACHE" | grep -qx "$brew"
}

get_version() {
  local name=$1 brew=$2 special=$3
  if [[ "$special" == "homebrew" ]]; then
    find_brew && "$BREW_BIN" --version 2>/dev/null | awk 'NR==1{print $2}' || echo "?"
    return
  fi
  if [[ -n "$brew" ]]; then
    "$BREW_BIN" list --versions "$brew" 2>/dev/null | awk '{print $2}' || echo "?"
  fi
}

has_update() {
  local name=$1 brew=$2 special=$3
  [[ "$special" == "homebrew" ]] && return 1
  [[ -n "$brew" ]] && echo "$BREW_OUTDATED_CACHE" | grep -qx "$brew"
}

# ── Progress bar ──────────────────────────────────────────────────────────────
progress() {
  local cur=$1 total=$2 label=$3
  local width=32 filled empty bar
  filled=$(( width * cur / total ))
  empty=$(( width - filled ))
  bar=$(printf '%*s' "$filled" '' | tr ' ' '█')
  bar+=$(printf '%*s' "$empty" '' | tr ' ' '░')
  printf "\r  [%s] %d/%d  %-24s" "$bar" "$cur" "$total" "$label"
}

# ── Install homebrew ──────────────────────────────────────────────────────────
install_homebrew() {
  local log="$CACHE_DIR/homebrew_install.log"
  echo -e "  ${CYAN}→${NC} Installing Homebrew (this may take a few minutes)..."
  if NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >"$log" 2>&1; then
    echo -e "  ${GREEN}✓${NC} Homebrew installed"
    echo -e "  ${YELLOW}Note:${NC} Add brew to PATH: eval \"\$(brew shellenv)\" — then restart your shell"
    return 0
  else
    echo -e "  ${RED}✗${NC} Homebrew install failed — log: $log"
    return 1
  fi
}

# ── Print a note ──────────────────────────────────────────────────────────────
print_note() {
  local notes=$1
  [[ -z "$notes" ]] && return
  echo -e "    ${YELLOW}Note:${NC} $notes"
}

# ── Status ────────────────────────────────────────────────────────────────────
do_status() {
  echo ""
  echo -e "${BOLD}hbrew${NC} v${VERSION}"
  echo -e "${DIM}config: ${CONFIG_SOURCE}${NC}"
  [[ "$CONFIG_UPDATED" == true ]] && \
    echo -e "${YELLOW}⟳ Config updated from GitHub${NC}"
  echo ""

  load_brew_caches

  printf "  ${BOLD}%-16s %-18s %-12s %s${NC}\n" "TOOL" "STATUS" "VERSION" "UPDATE"
  printf "  %s\n" "$(printf '─%.0s' $(seq 1 58))"

  local any_notes=false

  while IFS= read -r name && IFS= read -r brew && IFS= read -r special && IFS= read -r notes && IFS= read -r _blank; do
    [[ -z "$name" ]] && continue

    printf "  ${BOLD}%-16s${NC}" "$name"

    if is_installed "$name" "$brew" "$special"; then
      local ver
      ver=$(get_version "$name" "$brew" "$special")
      printf "${GREEN}%-18s${NC}" "✓ installed"
      printf "%-12s" "$ver"
      if [[ "$special" != "homebrew" ]] && has_update "$name" "$brew" "$special"; then
        printf "${YELLOW}update available${NC}"
      else
        printf "${GREEN}up to date${NC}"
      fi
      echo ""
      [[ -n "$notes" ]] && any_notes=true
    else
      printf "${RED}%-18s${NC}" "✗ not installed"
      printf "%-12s" "-"
      printf "${DIM}-%s${NC}" ""
      echo ""
    fi
  done < <(parse_config)

  echo ""
  if [[ "$any_notes" == true ]]; then
    echo -e "${DIM}Run --install-all to install missing tools. Notes will be shown after install.${NC}"
  fi
  echo -e "${DIM}Flags: --install-all  --update-all  --uninstall-all  -h${NC}"
  echo ""
}

# ── Install all ───────────────────────────────────────────────────────────────
do_install() {
  # First pass: collect all tools
  local -a names brews specials notes_arr
  while IFS= read -r name && IFS= read -r brew && IFS= read -r special && IFS= read -r notes && IFS= read -r _blank; do
    [[ -z "$name" ]] && continue
    names+=("$name"); brews+=("$brew"); specials+=("$special"); notes_arr+=("$notes")
  done < <(parse_config)

  local total=${#names[@]}
  echo ""
  echo -e "${BOLD}Installing $total tools...${NC}"
  echo ""

  load_brew_caches

  local idx=0 installed=0 skipped=0 failed=0

  for i in "${!names[@]}"; do
    local name="${names[$i]}" brew="${brews[$i]}" special="${specials[$i]}" notes="${notes_arr[$i]}"
    (( idx++ )) || true
    progress "$idx" "$total" "$name"
    echo ""

    if is_installed "$name" "$brew" "$special"; then
      echo -e "  ${DIM}↷ $name already installed${NC}"
      (( skipped++ )) || true
      continue
    fi

    local ok=true
    if [[ "$special" == "homebrew" ]]; then
      install_homebrew || ok=false
      BREW_BIN=""
      find_brew || true
    elif [[ -n "$brew" ]]; then
      find_brew || { echo -e "  ${RED}✗ brew not found — install homebrew first${NC}"; ok=false; }
      if [[ "$ok" == true ]]; then
        local log="$CACHE_DIR/${name}_install.log"
        if "$BREW_BIN" install "$brew" >"$log" 2>&1; then
          echo -e "  ${GREEN}✓${NC} $name installed"
          print_note "$notes"
          (( installed++ )) || true
        else
          echo -e "  ${RED}✗${NC} $name failed — log: $log"
          tail -5 "$log" | sed 's/^/    /' >&2
          (( failed++ )) || true
        fi
      fi
    else
      echo -e "  ${YELLOW}?${NC} $name: no install method defined"
    fi
  done

  echo ""
  echo -e "${BOLD}Done.${NC} installed=${GREEN}${installed}${NC}  skipped=${DIM}${skipped}${NC}  failed=${RED}${failed}${NC}"
  echo ""
}

# ── Update all ────────────────────────────────────────────────────────────────
do_update() {
  find_brew || { echo -e "${RED}Error: brew not found${NC}" >&2; exit 1; }

  local -a names brews specials
  while IFS= read -r name && IFS= read -r brew && IFS= read -r special && IFS= read -r notes && IFS= read -r _blank; do
    [[ -z "$name" ]] && continue
    names+=("$name"); brews+=("$brew"); specials+=("$special")
  done < <(parse_config)

  local total=${#names[@]}
  echo ""
  echo -e "${BOLD}Updating $total tools...${NC}"
  echo -e "${DIM}(Running brew update first)${NC}"
  echo ""

  "$BREW_BIN" update --quiet 2>/dev/null || true
  load_brew_caches

  local idx=0 updated=0 skipped=0 failed=0

  for i in "${!names[@]}"; do
    local name="${names[$i]}" brew="${brews[$i]}" special="${specials[$i]}"
    (( idx++ )) || true
    progress "$idx" "$total" "$name"
    echo ""

    if [[ "$special" == "homebrew" ]]; then
      echo -e "  ${DIM}↷ homebrew: use 'brew update' to update homebrew itself${NC}"
      (( skipped++ )) || true
      continue
    fi

    if ! is_installed "$name" "$brew" "$special"; then
      echo -e "  ${DIM}↷ $name not installed, skipping${NC}"
      (( skipped++ )) || true
      continue
    fi

    if ! has_update "$name" "$brew" "$special"; then
      echo -e "  ${GREEN}✓${NC} $name up to date"
      (( skipped++ )) || true
      continue
    fi

    local log="$CACHE_DIR/${name}_update.log"
    if "$BREW_BIN" upgrade "$brew" >"$log" 2>&1; then
      local ver
      ver=$("$BREW_BIN" list --versions "$brew" 2>/dev/null | awk '{print $2}' || echo "?")
      echo -e "  ${GREEN}✓${NC} $name updated → $ver"
      (( updated++ )) || true
    else
      echo -e "  ${RED}✗${NC} $name update failed — log: $log"
      tail -5 "$log" | sed 's/^/    /' >&2
      (( failed++ )) || true
    fi
  done

  echo ""
  echo -e "${BOLD}Done.${NC} updated=${GREEN}${updated}${NC}  already-current=${DIM}${skipped}${NC}  failed=${RED}${failed}${NC}"
  echo ""
}

# ── Uninstall all ─────────────────────────────────────────────────────────────
do_uninstall() {
  find_brew || { echo -e "${RED}Error: brew not found${NC}" >&2; exit 1; }

  local -a names brews specials
  while IFS= read -r name && IFS= read -r brew && IFS= read -r special && IFS= read -r notes && IFS= read -r _blank; do
    [[ -z "$name" ]] && continue
    [[ "$special" == "homebrew" ]] && continue  # skip — uninstall manually
    names+=("$name"); brews+=("$brew"); specials+=("$special")
  done < <(parse_config)

  local total=${#names[@]}
  echo ""
  echo -e "${BOLD}Uninstalling $total tools...${NC}"
  echo -e "${YELLOW}Note: homebrew itself is skipped (uninstall manually if needed)${NC}"
  echo ""

  load_brew_caches

  local idx=0 removed=0 skipped=0 failed=0

  for i in "${!names[@]}"; do
    local name="${names[$i]}" brew="${brews[$i]}" special="${specials[$i]}"
    (( idx++ )) || true
    progress "$idx" "$total" "$name"
    echo ""

    if ! is_installed "$name" "$brew" "$special"; then
      echo -e "  ${DIM}↷ $name not installed, skipping${NC}"
      (( skipped++ )) || true
      continue
    fi

    local log="$CACHE_DIR/${name}_uninstall.log"
    if "$BREW_BIN" uninstall "$brew" >"$log" 2>&1; then
      echo -e "  ${GREEN}✓${NC} $name uninstalled"
      (( removed++ )) || true
    else
      echo -e "  ${RED}✗${NC} $name uninstall failed — log: $log"
      tail -5 "$log" | sed 's/^/    /' >&2
      (( failed++ )) || true
    fi
  done

  echo ""
  echo -e "${BOLD}Done.${NC} removed=${GREEN}${removed}${NC}  skipped=${DIM}${skipped}${NC}  failed=${RED}${failed}${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
resolve_config

case "$ACTION" in
  status)    do_status ;;
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
esac
