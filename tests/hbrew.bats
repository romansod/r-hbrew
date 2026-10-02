#!/usr/bin/env bats
# Tests for hbrew.sh. Nothing here touches the real brew, the real gh session,
# the real home directory or the network: brew is stubbed through HBREW_BREW,
# curl and gh through PATH, and the cache and config directories live under
# the test's tmp dir.
#
# ASSERTIONS: use `[ ... ]` or the helpers below, never `[[ ... ]]` and never a
# bare `! command`. bats runs under /bin/bash 3.2 on macOS, where a false
# `[[ ]]` that is not the last command of a test does not fail it, and neither
# does a `!`-negated command that is not the last one, on any bash. A helper
# that returns non-zero always does.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HBREW="$REPO_ROOT/hbrew.sh"
  EXAMPLE="$REPO_ROOT/tools.example.yaml"

  export STUB_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUB_STATE"
  : > "$STUB_STATE/calls"
  : > "$STUB_STATE/curl-calls"
  : > "$STUB_STATE/gh-calls"

  export HBREW_BREW="$BATS_TEST_DIRNAME/stubs/brew"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  unset HBREW_REPO GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR
}

# Run hbrew and strip colour and progress-bar control sequences from $output.
hbrew() {
  run bash "$HBREW" "$@"
  output="$(printf '%s' "$output" | sed -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | tr '\r' '\n')"
}

installed() { printf '%s\n' "$@" > "$STUB_STATE/installed"; }
outdated() { printf '%s\n' "$@" > "$STUB_STATE/outdated"; }
remote_config() { cp "$1" "$STUB_STATE/remote-config"; }

# ── assertion helpers: each returns non-zero, with a reason, when it fails ────

exits() {
  [ "$status" -eq "$1" ] && return 0
  echo "expected exit status $1, got $status"
  echo "--- output:"
  echo "$output"
  return 1
}

has() {
  case "$output" in *"$1"*) return 0 ;; esac
  echo "expected output to contain: $1"
  echo "--- output:"
  echo "$output"
  return 1
}

lacks() {
  case "$output" in *"$1"*) ;; *) return 0 ;; esac
  echo "expected output NOT to contain: $1"
  echo "--- output:"
  echo "$output"
  return 1
}

# The table row for one tool, squeezed to single spaces.
row() { printf '%s\n' "$output" | grep -E "^  $1 " | tr -s ' '; }

row_is() {
  local got
  got="$(row "$1")"
  [ "$got" = "$2" ] && return 0
  echo "expected row: '$2'"
  echo "     got row: '$got'"
  return 1
}

row_starts() {
  local got
  got="$(row "$1")"
  case "$got" in "$2"*) return 0 ;; esac
  echo "expected row to start: '$2'"
  echo "              got row: '$got'"
  return 1
}

# file_has <state-file> <fixed string> / file_lacks <state-file> <ERE>
file_has() {
  grep -qF -- "$2" "$STUB_STATE/$1" && return 0
  echo "expected $1 to contain: $2"
  echo "--- $1:"
  cat "$STUB_STATE/$1"
  return 1
}

file_lacks() {
  if grep -qE -- "$2" "$STUB_STATE/$1"; then
    echo "expected $1 NOT to match: $2"
    echo "--- $1:"
    cat "$STUB_STATE/$1"
    return 1
  fi
}

brew_called() {
  grep -qx -- "$1" "$STUB_STATE/calls" && return 0
  echo "expected brew call: $1"
  echo "--- calls:"
  cat "$STUB_STATE/calls"
  return 1
}

brew_call_count() { # brew_call_count <subcommand> <n>
  local n
  n="$(grep -c "^$1 " "$STUB_STATE/calls" || true)"
  [ "$n" -eq "$2" ] && return 0
  echo "expected $2 '$1' call(s), got $n"
  cat "$STUB_STATE/calls"
  return 1
}

no_file_content() { # the state file is empty
  [ ! -s "$STUB_STATE/$1" ] && return 0
  echo "expected $1 to be empty:"
  cat "$STUB_STATE/$1"
  return 1
}

# A PATH that has everything hbrew needs except python3. The stubs stay first.
path_without_python3() {
  local dir="$BATS_TEST_TMPDIR/nopython" tool
  mkdir -p "$dir"
  for tool in bash env cat mkdir grep sed awk tr seq tail head dirname shasum mktemp rm cp; do
    ln -sf "$(command -v "$tool")" "$dir/$tool"
  done
  printf '%s:%s' "$BATS_TEST_DIRNAME/stubs" "$dir"
}

# ── status ────────────────────────────────────────────────────────────────────

@test "status lists one row per tool in the example config" {
  hbrew --config "$EXAMPLE"
  exits 0
  local tool
  for tool in homebrew atuin broot btop gh starship tmux tree; do
    row_starts "$tool" " $tool "
  done
  [ "$(printf '%s\n' "$output" | grep -cE '(✓ installed|✗ not installed)')" -eq 8 ]
}

@test "status tells installed, outdated and missing tools apart" {
  installed atuin gh
  outdated gh
  hbrew --config "$EXAMPLE"
  exits 0
  row_is atuin " atuin ✓ installed 1.2.3 up to date"
  row_is gh " gh ✓ installed 1.2.3 update available"
  row_starts btop " btop ✗ not installed"
}

@test "status reports homebrew itself with brew's own version" {
  hbrew --config "$EXAMPLE"
  exits 0
  row_is homebrew " homebrew ✓ installed 9.9.9 up to date"
}

@test "status changes no tool" {
  installed atuin
  outdated atuin
  hbrew --config "$EXAMPLE"
  exits 0
  file_lacks calls '^(install|upgrade|uninstall|update)( |$)'
}

@test "status names the config it read" {
  hbrew --config "$EXAMPLE"
  exits 0
  has "config: $EXAMPLE"
}

# ── HBREW_BREW ────────────────────────────────────────────────────────────────

@test "an HBREW_BREW that does not exist is an error before any action" {
  HBREW_BREW="$BATS_TEST_TMPDIR/no-such-brew" hbrew --config "$EXAMPLE" --install-all
  exits 1
  has "HBREW_BREW is not an executable file"
  lacks "Installing"
  no_file_content calls
  no_file_content curl-calls
}

@test "an HBREW_BREW that is a file without the executable bit is an error" {
  local plain="$BATS_TEST_TMPDIR/not-executable"
  : > "$plain"
  HBREW_BREW="$plain" hbrew --config "$EXAMPLE"
  exits 1
  has "HBREW_BREW is not an executable file"
  lacks "TOOL"
}

@test "an HBREW_BREW that is a directory is an error" {
  HBREW_BREW="$BATS_TEST_TMPDIR" hbrew --config "$EXAMPLE"
  exits 1
  has "HBREW_BREW is not an executable file"
  lacks "TOOL"
}

# ── config resolution ─────────────────────────────────────────────────────────

@test "an explicit --config wins over HBREW_REPO and makes no network call" {
  HBREW_REPO="nobody/nothing" hbrew --config "$EXAMPLE"
  exits 0
  has "config: $EXAMPLE"
  no_file_content curl-calls
  no_file_content gh-calls
}

@test "HBREW_REPO alone selects the repo config" {
  HBREW_REPO="nobody/nothing" hbrew
  exits 1
  has "could not fetch config"
  file_has curl-calls "nobody/nothing"
}

@test "--repo given with --config keeps the repo" {
  hbrew --config "$EXAMPLE" --repo nobody/nothing
  exits 1
  has "could not fetch config"
  file_has curl-calls "nobody/nothing"
}

@test "a repo config is fetched, cached and shown" {
  remote_config "$EXAMPLE"
  hbrew --repo nobody/nothing
  exits 0
  has "config: github:nobody/nothing"
  row_starts tree " tree ✗ not installed"
  [ -s "$XDG_CACHE_HOME/hbrew/tools.yaml" ]
  lacks "Config updated"
}

@test "a changed repo config is announced once" {
  remote_config "$EXAMPLE"
  hbrew --repo nobody/nothing
  exits 0
  printf 'tools:\n  - name: tree\n    brew: tree\n' > "$STUB_STATE/remote-config"
  hbrew --repo nobody/nothing
  exits 0
  has "Config updated from GitHub"
  hbrew --repo nobody/nothing
  exits 0
  lacks "Config updated"
}

@test "a run that fails to parse a changed repo config does not use up the notice" {
  remote_config "$EXAMPLE"
  hbrew --repo nobody/nothing
  exits 0
  printf 'tools:\n  - name: tree\n    brew: tree\n' > "$STUB_STATE/remote-config"
  PATH="$(path_without_python3)" hbrew --repo nobody/nothing
  exits 1
  hbrew --repo nobody/nothing
  exits 0
  has "Config updated from GitHub"
}

@test "a run that finds no tools in a changed repo config does not save its hash" {
  local sha="$XDG_CACHE_HOME/hbrew/tools.yaml.sha" before
  remote_config "$EXAMPLE"
  hbrew --repo nobody/nothing
  exits 0
  before="$(cat "$sha")"
  [ -n "$before" ]
  printf 'not a tools file\n' > "$STUB_STATE/remote-config"
  hbrew --repo nobody/nothing
  exits 1
  has "no tools found in config"
  [ "$(cat "$sha")" = "$before" ]
}

@test "a token from GH_TOKEN is sent to the GitHub API and never logged" {
  remote_config "$EXAMPLE"
  GH_TOKEN="sekrit-token-value" hbrew --repo nobody/nothing
  exits 0
  file_has curl-calls "api.github.com/repos/nobody/nothing/contents/"
  file_has curl-calls "Authorization: [redacted]"
  file_lacks curl-calls "sekrit-token-value"
  lacks "sekrit-token-value"
}

@test "without a token the gh session is asked, and the stub is signed out" {
  remote_config "$EXAMPLE"
  hbrew --repo nobody/nothing
  exits 0
  file_has gh-calls "auth status"
  file_lacks curl-calls "Authorization"
}

@test "the default config location is used when no flag is given" {
  mkdir -p "$XDG_CONFIG_HOME/hbrew"
  printf 'tools:\n  - name: tree\n    brew: tree\n' > "$XDG_CONFIG_HOME/hbrew/tools.yaml"
  hbrew
  exits 0
  row_starts tree " tree ✗ not installed"
}

@test "no config anywhere is an error that says where to put one" {
  hbrew
  exits 1
  has "No config found"
  has "$XDG_CONFIG_HOME/hbrew/tools.yaml"
}

@test "a missing --config file is an error" {
  hbrew --config "$BATS_TEST_TMPDIR/absent.yaml"
  exits 1
  has "config not found"
}

# ── the parser ────────────────────────────────────────────────────────────────

@test "a parser that cannot run fails the run instead of showing an empty table" {
  PATH="$(path_without_python3)" hbrew --config "$EXAMPLE"
  exits 1
  has "could not parse config"
  lacks "TOOL"
}

@test "a parser that cannot run fails --install-all before brew is touched" {
  PATH="$(path_without_python3)" hbrew --config "$EXAMPLE" --install-all
  exits 1
  has "could not parse config"
  no_file_content calls
}

@test "a config with no tools is an error, not an empty table" {
  hbrew --config "$REPO_ROOT/Makefile"
  exits 1
  has "no tools found in config"
  lacks "TOOL"
}

@test "an entry with no name is not a tool" {
  local cfg="$BATS_TEST_TMPDIR/blank.yaml"
  printf 'tools:\n  - name:\n    brew: tree\n' > "$cfg"
  hbrew --config "$cfg" --install-all
  exits 1
  has "no tools found in config"
  no_file_content calls
}

@test "the config is parsed exactly once per run, whatever the action" {
  local shim="$BATS_TEST_TMPDIR/shim" real action
  real="$(command -v python3)"
  mkdir -p "$shim"
  printf '#!/bin/sh\necho run >> "%s/python-runs"\nexec "%s" "$@"\n' "$STUB_STATE" "$real" > "$shim/python3"
  chmod +x "$shim/python3"
  for action in "" --install-all --update-all --uninstall-all; do
    : > "$STUB_STATE/python-runs"
    PATH="$shim:$PATH" hbrew --config "$EXAMPLE" $action
    exits 0
    [ "$(grep -c run "$STUB_STATE/python-runs")" -eq 1 ]
  done
}

@test "quotes around a note are stripped and the note is shown after install" {
  local cfg="$BATS_TEST_TMPDIR/one.yaml"
  printf 'tools:\n  - name: broot\n    brew: broot\n    notes: "Launch broot once"\n' > "$cfg"
  hbrew --config "$cfg" --install-all
  exits 0
  has "Note: Launch broot once"
  lacks '"Launch broot once"'
}

@test "a tool with no brew field and no special is reported, not installed" {
  local cfg="$BATS_TEST_TMPDIR/bare.yaml"
  printf 'tools:\n  - name: mystery\n' > "$cfg"
  hbrew --config "$cfg" --install-all
  exits 0
  has "mystery: no install method defined"
  brew_call_count install 0
}

@test "the parsed-config temp file is removed when the run ends, also on an error exit" {
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  hbrew --config "$EXAMPLE"
  exits 0
  [ -z "$(ls -A "$TMPDIR")" ]
  hbrew --config "$REPO_ROOT/Makefile"
  exits 1
  [ -z "$(ls -A "$TMPDIR")" ]
  PATH="$(path_without_python3)" hbrew --config "$EXAMPLE"
  exits 1
  [ -z "$(ls -A "$TMPDIR")" ]
}

# ── --install-all ─────────────────────────────────────────────────────────────

@test "--install-all installs only the missing tools" {
  installed atuin gh
  hbrew --config "$EXAMPLE" --install-all
  exits 0
  local tool
  for tool in broot btop starship tmux tree; do
    brew_called "install $tool"
  done
  brew_call_count install 5
  file_lacks calls '^install (atuin|gh)$'
  has "installed=5  skipped=3  failed=0"
}

@test "--install-all counts a failed install and carries on" {
  installed atuin gh
  echo "install btop" > "$STUB_STATE/fail"
  hbrew --config "$EXAMPLE" --install-all
  exits 0
  has "btop failed"
  has "installed=4  skipped=3  failed=1"
  brew_called "install tree"
}

# ── --update-all ──────────────────────────────────────────────────────────────

@test "--update-all upgrades only installed tools that are outdated" {
  installed atuin gh tree
  outdated gh btop
  hbrew --config "$EXAMPLE" --update-all
  exits 0
  brew_called "upgrade gh"
  brew_call_count upgrade 1
  has "updated=1"
  has "failed=0"
}

@test "--update-all counts a failed upgrade" {
  installed gh
  outdated gh
  echo "upgrade gh" > "$STUB_STATE/fail"
  hbrew --config "$EXAMPLE" --update-all
  exits 0
  has "gh update failed"
  has "updated=0"
  has "failed=1"
}

# ── --uninstall-all ───────────────────────────────────────────────────────────

@test "--uninstall-all removes installed tools and never homebrew" {
  installed atuin gh
  hbrew --config "$EXAMPLE" --uninstall-all
  exits 0
  brew_called "uninstall atuin"
  brew_called "uninstall gh"
  brew_call_count uninstall 2
  has "removed=2  skipped=5  failed=0"
}

# ── arguments ─────────────────────────────────────────────────────────────────

@test "-h prints usage and exits 0 without reading a config" {
  hbrew -h
  exits 0
  has "USAGE"
  has "HBREW_BREW"
}

@test "an unknown option is an error" {
  hbrew --frobnicate
  exits 1
  has "Unknown option: --frobnicate"
}

@test "--config without a value is an error" {
  hbrew --config
  exits 1
  has "--config requires a value"
}
