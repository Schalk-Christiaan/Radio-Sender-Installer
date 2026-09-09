# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Debian 13 installer (pure Bash + Liquidsoap) that turns a machine into an unattended internet-radio-to-FM sender: plays a primary stream, fails over to a backup stream and then to local music/sweepers on dead air or disconnect, recovers automatically, and exposes a `radioctl` CLI plus an optional full-screen TUI dashboard. All user-facing text, prompts, and code comments are in **Afrikaans** — match that when editing or adding to existing scripts/templates.

## Commands

Lint (what CI runs — `.github/workflows/shellcheck.yml`, triggers on push/PR to `main`):

```bash
shellcheck -x <file>              # single file, follows sourced files (-x)
shellcheck -x $(find . -name '*.sh')
```

Syntax-check a single script without running it:

```bash
bash -n templates/radio-dashboard.sh
```

There is no unit test suite. Verification is: `bash -n` + `shellcheck` on every changed script, plus manual/headless functional checks for interactive scripts (e.g. the dashboard) by stubbing `sudo`/`radioctl`/`systemctl` as fake executables on `PATH` and piping keystrokes into stdin — see recent commits for the pattern.

Running the installer requires an actual (or throwaway) Debian 13 host — it is not runnable/testable on this Windows dev machine:

```bash
sudo bash install.sh [--verbose]
sudo bash uninstall.sh
```

## Architecture

### Install-time flow

`install.sh` is a thin orchestrator: it checks for root + Debian 13, runs `scripts/setup.sh` (interactive wizard) if `config/environment.conf` doesn't exist yet, sources that config, then calls each `scripts/*.sh` step in sequence via `run_step "label" "script"` (logs to `installer.log`, aborts the whole install on any non-zero exit). Every step script follows the same shape: `set -e`, resolve its own dir via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, `source "$SCRIPT_DIR/progress.sh"` and (when it needs config) `source "$SCRIPT_DIR/../config/environment.conf"`, then report progress via `progress <percent> "label"` calls. Keep new install steps consistent with this shape and wire them into `install.sh` in the right order.

`scripts/setup.sh` is the only place that prompts the user; every prompted value is validated (`validate_url`, `validate_plain_text`, `validate_positive_int`, etc. — reject shell metacharacters `"'` `` ` `` `;` `\` `$`) before being written, `%q`-escaped, into `config/environment.conf`. That file is the single source of runtime config and is `source`d (as root) by later steps — the escaping is what makes that safe.

### Templates get filled in, not executed as-is

`templates/` holds files that are copied to their install location and then edited in place with `sed`:

- Simple value substitution: `__PLACEHOLDER__` tokens (e.g. `__STREAM_URL__`, `__ALSA_DEVICE__`, `__STATION_NAME__`) replaced via `sed -i "s|__X__|$value|g"` — always run replacement values through `escape_sed_replacement()` (escapes `&` and `|`) when they come from user config.
- Conditional blocks: marker comment lines like `# __BACKUP_RADIO_INSERT_POINT__` and `# __ACTIVE_SOURCE_BACKUP_BRANCH__` in `templates/radio.liq` get another template file `sed -i "/marker/r other-file"`-inserted above them when a feature is enabled (e.g. a backup stream is configured), then the marker line itself is deleted. `scripts/liquidsoap.sh` is the reference implementation of this pattern.
- Some templates are appended conditionally instead (e.g. `radio-icecast.liq` + `radio-server-socket.liq` are `cat >>`'d onto `radio.liq` only `if [ "$INSTALL_DASHBOARD" = "yes" ]`).

`templates/radioctl.sh` and `templates/radio-dashboard.sh` are the two templates that become long-lived executables (`/usr/local/bin/radioctl`, `/usr/local/bin/radio-dash`) rather than one-shot generated config — see below.

### Runtime layout (on the installed target)

Everything lives under `/opt/radio-orania` (`scripts/directories.sh` creates it, owned by the dedicated `radio-orania` service user, group `audio`):

```
/opt/radio-orania/
├── config/environment.conf   # active config, chmod 600, %q-escaped values
├── liquidsoap/radio.liq      # generated from templates/radio.liq + inserts
├── logs/, monitoring/
├── media/Musiek, media/Sweepers
├── filebrowser/, backups/
└── installer/                 # install.sh's own source copied here (persist_installer.sh) so `radioctl reconfigure`/`update` work without the original git clone
```

The radio service itself runs as `radio-orania` via `radio-orania.service` (systemd unit template, `__STATION_NAME__` substituted), executing `liquidsoap /opt/radio-orania/liquidsoap/radio.liq` directly — no wrapper process.

### `radioctl` (`templates/radioctl.sh`)

Dispatch is a flat `case "$1" in ... cmd_x ;; esac` at the bottom of the file calling `cmd_*` functions. It re-declares its own `contains_shell_metachars`/`is_valid_plain_text`/`is_valid_url` (deliberately separate copy from `scripts/setup.sh`'s validators, since this one runs post-install as root via `sudo radioctl set ...`) — **keep both copies in sync if the validation rules change.** `cmd_set` is the single mutation path: validates, rewrites the relevant key in `environment.conf`, then re-runs the specific installer step needed to apply it (e.g. `scripts/liquidsoap.sh` + service restart for stream/audio settings, `scripts/service.sh` for the station name) via `with_installer_config` — which temporarily restores a copy of `environment.conf` into `installer/config/` (deleted right after) since `persist_installer.sh` deliberately doesn't keep one there permanently, to avoid duplicating secrets on disk.

### Dashboard (`templates/radio-dashboard.sh`)

A single-file Bash TUI, installed as `/usr/local/bin/radio-dash` and auto-launched on login for a dedicated, unprivileged `radio-admin` user (`scripts/dashboard.sh`: created with only passwordless `sudo` access to `/usr/local/bin/radioctl`, auto-launched via that user's `.bash_profile`, and auto-logged-in on the physical console via a `getty@tty1.service.d` override). Also reachable any time via `radioctl dash`.

Structure to know before touching it (see also `docs/adr/0001-dashboard-single-screen-tab-navigation.md` for why it's shaped this way):
- `draw()` builds the **entire frame as one string** inside a single `$(...)` subshell and writes it in one `printf` (cursor-home + per-line clear-to-end-of-line, not a full screen clear) — this is what makes redraws flicker-free. Anything that must persist across redraws (`WAVE_FRAME`, the cached `STATION_BANNER_TEXT`, `STELSEL_BODY_CACHE`, `ACTIVE_TAB`) **must be mutated outside that subshell**, since subshell variable changes are lost when it exits.
- STATUS is always visible, on one continuously-redrawn screen — there is no separate mode/screen to navigate into. Below that sit six mutually-exclusive tabs (`TAB_NAMES`: BEHEER/INLIGTING/INSTELLINGS/ONDERHOUD/GEVAARLIK/TOETS), switched only by ◄/► arrow keys; each tab's options are a numbered list that restarts at 1 (type the number, press Enter — dispatched by `handle_tab_item()` based on `$ACTIVE_TAB`). `[Q]` Verlaat na shell is the one action that stands outside the tab system, always reachable. STELSEL (buffer/data/CPU, throttled to a 5s cache via `update_stelsel_body`) is INLIGTING tab content, not always-visible — `update_stelsel_body` is only called when `$ACTIVE_TAB = "INLIGTING"`. Each tab groups items by kind, not by history: BEHEER is live-broadcast control only (Begin/Stop/Herbegin/Monitor); INLIGTING is read-only display (stelsel-syfers, Logs, Media); INSTELLINGS is exclusively `radioctl set <SLEUTEL>` values; ONDERHOUD is system/panel upkeep (Rugsteun, Opdateer sagteware, Herkonfigureer, Kleurskema — none of these map to a single config key); GEVAARLIK is reserved for irreversible/sensitive actions regardless of how few items it currently holds.
- Input is read one char at a time (`read_main_key`): a digit starts a full-line read (multi-digit tab-item numbers, terminated by Enter, 15s timeout), ESC probes for an arrow-key sequence (cycles tabs), any other character is dispatched instantly as a single-key command.
- `<20` terminal lines triggers `compact` mode, which only suppresses decorative section headers/spacing — it does not change which content is shown (the tab bar itself is never suppressed).
- Color is theme-driven, not hardcoded: `PRIMARY`/`SECONDARY` are set by `apply_color_scheme()` from `~/.radio-dashboard-colors`, so new UI elements should reference those variables rather than a literal color code.
- The TOETS tab's fault-injection actions (`templates/radioctl.sh` `test-*` commands) are each independently reversible: source stop/start goes through Liquidsoap's `<id>.stop`/`<id>.start` server commands over the existing local socket (no real network risk), the internet-loss test allows ESTABLISHED/RELATED traffic and auto-reverts after 60s via `systemd-run` even if nobody clicks restore, and the service-crash test requires its own Y/N confirmation before running (the only TOETS action that causes a real, audible outage).

### Security patterns to preserve

- Radio/File Browser/heartbeat services run as the unprivileged `radio-orania` user; the dashboard's `radio-admin` user only has passwordless sudo to `radioctl` itself, nothing broader.
- Any value that ends up in a generated shell/config/Liquidsoap file goes through validation (reject `"'` `` ` `` `;` `\` `$`) and, for `environment.conf`, `printf %q` quoting — follow this for any new configurable field.
- `environment.conf` and credential files are `chmod 600`.

### Line endings

`.gitattributes` forces LF for `*.sh`, `*.liq`, `*.service`, `*.conf` — these run on Linux targets, so don't let Windows tooling introduce CRLF into them.

## Agent skills

### Issue tracker

GitHub Issues (Schalk-Christiaan/Radio-Sender-Installer), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root (not yet created; written lazily when needed). See `docs/agents/domain.md`.
