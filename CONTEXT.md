# Radio Orania Sender Installer

An installer and control panel for an unattended Debian radio-to-FM sender. This glossary covers terms specific to the project's own vocabulary — general programming or Linux concepts don't belong here.

## Language

**Beheerpaneel-skerm** (dashboard):
The optional full-screen, auto-refreshing terminal UI (`templates/radio-dashboard.sh`) that appears on login for the `radio-admin` user, either via SSH or the physical console.
_Avoid_: TUI, control panel screen (in English contexts, keep the Afrikaans term — it's what the code and README use).

**BEHEER** (dashboard tab):
The dashboard tab holding the day-to-day radio actions — Begin, Stop, Herbegin, Monitor, Media, Rugsteun. The default tab shown when the dashboard opens.
_Avoid_: RADIO/BEHEER (an earlier working name; the shipped tab label is just BEHEER).

**INLIGTING** (dashboard tab):
The dashboard tab holding live system readouts (network buffer, data usage, CPU load, memory, temperature — collectively "STELSEL") plus Logs.

**INSTELLINGS** (dashboard tab):
The dashboard tab holding configuration changes — stream URLs, station name, ALSA device, buffer size, color scheme, software updates.
_Avoid_: Settings (in English contexts, keep the Afrikaans term).

**GEVAARLIK** (dashboard tab):
The dashboard tab holding destructive/sensitive actions — revealing stored passwords, uninstalling the whole installation. Reached the same way as any other tab, with no extra gate; the actions inside it each keep their own confirmation prompt.

**STELSEL**:
The live system readouts (network buffer, data usage, CPU load, memory, temperature) shown on the INLIGTING dashboard tab. Not a tab itself, and not always-visible — it only refreshes while INLIGTING is the active tab.

**TOETS** (dashboard tab):
The dashboard tab holding fault-injection tests (simulated source/internet loss, a service-crash test, ntfy-notification and soundcard checks) used to verify failover behavior without a real outage.

**Aktiewe Bron** (active source):
Whichever of the primary stream, backup stream, or local noodmusiek is actually on-air at a given moment, as tracked by `active_source` and reported by `radioctl status`. Distinct from which sources are merely *configured*.

**Noodmusiek**:
The local music/sweeper fallback that plays when both the primary and (if configured) backup streams are unreachable or silent.

## Status

- 2026-11-12: Ongecommit op `main`: (1) konsole-glyphs, `buffer.adaptative`/`plughw:`/Icecast-klok/`Nice=-10`, veilige `liquidsoap.sh` (`LIQ_CHECK_ONLY=1`). (2) Installer-opknapping: `scripts/ui.sh`, `setup.sh` 5 afdelings + stroomtoets + klankkaart-name/toetstoon, Orania-kleur logo. (3) Uit VM-logs: `validation.sh` ALSA-tjek vals (aplay -L vs hw:N,M) reg; diens kry `CacheDirectory` (Liquidsoap-kas, 3.6s->2.9s herbegin).
- (4) Stres-toets in VM (praatprogram met 3-14s pouses + jitter/verlies/100kbit/onderbrekings 5-45s/flikker): blank.strip nou BUITE buffer.adaptative, `buffer=max/2` voorbuffer, verstekke SILENCE_THRESHOLD 8->20, STREAM_BUFFER_MAX 10->20. Wissels 80->18, bronveranderinge 62->8; 5s-onderbreking, flikker en 100kbit bereik nie meer die lug nie.
- Herbegin ~15s noodmusiek (voorbuffer) aanvaar deur Schalk. Toonhoogte: `limit=1.01`, `averaging=120.` op buffer.adaptative; gemeet met 12kHz-loodstoon (`toets/spoed.py`): maks 1.02% (was tot 25% toegelaat). Prys: na stadige internet 1 sprong (~101 rame weg) i.p.v. toonskuif.
- Toetsharnas: scratchpad `toets/run.sh` (VM `~/toets/run.sh`, logs `~/toets/logs/laaste`); toetsmedia in VM `/opt/radio-orania/media`.
- Lewendige sender nie aangeraak nie.
- Volgende: Schalk besluit oor herbegin-afweging en keur goed; dan commit na tak `klank-en-lettertipe`, `LIQ_CHECK_ONLY=1` op sender, oorskakel.
