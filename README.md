# hbrew

A lightweight Homebrew tool manager. Define your tools in a YAML config file — stored locally or in a GitHub repo — and use a single script to check status, install, update, or uninstall all of them.

## Install

```sh
git clone https://github.com/romansod/r-hbrew
bash r-hbrew/install.sh
exec zsh
```

This copies `hbrew` to `~/.local/bin/hbrew` and writes an alias to `~/.oh-my-zsh/custom/hbrew.zsh`. If you're not using oh-my-zsh, add this to your shell config manually:

```sh
alias hbrew="$HOME/.local/bin/hbrew"
```

## Usage

```
hbrew [OPTIONS]

  --config FILE          Use a local config file
  --repo OWNER/REPO      Fetch config from a GitHub repo
  --config-path PATH     Path within the repo (default: tools.yaml or configs/tools.yaml)
  --install-all          Install all tools listed in config
  --update-all           Update all installed tools via brew upgrade
  --uninstall-all        Uninstall all tools listed in config
  -h, --help             Show help

  ENV VARS
  HBREW_REPO             Default repo, so bare 'hbrew' works without --repo
  GH_TOKEN / GITHUB_TOKEN  GitHub PAT for private repos (used before gh CLI)
```

**Show status** (default — no flags):

```
hbrew --repo you/dotfiles

hbrew v1.0.0
config: github:you/dotfiles

  TOOL             STATUS             VERSION      UPDATE
  ──────────────────────────────────────────────────────────
  homebrew         ✓ installed        4.2.0        up to date
  atuin            ✓ installed        18.3.0       update available
  broot            ✗ not installed    -            -
  gh               ✓ installed        2.62.0       up to date
```

If the remote config has changed since the last run, a notice is shown at the top.

## Config format

A `tools.yaml` file at the root of your repo (or at `configs/tools.yaml`):

```yaml
tools:
  # homebrew itself — installed via the official install script
  - name: homebrew
    special: homebrew
    notes: "Add brew to PATH after install: eval $(brew shellenv)"

  # standard brew formula
  - name: atuin
    brew: atuin
    notes: "Run 'atuin import auto' to import existing shell history"

  - name: broot
    brew: broot
    notes: "Launch 'broot' once and type ':install' to enable the 'br' shell function"

  - name: btop
    brew: btop

  - name: gh
    brew: gh
    notes: "Run 'gh auth login' to authenticate with GitHub"

  - name: tree
    brew: tree
```

Fields:
| Field | Required | Description |
|---|---|---|
| `name` | yes | Display name |
| `brew` | for brew packages | Homebrew formula name |
| `special: homebrew` | for Homebrew itself | Installs via the official install script |
| `notes` | no | Shown after install — useful for post-install steps |

## Examples

```sh
# Set a default repo so 'hbrew' works bare (add to .zshrc)
export HBREW_REPO="you/dotfiles"

# Show status
hbrew
hbrew --repo you/dotfiles
hbrew --config ~/my-tools.yaml

# Install / update / remove
hbrew --install-all
hbrew --update-all
hbrew --uninstall-all

# Config at a non-default path in the repo
hbrew --repo you/dotfiles --config-path system/tools.yaml
```

## Private repos

Auth is resolved in this order:

1. `GH_TOKEN` or `GITHUB_TOKEN` env var — works before `gh` is installed
2. `gh` CLI session — works after `gh auth login`
3. Unauthenticated `curl` — public repos only

**Bootstrap on a fresh machine** (before `gh` is installed):

```sh
GH_TOKEN=<your-pat> hbrew --repo you/dotfiles --install-all
```

Generate a PAT at github.com/settings/tokens with `repo` scope. Once `gh` is installed, run `gh auth login` and you won't need the token again.
