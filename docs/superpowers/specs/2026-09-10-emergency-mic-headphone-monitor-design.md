---
status: proposed
---

# Emergency microphone override + simultaneous headphone monitor

## Summary

Two independent audio-hardware capabilities, both driven by physical devices connected to the machine running `radio-orania.service`:

1. **Emergency microphone override** — a manually-activated live source that fully replaces whatever is currently on air (stream/backup/local music), for spoken emergency announcements. Activated/deactivated through the existing `radioctl wissel` mechanism, same as switching to a stream or to local music.
2. **Headphone monitor** — a second, simultaneous ALSA output that always carries the exact same mix the transmitter receives, so the operator can plug in headphones at any time to listen without disturbing the broadcast.

Neither capability is present in the system today. Both are additive: no existing behavior (stream failover, `radioctl wissel`, dashboard tabs) changes shape, they gain one more case each.

## Decisions already made (via user Q&A)

- Mic fully **replaces** the current source while active (no mixing/ducking).
- Activation is **manual only** (`radioctl wissel mikrofoon`, mirrored in BEHEER) — never auto-detected on plug-in.
- Deactivation is **manual only** (`radioctl wissel outomaties`) — no silence-based auto-revert.
- Headphones are **simultaneous monitor output**, not a switchable alternate output.

## Non-goals

- Auto-revert of the mic on silence or unplug detection.
- Mixing/ducking the mic over background audio.
- Hot-swapping which physical device is "the" transmitter output — `ALSA_DEVICE` keeps its existing single-purpose meaning; headphones are strictly additive.
- Handling a mic that gets unplugged *while* `source_override == "mikrofoon"` — same open gap that already exists for a stream dying mid-broadcast beyond what `radio_connected`/`is_ready` catch. Deferred; revisit with the same `on_start`/`on_stop`-callback approach used for `radio_connected` if it turns out to matter in practice.

## Prior investigation (this session, on `radio-test` WSL VM, Liquidsoap 2.3.2+dev)

- `input.alsa(device=..., fallible=true, start=false)` is safe to declare even when the named ALSA device doesn't exist: `is_ready()`/`is_started()` just report `false`, no crash, confirmed via an isolated probe script.
- Calling `.start()` on a **non-existent** device raises an uncaught language-level runtime error (`Error 9: Failure: Error while setting open_pcm: No such file or directory`). A naive `try ... catch _ do ... end` did not catch it in a quick test; the process itself did not crash or hang, but the exact catch syntax needs more care than time allowed during brainstorming.
- **Design consequence**: don't lean on Liquidsoap-side exception handling as the primary safety net. Validate the device's existence at the shell level (`arecord -l`) in `radioctl wissel mikrofoon` *before* ever telling Liquidsoap to start it — consistent with how `BACKUP_STREAM_URL`/`PRIMARY_SOURCE` are already validated in `cmd_set` before being applied. Getting a clean Liquidsoap-side `try/catch` right (as defense in depth, for the race where the device disappears between the shell check and `.start()`) is left to the implementation plan to work out and verify with `liquidsoap --check` + real runs, not assumed solved by this spec.
- The existing "second simultaneous `output.*` consuming `main`" pattern is already proven in this codebase: `radio-icecast.liq` already adds an `output.icecast(..., main)` alongside `output.alsa(..., main)` when the dashboard is installed. The headphone output reuses this exact pattern with a second `output.alsa`.

## Architecture

### Emergency microphone

Reuses the existing `source_override` file/thread mechanism (`radioctl wissel`, `read_source_override()`, `switch()` predicates, `check_active_source()`) rather than inventing a parallel one. `"mikrofoon"` becomes a fourth valid override value alongside `"primer"`, `"rugsteun"`, `"noodmusiek"`.

- `mic = input.alsa(id="mic_input", device=mic_device, fallible=true, start=false)` — declared once, like `radio`/`backup_radio`.
- `read_source_override()` (the existing 2-second thread) gains responsibility for calling `mic.start()`/`mic.stop()` when the requested value transitions into/out of `"mikrofoon"`. It needs to track the *previous* requested value (a new `ref`) to only call start/stop on the transition, not every tick.
- Mirroring the existing `"noodmusiek"`-degrades-when-empty pattern: if `requested == "mikrofoon"` but, after attempting to start it, `mic.is_ready()` is still false, the effective override degrades back to `""` (automatic) rather than latching onto a silent/failed branch. This reuses the same degrade mechanism already in `read_source_override()`, extended with one more condition.
- `switch()` gains a new **first** predicate (highest priority, checked before `"primer"`): `({source_override() == "mikrofoon" and mic.is_ready()}, mic)`.
- `check_active_source()` mirrors this as a new first `if` branch, writing (a new label, e.g.) `"mikrofoon"` to `active_source` — dashboard/status-card work needed to display this label is in scope for the implementation plan (falls out of the existing `active_source`-reading code path, no new plumbing).

### Headphone monitor

No `source_override` involvement — this isn't a selectable *source*, it's an always-on second *sink* for whatever `main` already is.

```
if HEADPHONE_DEVICE is set:
    output.alsa(device=headphone_device, main)
```

Added unconditionally alongside the existing `output.alsa(device=alsa_device, main)`, gated the same way the icecast output is gated on `INSTALL_DASHBOARD`/config presence.

## Components touched

- **`templates/radio.liq`**: `mic` source declaration; `read_source_override()` extended (start/stop transition + degrade condition); new `switch()` predicate (first in `switch_sources`, so it also automatically picks up the existing `crossfade` transition via `list.map`); `check_active_source()` mirror; conditional second `output.alsa` for headphones.
- **`templates/radioctl.sh`**: `cmd_wissel`'s `case` gains a `mikrofoon)` branch — validates `MIC_DEVICE` is configured (non-empty) *and* currently appears in `arecord -l` output, rejecting with a clear Afrikaans message otherwise; `SETTABLE_KEYS`/`cmd_set` gain `MIC_DEVICE` and `HEADPHONE_DEVICE` (both optional, empty = disabled, same convention as `BACKUP_STREAM_URL`/`HEARTBEAT_URL`); both trigger the existing `scripts/liquidsoap.sh` + service-restart group in `cmd_set` (same group as `ALSA_DEVICE`).
- **`scripts/liquidsoap.sh`**: substitute `__MIC_DEVICE__`/`__HEADPHONE_DEVICE__` (default-empty like `BACKUP_STREAM_URL` handling), and gate the headphone `output.alsa` block the same additive-insert way the backup-radio blocks are gated (new marker + insert file, or a simple always-present `if headphone_device != "" then ... end` directly in the template if that turns out simpler — implementation plan to decide based on what reads cleaner).
- **`templates/radio-dashboard.sh`**: BEHEER gains a "Noodmikrofoon aan/af" item (toggle label depending on current `active_source`, same pattern as the existing Monitor Aan/Af toggle). INSTELLINGS gains "Mikrofoon-toestel" and "Oorfone-toestel" items, both listing available devices first (`arecord -l` / `aplay -l` respectively) before prompting, mirroring the existing ALSA_DEVICE item's UX.
- **`config/environment.conf` / `scripts/setup.sh`**: no initial-install prompts (same lazy-default precedent as `PRIMARY_SOURCE`) — both keys are configured later via `radioctl set` / INSTELLINGS, defaulting to empty (disabled) until set.

## Data flow

Identical shape to the existing "Wissel bron" flow: `radioctl wissel mikrofoon` (after its device-presence check) writes `"mikrofoon"` to the `source_override` file; the existing 2-second Liquidsoap thread reads it, starts the mic, and `switch()` picks it up on the next predicate evaluation. `radioctl wissel outomaties` writes `""`; the thread sees the transition and stops the mic.

## Error handling

- `radioctl wissel mikrofoon` with `MIC_DEVICE` unset → rejected, Afrikaans message pointing at INSTELLINGS.
- `MIC_DEVICE` set but not currently in `arecord -l` → rejected before touching Liquidsoap at all.
- Device passes the shell-level check but still fails to start inside Liquidsoap (race, or a bad-but-present device) → degrades to automatic per the design above, rather than latching a silent `mic` branch.
- Headphones: `HEADPHONE_DEVICE` unset simply means the second `output.alsa` is omitted — no error path needed, this mirrors how `BACKUP_STREAM_URL` being empty already omits `backup_radio` entirely.

## Testing

- `bash -n` + `shellcheck -x` on every changed script.
- `liquidsoap --check` against the generated `radio.liq`, with and without `HEADPHONE_DEVICE`/`MIC_DEVICE` set, same dry-run harness already used earlier this session.
- On the `radio-test` VM: confirm a service with `MIC_DEVICE` pointed at a genuinely non-existent device (a) never crashes the service at boot, (b) `radioctl wissel mikrofoon` is cleanly rejected by the shell-level check. If a real capture device is available in that environment, confirm the full activate → `switch()` picks `mic` → `active_source` reflects it → deactivate cycle, plus that the crossfade transition doesn't error when `mic` is one of the two sources involved.
- Headphone output: confirm `liquidsoap --check` accepts a second `output.alsa` pointed at a plausible device string, and that omitting `HEADPHONE_DEVICE` produces byte-identical `radio.liq` structure to before this change (no accidental behavior change for installs that never configure it).

## Open items for the implementation plan

- Exact Liquidsoap `try`/`catch` syntax for wrapping `mic.start()` as defense-in-depth (the shell-level check is the primary guard; this is a belt-and-braces backstop for the TOCTOU race).
- Whether the headphone `output.alsa` block needs its own template-insert marker/file (matching the backup-radio pattern) or can be a simple inline `if` — decide based on what's cleanest once the surrounding code is being edited.
- Exact wording/placement of the new BEHEER dashboard item and the new `active_source` label surfaced on the status card.
