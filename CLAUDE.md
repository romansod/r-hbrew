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
tests/stubs/         Stand-ins for brew, curl and gh that the suite puts in front of the real ones
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
  real `gh` session, the real home directory or the network. brew is replaced
  through `HBREW_BREW`. `curl` and `gh` are replaced by stubs first on `PATH`:
  the curl stub records each call with any `Authorization` value redacted and
  serves a canned config when a test provides one, and the gh stub is always
  signed out. The cache and config directories live under the test's temporary
  directory.

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
- **The config is parsed once.** The main block runs `parse_config` into a
  temporary file and exits 1 if the parser fails or finds no tools; every
  action reads that file (`"$PARSED_TOOLS"`). A new action reads it too, and
  never calls `parse_config` through process substitution, which hides the
  parser's exit status.
- **`HBREW_BREW` is validated at startup.** Set to anything but an executable
  file, it is an error before any action runs. Treated as "brew not found" it
  would make `--install-all` try to install Homebrew.
- **Tests never run the real brew or the real gh.** A test that leaves
  `HBREW_BREW` unset would install, upgrade or remove real packages; `setup()`
  sets it for every test.
- **Test assertions use `[ ... ]` or the helpers in `tests/hbrew.bats`** —
  never `[[ ... ]]` and never a bare `! command`. bats runs under `/bin/bash`
  3.2 on macOS, where a false `[[ ]]` that is not the last command of a test
  does not fail it, and a `!`-negated command never fails a test on any bash.
- **A behaviour change comes with a test**, and the test is shown to fail when
  the behaviour is broken.
- **Documentation follows the change.** A config field updates the `usage()`
  text, `README.md` and `tools.example.yaml`; a flag or environment variable
  updates `usage()` and `README.md`.

## Review

Review output goes to `docs/reviews/pr-*/`, which is git-ignored. No extra
review pre-passes are declared.
