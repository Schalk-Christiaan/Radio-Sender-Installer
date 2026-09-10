# Emergency Microphone + Headphone Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator (a) plug in a microphone and force it live over the air for an emergency announcement, fully replacing whatever is currently broadcasting, and (b) plug in headphones that always carry a live copy of exactly what's going out to the transmitter, for monitoring.

**Architecture:** Both features are additive extensions of existing mechanisms, not a new subsystem. The mic reuses the existing `source_override` file/thread/`switch()` plumbing (`radioctl wissel`) that already drives "primer"/"rugsteun"/"noodmusiek" — it becomes a fourth value, `"mikrofoon"`, checked with the highest priority. The headphone output reuses the already-proven "second simultaneous `output.*` consuming `main`" pattern that `radio-icecast.liq` already uses for the dashboard's Icecast relay.

**Tech Stack:** Bash (installer scripts, `radioctl`, dashboard), Liquidsoap 2.3 (`.liq` templates), `sed`-based template generation, ALSA (`arecord`/`aplay`) for device enumeration.

**Spec:** `docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md`

## Global Constraints

- All user-facing text (radioctl output, dashboard labels, code comments) is in **Afrikaans** — match the existing tone (see any current `templates/radioctl.sh` message for style).
- Any value written into `environment.conf` goes through `printf '%q'` quoting (already handled generically by `cmd_set` — no new escaping code needed for these two keys).
- Any value that reaches a generated `.liq`/shell file via `sed` must go through `escape_sed_replacement()` in `scripts/liquidsoap.sh` (already used for `ALSA_DEVICE`, `BACKUP_STREAM_URL`, etc. — apply the same helper to the two new substitutions).
- New settable keys are **optional**, empty string = feature disabled — same convention as `BACKUP_STREAM_URL`/`HEARTBEAT_URL`. Never require them.
- The emergency mic **fully replaces** the current source while active (no mixing). It is activated and deactivated **only** by explicit operator action (`radioctl wissel mikrofoon` / `radioctl wissel outomaties`) — never auto-detected, never auto-reverted on silence.
- **Verification**: `bash -n <file>` and `shellcheck -x <file>` on every changed shell script (per `CLAUDE.md`); `liquidsoap --check` on the generated `radio.liq` wherever a Debian/Liquidsoap test host is available (this repo's development session used a WSL Debian instance named `radio-test` reachable via `wsl.exe -d radio-test -- <command>` from the Windows host — reuse it if it still exists; otherwise note in your task write-up that this step needs a real Debian 13 host per `CLAUDE.md`'s own stated limitation, and describe exactly what you'd run).
- Never skip a step's verification and move on "because it's probably fine" — this project has no automated test suite, so the manual checks in this plan **are** the test suite.

---

### Task 1: `radio.liq` — emergency microphone source + `source_override` integration

**Files:**
- Modify: `templates/radio.liq`
- Modify: `scripts/liquidsoap.sh`

**Interfaces:**
- Produces: `mic_device` (string, from `__MIC_DEVICE__`), `mic` (a `source`, `input.alsa(id="mic_input", ...)`), the `"mikrofoon"` value for `source_override()`, and `active_source` file gaining a new possible content value `"mikrofoon"`.
- Consumes: the existing `source_override_path`, `source_override` ref, `read_source_override()` function, `switch_sources` list, `check_active_source()` function — all already present in `templates/radio.liq` from earlier work this session.

- [ ] **Step 1: Add the `mic_device` setting**

In `templates/radio.liq`, find:

```
alsa_device = "__ALSA_DEVICE__"
```

Add immediately after it:

```

# Toestel vir die noodmikrofoon (bv. "hw:1,0") - leeg beteken die
# funksie is afgeskakel. radioctl valideer by "wissel mikrofoon" dat
# die toestel werklik in arecord -l verskyn voor dit hier ooit gebruik
# word.
mic_device = "__MIC_DEVICE__"
```

- [ ] **Step 2: Declare the `mic` source**

In `templates/radio.liq`, find the end of the `radio = buffer(...)` block (it ends with the closing `)` right before the `# __BACKUP_RADIO_INSERT_POINT__` marker line). Immediately after that closing `)` and before the marker line, insert:

```

# Noodmikrofoon
#
# start=false, fallible=true beteken hierdie bron NOOIT self probeer
# koppel tensy iets eksplisiet mic.start() roep - dis dus veilig om te
# declareer al is mic_device leeg of verwys dit na 'n toestel wat nie
# (nog) gekoppel is nie (getoets: geen omval nie). 'n mislukte
# mic.start() (bv. toestel bestaan nie werklik) gooi self 'n
# Liquidsoap-fout, maar radioctl (cmd_wissel se "mikrofoon"-tak)
# valideer eers self via arecord -l dat die toestel bestaan voor
# hierdie punt ooit bereik word - dis die primêre skans, nie enige
# vang-logika hieronder nie.

mic = input.alsa(id="mic_input", device=mic_device, fallible=true, start=false)
```

- [ ] **Step 3: Extend `read_source_override()` to start/stop the mic on transition, and degrade `"mikrofoon"` if it fails to become ready**

In `templates/radio.liq`, find the current `read_source_override()`:

```
def read_source_override()
  requested =
    if file.exists(source_override_path) then
      string.trim(file.contents(source_override_path))
    else
      ""
    end
  source_override := (
    if
      requested == "noodmusiek"
      and not emergency_music_raw.is_ready()
      and not sweepers_raw.is_ready()
    then
      ""
    else
      requested
    end
  )
  2.0
end
```

Replace it with:

```
def read_source_override()
  requested =
    if file.exists(source_override_path) then
      string.trim(file.contents(source_override_path))
    else
      ""
    end

  previous = source_override()

  # Begin/stop die mikrofoon net op die oorgang in/uit "mikrofoon" toe
  # (nie elke keer die lus loop nie) - as dit nie dadelik gereed raak
  # nie (mic.is_ready() steeds vals), degradeer die effektiewe
  # oorheersing hieronder na "" en probeer read_source_override() dit
  # weer op die volgende siklus (previous sal dan weer "" wees), wat
  # 'n selfherstellende retry gee eerder as om vas te steek.
  if requested == "mikrofoon" and previous != "mikrofoon" then
    mic.start()
  elsif requested != "mikrofoon" and previous == "mikrofoon" then
    mic.stop()
  end

  source_override := (
    if
      requested == "noodmusiek"
      and not emergency_music_raw.is_ready()
      and not sweepers_raw.is_ready()
    then
      ""
    elsif requested == "mikrofoon" and not mic.is_ready() then
      ""
    else
      requested
    end
  )
  2.0
end
```

- [ ] **Step 4: Add the `"mikrofoon"` predicate to `switch_sources`, at the top**

In `templates/radio.liq`, find:

```
switch_sources =
  [
    ({source_override() == "primer" and radio_connected()}, radio),
    ({source_override() == "noodmusiek"}, backup_program),
    ({source_override() == "" and primary_source == "1" and radio_connected()}, radio),
# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__
    ({true}, backup_program)
  ]
```

Replace it with:

```
switch_sources =
  [
    ({source_override() == "mikrofoon" and mic.is_ready()}, mic),
    ({source_override() == "primer" and radio_connected()}, radio),
    ({source_override() == "noodmusiek"}, backup_program),
    ({source_override() == "" and primary_source == "1" and radio_connected()}, radio),
# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__
    ({true}, backup_program)
  ]
```

(No other change needed near `switch()` itself — `transitions=list.map(fun (pair) -> crossfade, switch_sources)` already covers however many entries `switch_sources` has, including this new one, automatically.)

- [ ] **Step 5: Mirror the new branch in `check_active_source()`**

In `templates/radio.liq`, find:

```
def check_active_source()
  active =
    if source_override() == "primer" and radio_connected() then
      "primer"
    elsif source_override() == "noodmusiek" then
      "noodmusiek"
    elsif source_override() == "" and primary_source == "1" and radio_connected() then
      "primer"
# __ACTIVE_SOURCE_BACKUP_BRANCH__
    else
      "noodmusiek"
    end
```

Replace it with:

```
def check_active_source()
  active =
    if source_override() == "mikrofoon" and mic.is_ready() then
      "mikrofoon"
    elsif source_override() == "primer" and radio_connected() then
      "primer"
    elsif source_override() == "noodmusiek" then
      "noodmusiek"
    elsif source_override() == "" and primary_source == "1" and radio_connected() then
      "primer"
# __ACTIVE_SOURCE_BACKUP_BRANCH__
    else
      "noodmusiek"
    end
```

- [ ] **Step 6: Wire `__MIC_DEVICE__` substitution in `scripts/liquidsoap.sh`**

In `scripts/liquidsoap.sh`, find:

```
sed -i "s|__PRIMARY_SOURCE__|${PRIMARY_SOURCE:-1}|g" "$TARGET_FILE"
```

Add immediately after it:

```

sed -i "s|__MIC_DEVICE__|$(escape_sed_replacement "$MIC_DEVICE")|g" "$TARGET_FILE"
```

- [ ] **Step 7: Syntax-check and lint**

Run:

```bash
bash -n scripts/liquidsoap.sh
shellcheck -x scripts/liquidsoap.sh
```

Expected: no errors. `SC1091` "Not following" info-level notices for `progress.sh`/`environment.conf` are pre-existing and expected on a non-Linux dev machine — not a failure.

- [ ] **Step 8: `liquidsoap --check` with `MIC_DEVICE` unset (must match today's behavior exactly)**

If a Debian/Liquidsoap host is available, copy `templates/radio.liq` there, run it through the same `sed` pipeline `scripts/liquidsoap.sh` uses (with `MIC_DEVICE=""` and all other variables set to realistic values, e.g. `STREAM_URL="https://stream.radio.co/s7adaa782c/listen"`, `MUSIC_WEIGHT=5`, `SWEEPER_WEIGHT=1`, `PLAYLIST_RELOAD=1000`, `PLAYLIST_PREFETCH=10`, `STREAM_BUFFER_MAX=10`, `PRIMARY_SOURCE=1`, `ALSA_DEVICE=default`), then:

```bash
liquidsoap --check /path/to/generated/radio.liq
```

Expected: exit 0, same harmless `Warning 4: Unused variable headers`/`pair` notices as before this task (nothing new).

- [ ] **Step 9: `liquidsoap --check` with `MIC_DEVICE` set to a deliberately non-existent device**

Repeat Step 8 with `MIC_DEVICE="hw:9,0"` (or any device number you're confident doesn't exist on the test host). Expected: exit 0 — declaring `mic` must never fail `--check` regardless of whether the device is real, since `start=false` means it's never opened at check time.

- [ ] **Step 10: Confirm the service itself doesn't crash at boot with a bad `MIC_DEVICE`, and that repeated failed activations don't destabilize it**

On the Debian/Liquidsoap test host, with the real installed service (or a manually-run copy of the generated `radio.liq` piped to a dummy/test ALSA output), with `MIC_DEVICE` set to a non-existent device:

1. Start/restart the service. Confirm it comes up normally (`systemctl status radio-orania.service` shows `active (running)`, no crash-loop).
2. Bypass `radioctl`'s shell-level check for this specific test (it would correctly refuse — that's Task 5) by writing `mikrofoon` directly to `/opt/radio-orania/liquidsoap/source_override` as root, e.g. `echo -n mikrofoon | sudo tee /opt/radio-orania/liquidsoap/source_override`.
3. Watch `sudo journalctl -u radio-orania.service -f` and `active_source`/`source_override` file contents for at least 4 read-cycles (~10 seconds): confirm the service keeps running (no crash), `active_source` never latches on `"mikrofoon"` (since `mic.is_ready()` never becomes true), and it settles into whatever the normal automatic branch is instead (falls through to `"primer"`/`"noodmusiek"` per the existing cascade).
4. Reset the override: `sudo radioctl wissel outomaties`.

This step exists because `.start()` on a bad device is known (from spec-stage investigation) to raise an uncaught Liquidsoap-level error — Step 10 confirms empirically that this doesn't destabilize the whole process even when retried every 2 seconds, which the shell-level check in Task 5 will prevent from happening via the normal `radioctl wissel mikrofoon` path, but the underlying Liquidsoap code must still not misbehave if it's ever reached (e.g. a stale config, a device that vanishes after the shell check passed).

- [ ] **Step 11: Commit**

```bash
git add templates/radio.liq scripts/liquidsoap.sh
git commit -m "$(cat <<'EOF'
Voeg noodmikrofoon-bron by radio.liq (source_override-uitbreiding)

'n Vierde source_override-waarde, "mikrofoon", kry die heel hoogste
prioriteit in switch() en vervang die huidige bron heeltemal. Hergebruik
presies dieselfde lêer/lus-meganisme as "Wissel bron" - read_source_override()
begin/stop nou die mikrofoon op die oorgang in/uit "mikrofoon" toe, en
degradeer terug na outomaties as dit nie gereed raak nie (selfhelend elke
2s, soos die bestaande "noodmusiek"-by-leë-vouers-logika).

start=false + fallible=true op input.alsa() beteken die bron is veilig om
te declareer selfs sonder 'n gekoppelde mikrofoon nie - net 'n eksplisiete
"radioctl wissel mikrofoon" probeer dit werklik oopmaak.

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 2: `radio.liq` — simultaneous headphone monitor output

**Files:**
- Modify: `templates/radio.liq`
- Modify: `scripts/liquidsoap.sh`

**Interfaces:**
- Produces: `headphone_device` (string, from `__HEADPHONE_DEVICE__`); a second `output.alsa(...)` consuming the same `main` the transmitter output already consumes.
- Consumes: `main` (already exists, the fully-processed/normalized signal, right before the existing `output.alsa(device=alsa_device, main)` call).

- [ ] **Step 1: Add the `headphone_device` setting**

In `templates/radio.liq`, right after the `mic_device` line added in Task 1 Step 1, add:

```

# Toestel vir die oorfoon-monitor (bv. "hw:2,0") - leeg beteken
# afgeskakel. Speel altyd presies dieselfde mengsel as wat na die
# sender gaan (gelyktydig, nie 'n alternatief nie).
headphone_device = "__HEADPHONE_DEVICE__"
```

- [ ] **Step 2: Add the second, conditional `output.alsa`**

In `templates/radio.liq`, find:

```
# ALSA uitset

output.alsa(
  device=alsa_device,
  main
)
```

Replace it with:

```
# ALSA uitset

output.alsa(
  device=alsa_device,
  main
)

# Oorfoon-monitor - gelyktydige tweede uitset na 'n aparte toestel, wat
# presies dieselfde main hierbo speel (soos die Icecast-uitset in
# radio-icecast.liq ook 'n tweede, onafhanklike verbruiker van main is).
# headphone_device == "" (verstek) beteken hierdie hele blok word by
# skrip-laai oorgeslaan - geen tweede output.alsa() word dan ooit
# aangevra nie.
if headphone_device != "" then
  output.alsa(
    device=headphone_device,
    main
  )
end
```

- [ ] **Step 3: Wire `__HEADPHONE_DEVICE__` substitution in `scripts/liquidsoap.sh`**

In `scripts/liquidsoap.sh`, find the `__MIC_DEVICE__` line added in Task 1 Step 6, and add immediately after it:

```

sed -i "s|__HEADPHONE_DEVICE__|$(escape_sed_replacement "$HEADPHONE_DEVICE")|g" "$TARGET_FILE"
```

- [ ] **Step 4: Syntax-check and lint**

```bash
bash -n scripts/liquidsoap.sh
shellcheck -x scripts/liquidsoap.sh
```

Expected: no new errors.

- [ ] **Step 5: `liquidsoap --check`, headphone off vs. on**

Same dry-run harness as Task 1 Step 8, twice:

1. `HEADPHONE_DEVICE=""` — expected: exit 0, and the generated file should contain no second `output.alsa` call (confirm with `grep -c 'output.alsa' generated/radio.liq` equals 1).
2. `HEADPHONE_DEVICE="hw:2,0"` (any plausible string — `--check` never opens the device) — expected: exit 0, and `grep -c 'output.alsa' generated/radio.liq` now equals 2.

- [ ] **Step 6: Commit**

```bash
git add templates/radio.liq scripts/liquidsoap.sh
git commit -m "$(cat <<'EOF'
Voeg opsionele gelyktydige oorfoon-monitor-uitset by radio.liq

'n Tweede output.alsa(), na 'n aparte HEADPHONE_DEVICE, wat altyd presies
dieselfde main speel as wat na die sender gaan - dieselfde "een bron, twee
verbruikers"-patroon wat radio-icecast.liq reeds vir die Icecast-relay
gebruik. Leeg (verstek) = heeltemal afgeskakel, geen tweede uitset word
dan aangevra nie.

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 3: `radioctl.sh` — `MIC_DEVICE`/`HEADPHONE_DEVICE` as settable keys

**Files:**
- Modify: `templates/radioctl.sh`

**Interfaces:**
- Consumes: `SETTABLE_KEYS`, `cmd_set()`, `is_valid_plain_text()` (all pre-existing).
- Produces: `radioctl set MIC_DEVICE <toestel>` / `radioctl set HEADPHONE_DEVICE <toestel>`, both applied via the same `scripts/liquidsoap.sh` + service-restart group as `ALSA_DEVICE`.

- [ ] **Step 1: Add the two keys to `SETTABLE_KEYS`**

In `templates/radioctl.sh`, find:

```
SETTABLE_KEYS="STREAM_URL BACKUP_STREAM_URL MUSIC_WEIGHT SWEEPER_WEIGHT ALSA_DEVICE STATION_NAME HEARTBEAT_URL STREAM_BUFFER_MAX PRIMARY_SOURCE"
```

Replace it with:

```
SETTABLE_KEYS="STREAM_URL BACKUP_STREAM_URL MUSIC_WEIGHT SWEEPER_WEIGHT ALSA_DEVICE STATION_NAME HEARTBEAT_URL STREAM_BUFFER_MAX PRIMARY_SOURCE MIC_DEVICE HEADPHONE_DEVICE"
```

- [ ] **Step 2: Add validation for both keys**

In `templates/radioctl.sh`, find the `PRIMARY_SOURCE)` case block inside `cmd_set()` (it ends with its own `;;` right before the `*)` fallback case). Immediately after that block's `;;` and before `*)`, insert:

```
        MIC_DEVICE|HEADPHONE_DEVICE)
            if [ -n "$value" ] && ! is_valid_plain_text "$value"; then
                echo "Ongeldige toestelnaam."
                exit 1
            fi
            ;;
```

- [ ] **Step 3: Add both keys to the liquidsoap-rerun apply-group**

In `templates/radioctl.sh`, find:

```
        STREAM_URL|BACKUP_STREAM_URL|MUSIC_WEIGHT|SWEEPER_WEIGHT|ALSA_DEVICE|STREAM_BUFFER_MAX|PRIMARY_SOURCE)
```

Replace it with:

```
        STREAM_URL|BACKUP_STREAM_URL|MUSIC_WEIGHT|SWEEPER_WEIGHT|ALSA_DEVICE|STREAM_BUFFER_MAX|PRIMARY_SOURCE|MIC_DEVICE|HEADPHONE_DEVICE)
```

- [ ] **Step 4: Add both keys to the `usage()` help text**

In `templates/radioctl.sh`, find:

```
  set <S> <W>    Verander 'n instelling ($SETTABLE_KEYS)
```

Leave that line as-is (it already interpolates `$SETTABLE_KEYS`, which now includes the two new keys automatically) — no change needed here. Skip this step if you find the line already reads correctly; it's listed only so you don't go looking for a second place to edit.

- [ ] **Step 5: Syntax-check and lint**

```bash
bash -n templates/radioctl.sh
shellcheck -x templates/radioctl.sh
```

Expected: no errors.

- [ ] **Step 6: Manual functional check (headless, no root needed for the rejection path)**

```bash
bash -n templates/radioctl.sh && echo "syntax OK"
grep -n 'MIC_DEVICE\|HEADPHONE_DEVICE' templates/radioctl.sh
```

Confirm the `grep` shows: the `SETTABLE_KEYS` line, the new validation case, and the apply-group line — three distinct hits at minimum. If a Debian test host with the installer deployed is available, additionally run `sudo radioctl set MIC_DEVICE "hw:1,0"` and confirm it prints `MIC_DEVICE opgedateer na 'hw:1,0' en toegepas.` and that `grep MIC_DEVICE /opt/radio-orania/config/environment.conf` shows the new value.

- [ ] **Step 7: Commit**

```bash
git add templates/radioctl.sh
git commit -m "$(cat <<'EOF'
Voeg MIC_DEVICE/HEADPHONE_DEVICE by as radioctl set-sleutels

Volg presies dieselfde patroon as ALSA_DEVICE: opsioneel (leeg = af),
gevalideer met is_valid_plain_text(), en herbou radio.liq + herbegin die
diens by verandering (dieselfde toepas-groep as ALSA_DEVICE).

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 4: `radioctl.sh` — `radioctl wissel mikrofoon`

**Files:**
- Modify: `templates/radioctl.sh`

**Interfaces:**
- Consumes: `MIC_DEVICE` (from `load_config`, already called at the top of `cmd_wissel()`), the existing `cmd_wissel()` function and its `case "$choice" in` block.
- Produces: `mic_device_present()` (new shell function), the `mikrofoon` branch of `radioctl wissel`, writing `"mikrofoon"` into the `source_override` file exactly like the existing `1`/`2`/`musiek`/`outomaties` branches do.

- [ ] **Step 1: Confirm `arecord` is available on installed systems**

`arecord` ships in the `alsa-utils` package, same as `aplay` (already used by `templates/radio-dashboard.sh`'s ALSA_DEVICE prompt). Confirm `alsa-utils` is already a dependency:

```bash
grep -n "alsa-utils" scripts/dependencies.sh
```

If it's not listed, add it to the `apt-get install` line in `scripts/dependencies.sh` (find the line starting `apt-get install -y` and add `alsa-utils` to the package list), then re-run `bash -n scripts/dependencies.sh && shellcheck -x scripts/dependencies.sh`. If it's already there (likely, since `aplay` already works today), no change needed — just note that you checked.

- [ ] **Step 2: Add the `mic_device_present()` helper**

In `templates/radioctl.sh`, find the comment block that introduces `cmd_wissel()`:

```
# --- BEHEER-oortjie: handmatige bron-wissel -----------------------------
#
```

Immediately before that comment block, insert:

```
# Kontroleer of 'n ALSA-toestelnaam werklik as 'n opname-toestel
# verskyn - net vir die algemeenste vorms ("hw:N,..."/"plughw:N,...").
# Ander vorms (bv. "default") kan nie vooraf geverifieer word sonder om
# dit oop te maak nie, so word vertrou, soos ALSA_DEVICE ook vertrou
# word.
mic_device_present() {
    local dev="$1" card
    case "$dev" in
        hw:*|plughw:*)
            card="${dev#*:}"
            card="${card%%,*}"
            arecord -l 2>/dev/null | grep -q "^card ${card}:"
            ;;
        *)
            return 0
            ;;
    esac
}

```

- [ ] **Step 3: Add the `mikrofoon` branch to `cmd_wissel()`**

In `templates/radioctl.sh`, find:

```
        musiek)
            val="noodmusiek"
            label="Musiek"
            ;;
```

Replace it with:

```
        musiek)
            val="noodmusiek"
            label="Musiek"
            ;;
        mikrofoon)
            if [ -z "${MIC_DEVICE:-}" ]; then
                echo "Geen mikrofoon-toestel ingestel nie (INSTELLINGS)."
                exit 1
            fi
            if ! command -v arecord >/dev/null 2>&1; then
                echo "arecord nie beskikbaar nie - kan nie mikrofoon-toestel bevestig nie."
                exit 1
            fi
            if ! mic_device_present "$MIC_DEVICE"; then
                echo "Mikrofoon-toestel '$MIC_DEVICE' nie tans gekoppel/sigbaar nie (arecord -l)."
                exit 1
            fi
            val="mikrofoon"
            label="Noodmikrofoon"
            ;;
```

- [ ] **Step 4: Update `cmd_wissel()`'s usage message and `usage()` help text**

In `templates/radioctl.sh`, find (inside `cmd_wissel()`):

```
        *)
            echo "Gebruik: radioctl wissel <1|2|musiek|outomaties>"
            exit 1
            ;;
```

Replace it with:

```
        *)
            echo "Gebruik: radioctl wissel <1|2|musiek|mikrofoon|outomaties>"
            exit 1
            ;;
```

Then find, in `usage()`:

```
  wissel <T>     Wissel bron: 1, 2, musiek, of outomaties (tydelik)
```

Replace it with:

```
  wissel <T>     Wissel bron: 1, 2, musiek, mikrofoon, of outomaties (tydelik)
```

- [ ] **Step 5: Syntax-check and lint**

```bash
bash -n templates/radioctl.sh
shellcheck -x templates/radioctl.sh
```

Expected: no errors.

- [ ] **Step 6: Manual functional check**

Without root or a real device, confirm the rejection paths work (these don't touch the system, safe to run anywhere `bash` exists — but `templates/radioctl.sh` hardcodes `/opt/radio-orania` paths and calls `need_root`, so this specific check needs either the Debian test host or a local stub; skip to the Debian-host version if you have one):

On a Debian/Liquidsoap test host with the installer already deployed and `MIC_DEVICE` unset:

```bash
sudo radioctl wissel mikrofoon
```

Expected: `Geen mikrofoon-toestel ingestel nie (INSTELLINGS).` and exit 1 — confirm with `echo $?`.

Then:

```bash
sudo radioctl set MIC_DEVICE "hw:9,0"
sudo radioctl wissel mikrofoon
```

Expected (assuming card 9 doesn't exist on the test host): `Mikrofoon-toestel 'hw:9,0' nie tans gekoppel/sigbaar nie (arecord -l).` and exit 1. Confirm `cat /opt/radio-orania/liquidsoap/source_override` still shows the previous value (unchanged — the rejected command must never write to the override file).

If the test host has a real capture device (check with `arecord -l` yourself first), repeat with `MIC_DEVICE` set to that device's real `hw:N,M` string and confirm `radioctl wissel mikrofoon` succeeds, prints `Bron gewissel na: Noodmikrofoon`, and that `active_source` becomes `mikrofoon` within a couple of seconds (per Task 1's mechanism) — then `sudo radioctl wissel outomaties` to revert.

- [ ] **Step 7: Commit**

```bash
git add templates/radioctl.sh scripts/dependencies.sh
git commit -m "$(cat <<'EOF'
Voeg 'radioctl wissel mikrofoon' by, met vooraf-toestelkontrole

Hergebruik die bestaande "Wissel bron"-lêermeganisme (source_override)
vir 'n vierde waarde, "mikrofoon". mic_device_present() kontroleer via
arecord -l dat die gekonfigureerde toestel werklik as 'n opname-toestel
verskyn VOOR die oorheersing geskryf word - Liquidsoap word dus nooit
gevra om 'n toestel te begin wat nie bestaan nie (sien Task 1: 'n
mislukte mic.start() gooi 'n fout wat nie hier voorkom moet word nie).

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 5: dashboard — INSTELLINGS items for `MIC_DEVICE`/`HEADPHONE_DEVICE`

**Files:**
- Modify: `templates/radio-dashboard.sh`

**Interfaces:**
- Consumes: `handle_instellings_item()`, `draw_instellings_tab()`, `inline_prompt()` (all pre-existing), `radioctl set MIC_DEVICE`/`radioctl set HEADPHONE_DEVICE` (from Task 3).

- [ ] **Step 1: Add items 9 and 10 to `handle_instellings_item()`**

In `templates/radio-dashboard.sh`, find:

```
        7)
            inline_prompt "Maksimum stroom-buffer in sekondes: " val
            STATUS_MSG=$(sudo radioctl set STREAM_BUFFER_MAX "$val" 2>&1)
            ;;
        8)
            inline_prompt "Primêre bron (1 of 2): " val
            STATUS_MSG=$(sudo radioctl set PRIMARY_SOURCE "$val" 2>&1)
            ;;
```

Replace it with:

```
        7)
            inline_prompt "Maksimum stroom-buffer in sekondes: " val
            STATUS_MSG=$(sudo radioctl set STREAM_BUFFER_MAX "$val" 2>&1)
            ;;
        8)
            inline_prompt "Primêre bron (1 of 2): " val
            STATUS_MSG=$(sudo radioctl set PRIMARY_SOURCE "$val" 2>&1)
            ;;
        9)
            printf '%s' "$SHOW_CURSOR"
            echo
            command -v arecord >/dev/null 2>&1 && arecord -l 2>/dev/null
            echo
            printf 'Mikrofoon-toestel (bv. hw:1,0; leeg om af te skakel): '
            read -r val
            printf '%s' "$HIDE_CURSOR"
            STATUS_MSG=$(sudo radioctl set MIC_DEVICE "$val" 2>&1)
            ;;
        10)
            printf '%s' "$SHOW_CURSOR"
            echo
            command -v aplay >/dev/null 2>&1 && aplay -l 2>/dev/null
            echo
            printf 'Oorfone-toestel (bv. hw:2,0; leeg om af te skakel): '
            read -r val
            printf '%s' "$HIDE_CURSOR"
            STATUS_MSG=$(sudo radioctl set HEADPHONE_DEVICE "$val" 2>&1)
            ;;
```

- [ ] **Step 2: Add both items to `draw_instellings_tab()`**

In `templates/radio-dashboard.sh`, find:

```
    local items=(
        "1) Stroom URL (primêr)" "2) Rugsteun-stroom URL"
        "3) Musiek/sweeper-verhouding" "4) Stasienaam"
        "5) ALSA-klanktoestel" "6) Heartbeat URL"
        "7) Maksimum stroom-buffer" "8) Primêre bron"
    )
```

Replace it with:

```
    local items=(
        "1) Stroom URL (primêr)" "2) Rugsteun-stroom URL"
        "3) Musiek/sweeper-verhouding" "4) Stasienaam"
        "5) ALSA-klanktoestel" "6) Heartbeat URL"
        "7) Maksimum stroom-buffer" "8) Primêre bron"
        "9) Mikrofoon-toestel" "10) Oorfone-toestel"
    )
```

- [ ] **Step 3: Syntax-check and lint**

```bash
bash -n templates/radio-dashboard.sh
shellcheck -x templates/radio-dashboard.sh
```

Expected: no new errors (pre-existing `SC1003`/`SC2005` notices elsewhere in the file are unrelated and expected).

- [ ] **Step 4: Headless functional check**

Follow this project's documented pattern (per `CLAUDE.md`): stub `sudo`/`radioctl`/`systemctl` as fake executables on `PATH`, pipe keystrokes into stdin, and confirm:

1. Navigating to the INSTELLINGS tab shows items 9 and 10 in the grid.
2. Typing `9`, Enter shows the (stubbed, empty) `arecord -l` output, prompts for a device string, and calls the stubbed `radioctl set MIC_DEVICE <what you typed>`.
3. Typing `10`, Enter shows the (stubbed, empty) `aplay -l` output, prompts, and calls the stubbed `radioctl set HEADPHONE_DEVICE <what you typed>`.

- [ ] **Step 5: Commit**

```bash
git add templates/radio-dashboard.sh
git commit -m "$(cat <<'EOF'
Voeg Mikrofoon-toestel/Oorfone-toestel by INSTELLINGS-oortjie

Volg presies dieselfde patroon as ALSA-klanktoestel: wys beskikbare
toestelle (arecord -l / aplay -l) voor die admin tik.

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 6: dashboard — BEHEER toggle for the emergency mic

**Files:**
- Modify: `templates/radio-dashboard.sh`

**Interfaces:**
- Consumes: `handle_beheer_item()`, `draw_beheer_tab()` (pre-existing), `radioctl wissel mikrofoon`/`radioctl wissel outomaties` (from Task 4), `active_source` file (`/opt/radio-orania/liquidsoap/active_source`, already read elsewhere in the dashboard for the STATUS card).

- [ ] **Step 1: Add the toggle item to `handle_beheer_item()`**

In `templates/radio-dashboard.sh`, find:

```
        5)
            local val
            inline_prompt "Wissel na (1/2/M=Musiek/A=Outomaties): " val
            case "$val" in
                [Mm]*) val="musiek" ;;
                [Aa]*|"") val="outomaties" ;;
            esac
            STATUS_MSG=$(sudo radioctl wissel "$val" 2>&1)
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- INLIGTING-oortjie
```

Replace it with:

```
        5)
            local val
            inline_prompt "Wissel na (1/2/M=Musiek/A=Outomaties): " val
            case "$val" in
                [Mm]*) val="musiek" ;;
                [Aa]*|"") val="outomaties" ;;
            esac
            STATUS_MSG=$(sudo radioctl wissel "$val" 2>&1)
            ;;
        6)
            local current_source
            current_source=$(cat /opt/radio-orania/liquidsoap/active_source 2>/dev/null || echo "")
            if [ "$current_source" = "mikrofoon" ]; then
                STATUS_MSG=$(sudo radioctl wissel outomaties 2>&1)
            else
                STATUS_MSG=$(sudo radioctl wissel mikrofoon 2>&1)
            fi
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- INLIGTING-oortjie
```

- [ ] **Step 2: Add the toggle label to `draw_beheer_tab()`**

In `templates/radio-dashboard.sh`, find:

```
draw_beheer_tab() {
    local listen_item
    if [ "$PLAYING" = true ]; then
        listen_item="4) Monitor Af"
    else
        listen_item="4) Monitor Aan"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items=(
        "1) Begin" "2) Stop" "3) Herbegin" "$listen_item" "5) Wissel bron"
    )
    print_command_grid items items "$sep_width"
}
```

Replace it with:

```
draw_beheer_tab() {
    local listen_item mic_item current_source
    if [ "$PLAYING" = true ]; then
        listen_item="4) Monitor Af"
    else
        listen_item="4) Monitor Aan"
    fi

    current_source=$(cat /opt/radio-orania/liquidsoap/active_source 2>/dev/null || echo "")
    if [ "$current_source" = "mikrofoon" ]; then
        mic_item="6) Noodmikrofoon Af"
    else
        mic_item="6) Noodmikrofoon Aan"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items=(
        "1) Begin" "2) Stop" "3) Herbegin" "$listen_item" "5) Wissel bron" "$mic_item"
    )
    print_command_grid items items "$sep_width"
}
```

- [ ] **Step 3: Syntax-check and lint**

```bash
bash -n templates/radio-dashboard.sh
shellcheck -x templates/radio-dashboard.sh
```

Expected: no new errors.

- [ ] **Step 4: Headless functional check**

Same stubbing approach as Task 5 Step 4:

1. BEHEER tab shows `6) Noodmikrofoon Aan` when the stubbed `active_source` file doesn't contain `mikrofoon`.
2. Typing `6`, Enter calls the stubbed `radioctl wissel mikrofoon`.
3. With the stubbed `active_source` file changed to contain `mikrofoon`, redrawing BEHEER shows `6) Noodmikrofoon Af` instead, and typing `6` now calls `radioctl wissel outomaties`.

- [ ] **Step 5: Commit**

```bash
git add templates/radio-dashboard.sh
git commit -m "$(cat <<'EOF'
Voeg 'Noodmikrofoon aan/af'-wisselaar by BEHEER-oortjie

Etiket wissel self na "af" sodra active_source "mikrofoon" wys - soos
die bestaande Monitor Aan/Af-toggle. Roep radioctl wissel mikrofoon/
outomaties, wat reeds (Task 4) die toestel se bestaan vooraf nagaan.

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

### Task 7: Docs + end-to-end verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- None (documentation + verification only; no new code interfaces).

- [ ] **Step 1: Update the `radioctl` command reference in `README.md`**

In `README.md`, find:

```
radioctl set <S> <W>          Verander 'n instelling (STREAM_URL, BACKUP_STREAM_URL,
                              MUSIC_WEIGHT, SWEEPER_WEIGHT, ALSA_DEVICE, STATION_NAME,
                              HEARTBEAT_URL, STREAM_BUFFER_MAX)
```

Replace it with:

```
radioctl set <S> <W>          Verander 'n instelling (STREAM_URL, BACKUP_STREAM_URL,
                              MUSIC_WEIGHT, SWEEPER_WEIGHT, ALSA_DEVICE, STATION_NAME,
                              HEARTBEAT_URL, STREAM_BUFFER_MAX, PRIMARY_SOURCE,
                              MIC_DEVICE, HEADPHONE_DEVICE)
radioctl wissel <T>           Wissel bron: 1, 2, musiek, mikrofoon, of outomaties (tydelik)
```

(This also backfills `PRIMARY_SOURCE` and `radioctl wissel`, which were added earlier this session but never made it into `README.md` — worth fixing here since you're already touching this exact block.)

- [ ] **Step 2: Update the tab summary in `README.md`**

In `README.md`, find:

```
* **BEHEER** (verstek) — Begin, Stop, Herbegin, Monitor aan/af
* **INLIGTING** — stelsel-syfers (buffer, data, CPU, geheue, temperatuur), Logs, Media
* **INSTELLINGS** — stroom URL's, stasienaam, ALSA-toestel, musiek/sweeper-verhouding, Heartbeat URL, stroom-buffer
```

Replace it with:

```
* **BEHEER** (verstek) — Begin, Stop, Herbegin, Monitor aan/af, Wissel bron, Noodmikrofoon aan/af
* **INLIGTING** — stelsel-syfers (buffer, data, CPU, geheue, temperatuur), Logs, Media
* **INSTELLINGS** — stroom URL's, stasienaam, ALSA-toestel, musiek/sweeper-verhouding, Heartbeat URL, stroom-buffer, primêre bron, mikrofoon-/oorfone-toestel
```

- [ ] **Step 3: Full end-to-end verification (requires a Debian/Liquidsoap test host)**

With all six prior tasks' changes deployed to a real test host (copy the changed `templates/`/`scripts/` files into `/opt/radio-orania/installer/`, then `sudo bash scripts/liquidsoap.sh` + `sudo systemctl restart radio-orania.service`, exactly as done repeatedly earlier this session):

1. `MIC_DEVICE`/`HEADPHONE_DEVICE` both unset (default): confirm `sudo radioctl status` and normal broadcast behavior are byte-for-byte unchanged from before this feature — no regression for installs that never touch these settings.
2. Set `HEADPHONE_DEVICE` to a plausible-but-fake device string, confirm the service still starts (the second `output.alsa` will fail loudly in logs if the device is genuinely invalid at open-time, since `output.alsa` doesn't have the same `fallible`/`start=false` safety as `input.alsa` — if this happens, note it in the task's written report as a follow-up, since the spec didn't originally call for the headphone output to be forgiving of a bad device the way the mic input is; don't silently patch around it without flagging it).
3. If a real capture device is available: full `radioctl wissel mikrofoon` → confirm on-air source switches (via `active_source` and, if possible, actually listening) → `radioctl wissel outomaties` → confirm it reverts.
4. Re-run every `TOETS`-tab fault-simulation command (`test-source-stop/-start`, `test-internet-block/-restore`) once more to confirm none of this session's changes regressed them.
5. Sync the test host's installer checkout to the final pushed commit (`git fetch && git reset --hard origin/main`) once everything is confirmed, matching the pattern used throughout this session.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
Dokumenteer noodmikrofoon en oorfoon-monitor in README

Ook: voeg die vroeër-bygevoegde PRIMARY_SOURCE-sleutel en 'radioctl
wissel' by die opdraglys, wat by daardie vorige werk uitgelaat is.

Spec: docs/superpowers/specs/2026-09-10-emergency-mic-headphone-monitor-design.md
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage**: mic override (Tasks 1, 4, 6), headphone monitor (Tasks 2, 5 partial), device settings + validation (Tasks 3, 4, 5), docs (Task 7) — every section of the spec has a task. The spec's "Open items" are resolved inline: the Liquidsoap `try`/`catch` question is resolved by *not* needing it (shell-level `mic_device_present()` is the real guard; Task 1 Step 10 empirically confirms the unguarded Liquidsoap-side failure doesn't crash the process, so no belt-and-braces catch was added — simpler than the spec anticipated). The headphone insert-marker-vs-inline-`if` question is resolved in favor of the simple inline `if` (Task 2 Step 2).
- **Placeholder scan**: every step above has literal, complete code — no "add error handling" or "similar to Task N" placeholders.
- **Type/name consistency**: `mic_device_present()` (Task 4) takes one positional arg (`$1`) and is a boolean-via-exit-status shell function, called as `mic_device_present "$MIC_DEVICE"` — consistent everywhere it's referenced. `mic` (Liquidsoap source, Task 1) is referenced identically in `switch_sources` and `check_active_source()`. `active_source` file content value `"mikrofoon"` (Liquidsoap side, Task 1) matches the literal string compared against in the dashboard's Task 6 toggle (`current_source = "mikrofoon"`) and in `radioctl wissel mikrofoon`'s `val="mikrofoon"` (Task 4) — all three must stay byte-identical since they're just string comparisons across process boundaries (no shared constant to enforce this at the language level, so double-check this specific string literal if you touch any of the three later).
