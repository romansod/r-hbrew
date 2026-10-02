#!/usr/bin/env bats
# Tests for hbrew.sh. Nothing here touches the real brew, the real home
# directory or the network: brew is stubbed through HBREW_BREW, curl through
# PATH, and the cache and config directories live under the test's tmp dir.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HBREW="$REPO_ROOT/hbrew.sh"
  EXAMPLE="$REPO_ROOT/tools.example.yaml"

  export STUB_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUB_STATE"
  : > "$STUB_STATE/calls"
  : > "$STUB_STATE/curl-calls"

  export HBREW_BREW="$BATS_TEST_DIRNAME/stubs/brew"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  unset HBREW_REPO GH_TOKEN GITHUB_TOKEN
}

# Run hbrew and strip colour and progress-bar control sequences from $output.
hbrew() {
  run bash "$HBREW" "$@"
  output="$(printf '%s' "$output" | sed -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | tr '\r' '\n')"
}

installed() { printf '%s\n' "$@" > "$STUB_STATE/installed"; }
outdated() { printf '%s\n' "$@" > "$STUB_STATE/outdated"; }

# The table row for one tool, squeezed to single spaces.
row() { printf '%s\n' "$output" | grep -E "^  $1 " | tr -s ' '; }

# A PATH that has everything hbrew needs except python3.
path_without_python3() {
  local dir="$BATS_TEST_TMPDIR/nopython" tool
  mkdir -p "$dir"
  for tool in bash env cat mkdir grep sed awk tr seq tail head dirname shasum; do
    ln -sf "$(command -v "$tool")" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# ── status ────────────────────────────────────────────────────────────────────

@test "status lists one row per tool in the example config" {
  hbrew --config "$EXAMPLE"
  [ "$status" -eq 0 ]
  for tool in homebrew atuin broot btop gh starship tmux tree; do
    [ -n "$(row "$tool")" ]
  done
  [ "$(printf '%s\n' "$output" | grep -cE '(✓ installed|✗ not installed)')" -eq 8 ]
}

@test "status tells installed, outdated and missing tools apart" {
  installed atuin gh
  outdated gh
  hbrew --config "$EXAMPLE"
  [ "$status" -eq 0 ]
  [ "$(row atuin)" = " atuin ✓ installed 1.2.3 up to date" ]
  [ "$(row gh)" = " gh ✓ installed 1.2.3 update available" ]
  [[ "$(row btop)" == " btop ✗ not installed"* ]]
}

@test "status reports homebrew itself with brew's own version" {
  hbrew --config "$EXAMPLE"
  [ "$(row homebrew)" = " homebrew ✓ installed 9.9.9 up to date" ]
}

@test "status reports homebrew as missing when HBREW_BREW is not executable" {
  HBREW_BREW="$BATS_TEST_TMPDIR/no-such-brew" hbrew --config "$EXAMPLE"
  [ "$status" -eq 0 ]
  [[ "$(row homebrew)" == " homebrew ✗ not installed"* ]]
  [ ! -s "$STUB_STATE/calls" ]
}

@test "status changes no tool" {
  installed atuin
  outdated atuin
  hbrew --config "$EXAMPLE"
  [ "$status" -eq 0 ]
  ! grep -qE '^(install|upgrade|uninstall|update)( |$)' "$STUB_STATE/calls"
}

@test "status names the config it read" {
  hbrew --config "$EXAMPLE"
  [[ "$output" == *"config: $EXAMPLE"* ]]
}

# ── config resolution ─────────────────────────────────────────────────────────

@test "an explicit --config wins over HBREW_REPO and makes no network call" {
  HBREW_REPO="nobody/nothing" hbrew --config "$EXAMPLE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config: $EXAMPLE"* ]]
  [ ! -s "$STUB_STATE/curl-calls" ]
}

@test "HBREW_REPO alone still selects the repo config" {
  HBREW_REPO="nobody/nothing" hbrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch config"* ]]
  grep -q "nobody/nothing" "$STUB_STATE/curl-calls"
}

@test "--repo given with --config keeps the repo" {
  hbrew --config "$EXAMPLE" --repo nobody/nothing
  [ "$status" -eq 1 ]
  grep -q "nobody/nothing" "$STUB_STATE/curl-calls"
}

@test "the default config location is used when no flag is given" {
  mkdir -p "$XDG_CONFIG_HOME/hbrew"
  printf 'tools:\n  - name: tree\n    brew: tree\n' > "$XDG_CONFIG_HOME/hbrew/tools.yaml"
  hbrew
  [ "$status" -eq 0 ]
  [[ "$(row tree)" == " tree ✗ not installed"* ]]
}

@test "no config anywhere is an error that says where to put one" {
  hbrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"No config found"* ]]
  [[ "$output" == *"$XDG_CONFIG_HOME/hbrew/tools.yaml"* ]]
}

@test "a missing --config file is an error" {
  hbrew --config "$BATS_TEST_TMPDIR/absent.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config not found"* ]]
}

# ── the parser ────────────────────────────────────────────────────────────────

@test "a parser that cannot run fails the run instead of showing an empty table" {
  PATH="$(path_without_python3)" hbrew --config "$EXAMPLE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not parse config"* ]]
  [[ "$output" != *"TOOL"* ]]
}

@test "a parser that cannot run fails --install-all before brew is touched" {
  PATH="$(path_without_python3)" hbrew --config "$EXAMPLE" --install-all
  [ "$status" -eq 1 ]
  [ ! -s "$STUB_STATE/calls" ]
}

@test "quotes around a note are stripped and the note is shown after install" {
  local cfg="$BATS_TEST_TMPDIR/one.yaml"
  printf 'tools:\n  - name: broot\n    brew: broot\n    notes: "Launch broot once"\n' > "$cfg"
  hbrew --config "$cfg" --install-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Note: Launch broot once"* ]]
  [[ "$output" != *'"Launch broot once"'* ]]
}

@test "a tool with no brew field and no special is reported, not installed" {
  local cfg="$BATS_TEST_TMPDIR/bare.yaml"
  printf 'tools:\n  - name: mystery\n' > "$cfg"
  hbrew --config "$cfg" --install-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"mystery: no install method defined"* ]]
  ! grep -q '^install' "$STUB_STATE/calls"
}

# ── --install-all ─────────────────────────────────────────────────────────────

@test "--install-all installs only the missing tools" {
  installed atuin gh
  hbrew --config "$EXAMPLE" --install-all
  [ "$status" -eq 0 ]
  for tool in broot btop starship tmux tree; do
    grep -qx "install $tool" "$STUB_STATE/calls"
  done
  ! grep -qx "install atuin" "$STUB_STATE/calls"
  ! grep -qx "install gh" "$STUB_STATE/calls"
  [[ "$output" == *"installed=5  skipped=3  failed=0"* ]]
}

@test "--install-all counts a failed install and carries on" {
  installed atuin gh
  echo "install btop" > "$STUB_STATE/fail"
  hbrew --config "$EXAMPLE" --install-all
  [[ "$output" == *"btop failed"* ]]
  [[ "$output" == *"installed=4  skipped=3  failed=1"* ]]
  grep -qx "install tree" "$STUB_STATE/calls"
}

# ── --update-all ──────────────────────────────────────────────────────────────

@test "--update-all upgrades only installed tools that are outdated" {
  installed atuin gh tree
  outdated gh btop
  hbrew --config "$EXAMPLE" --update-all
  [ "$status" -eq 0 ]
  grep -qx "upgrade gh" "$STUB_STATE/calls"
  [ "$(grep -c '^upgrade ' "$STUB_STATE/calls")" -eq 1 ]
  [[ "$output" == *"updated=1"* ]]
  [[ "$output" == *"failed=0"* ]]
}

@test "--update-all without brew is an error" {
  HBREW_BREW="$BATS_TEST_TMPDIR/no-such-brew" hbrew --config "$EXAMPLE" --update-all
  [ "$status" -eq 1 ]
  [[ "$output" == *"brew not found"* ]]
}

# ── --uninstall-all ───────────────────────────────────────────────────────────

@test "--uninstall-all removes installed tools and never homebrew" {
  installed atuin gh
  hbrew --config "$EXAMPLE" --uninstall-all
  [ "$status" -eq 0 ]
  grep -qx "uninstall atuin" "$STUB_STATE/calls"
  grep -qx "uninstall gh" "$STUB_STATE/calls"
  [ "$(grep -c '^uninstall ' "$STUB_STATE/calls")" -eq 2 ]
  [[ "$output" == *"removed=2  skipped=5  failed=0"* ]]
}

# ── arguments ─────────────────────────────────────────────────────────────────

@test "-h prints usage and exits 0 without reading a config" {
  hbrew -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"HBREW_BREW"* ]]
}

@test "an unknown option is an error" {
  hbrew --frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --frobnicate"* ]]
}

@test "--config without a value is an error" {
  hbrew --config
  [ "$status" -eq 1 ]
  [[ "$output" == *"--config requires a value"* ]]
}
