# r-hbrew — CLAUDE.md

`hbrew` is a Homebrew tool manager in one bash script: it reads a YAML list of
tools, from a local file or a GitHub repo, and shows status or installs,
updates and uninstalls them. [README.md](README.md) is the user documentation.

## Repo layout

```
hbrew.sh             The tool. install.sh copies it to ~/.local/bin/hbrew
install.sh           Installer: copies hbrew.sh, installs oh-my-zsh if missing, writes the alias
tools.example.yaml   Example config, also the reference for the config format
README.md            Usage, config format, private-repo auth
```

## Setup and verification

```bash
make check      # shellcheck on both scripts
```

There is nothing to install in the checkout itself. `make check` needs
`shellcheck` on `PATH` (`brew install shellcheck`). `make lint` is the same
check under its own name. There is no automated test suite: behaviour is
verified by running
`env -u HBREW_REPO bash hbrew.sh --config tools.example.yaml`, which only reads
brew's state. Unset `HBREW_REPO` for that run: when it is set, the repo config
is used even if `--config` is passed.

## Idioms

- **`hbrew.sh` stays one self-contained file.** It is deployed by copying that
  single file, so it cannot source a sibling. Its only dependencies are bash,
  `curl`, and `python3` from the standard library; `brew` and `gh` are used
  when present and must not be assumed.
- **The YAML parser is the embedded Python in `parse_config`**, standard
  library only. Don't add `yq` or PyYAML: hbrew has to run on a fresh machine
  before any tool is installed.
- **Auth order for a private config repo** is `GH_TOKEN`/`GITHUB_TOKEN`, then a
  `gh` session, then unauthenticated `curl`. A token is never printed.
- **Status is read-only.** Bare `hbrew` only reads; anything that changes the
  machine sits behind an explicit `--install-all`, `--update-all` or
  `--uninstall-all`.
- **Both scripts run under `set -euo pipefail`** and are kept clean under
  `shellcheck` at its default severity. Colours are `$'...'` variables passed
  to `printf` as arguments, not placed in the format string.
- **A config field or flag change updates three places**: the `usage()` text,
  `README.md`, and `tools.example.yaml`.

## Review

Review output goes to `docs/reviews/pr-*/`, which is git-ignored. No extra
review pre-passes are declared.
