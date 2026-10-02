# r-hbrew — CLAUDE.md

`hbrew` is a Homebrew tool manager in one bash script: it reads a YAML list of
tools, from a local file or a GitHub repo, and shows status or installs,
updates and uninstalls them. [README.md](README.md) is the user documentation.

## Repo layout

```
hbrew.sh             The tool. install.sh copies it to ~/.local/bin/hbrew
install.sh           Installer: copies hbrew.sh, installs oh-my-zsh if missing, writes the alias
tools.example.yaml   Example config, also the reference for the config format
tests/hbrew.bats     The test suite (bats)
tests/stubs/         Stand-ins for brew and curl that the suite puts in front of the real ones
README.md            Usage, config format, private-repo auth
```

## Setup and verification

```bash
make check      # lint + test
```

There is nothing to install in the checkout itself. `make check` needs
`shellcheck` and `bats` on `PATH` (`brew install shellcheck bats-core`).

- `make lint` runs `shellcheck` on both scripts and on the test stubs.
- `make test` runs `bats tests`. The suite never touches the real brew, the
  real home directory or the network: brew is replaced through `HBREW_BREW`,
  `curl` by a stub first on `PATH` that records the call and fails, and the
  cache and config directories live under the test's temporary directory.

`install.sh` has no tests: it writes to the real home directory and can install
oh-my-zsh. Check a change to it by reading, and by running the affected lines
alone.

## Idioms

- **`hbrew.sh` stays one self-contained file.** It is deployed by copying that
  single file, so it cannot source a sibling. Beyond bash it needs `curl`,
  `python3` (standard library only), `shasum`, and the usual POSIX utilities
  (`awk`, `grep`, `seq`, `tr`, `tail`); `brew` and `gh` are used when present
  and must not be assumed.
- **The YAML parser is the embedded Python in `parse_config`**, standard
  library only. Don't add `yq` or PyYAML: hbrew has to run on a fresh machine
  before any tool is installed.
- **Auth order for a private config repo** is `GH_TOKEN`/`GITHUB_TOKEN`, then a
  `gh` session, then unauthenticated `curl`. A token is never echoed or
  logged. It is passed to `curl` as an argument, so it is visible in the
  process list while the fetch runs; that is a known weakness, not a guarantee.
- **Status changes no tool.** Bare `hbrew` never installs, updates or removes
  anything; that sits behind an explicit `--install-all`, `--update-all` or
  `--uninstall-all`. It does write its own cache: the cache directory on every
  run, and the fetched config and its hash in repo mode.
- **Both scripts run under `set -euo pipefail`** and are kept clean under
  `shellcheck` at its default severity. Colours are `$'...'` variables. A
  `printf` format string is never made of variables alone (`shellcheck`
  SC2059): pass such a string as an argument to `printf '%s'`. A colour beside
  a `%` specifier in the format string is accepted, and `do_status` does it.
- **`HBREW_REPO` is a default, not an override.** An explicit `--config` wins
  over it; `--repo` given on the command line wins over `--config`.
- **A parser failure fails the run.** The actions read `parse_config` through
  process substitution, which hides its exit status, so the main block runs the
  parser once first and exits 1 if it fails. Keep that check when adding an
  action.
- **Tests never run the real brew.** A test that leaves `HBREW_BREW` unset
  would install, upgrade or remove real packages. `setup()` sets it for every
  test; a test that overrides it points at a path that does not exist.
- **A behaviour change comes with a test** in `tests/hbrew.bats`.
- **A config field, flag or environment variable change updates three
  places**: the `usage()` text, `README.md`, and `tools.example.yaml`.

## Review

Review output goes to `docs/reviews/pr-*/`, which is git-ignored. No extra
review pre-passes are declared.
