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

- 2026-11-12: Tak `pre-release` gepush (5f6c3e7 klank/installer/README-diagram, d6d1c1a environment.conf altyd na /opt). Skoon installasie in VM OK. Op die lewendige sender geïnstalleer deur Schalk (stap 3) ~12:33.
- Klank: blank.strip buite buffer.adaptative, voorbuffer max/2, `limit=1.01`/`averaging=120.` (maks 1.02% spoed gemeet), verstekke SILENCE_THRESHOLD/STREAM_BUFFER_MAX 20. VM-harnas: scratchpad `toets/run.sh` + `toets/spoed.py`.
- Lugvoorval 11 Nov 21:15-21:25 BEVESTIG uit sender-joernaal (~/Downloads/radio-nag.log): ou kode, stroom te stadig (catchup ~4.3s elke sekonde 19-21h, geen verbindingsfout), buffer leeg -> noodmusiek -> 1-3s later terug, 124 wissels/uur; elke wissel begin 'n nuwe noodmusiek-snit. Presies VM-fase C, wat nuwe kode oorbrug. Ook ~80 ALSA underruns/uur heelnag (ou kode) -> sterk saak vir buffer_size=0.5.
- Oop vermoede: crossfade `fade.out` vervaag net aan die einde van 'n snit -> ou bron kan by wissel vol volume onder nuwe bly. Twee-toon-toets in VM `/tmp/xf.liq` -> `/tmp/xf.wav` gedraai, NOG NIE ontleed nie.
- 2026-11-16: Naweek-joernaal (14-15 Nov, nuwe kode) ontleed: 15 wissels in 48h (was 124/uur), ~24 ALSA underruns/uur (was ~80). Stroomfoute = radio.co (timeouts, 1x 403/404). Sender het nog `STREAM_BUFFER_MAX=10` (ou env). Sweepers-vouer leeg -> `Fetch failed` elke reload, onskadelik. Dashboard-sudo het ~118k joernaalreëls/dag gelog.
- Gedoen in repo: `output.alsa(buffer_size=0.5)` (`liquidsoap --check` op sender OK); sudoers `!syslog, !pam_session` vir radio-admin. Nog NIE op sender nie (lewendig) - plan: stage sonder herbegin, 06:00-herbegin tel dit op.
- Valstrik: as `/opt/radio-orania/installer/.git` bestaan, herstel persist_installer dit na main - geen `radioctl set` tot merge nie.
- TODO (Schalk wag eers): (a) `output.alsa(buffer_size=0.5)` teen underruns - eers 13 Nov se joernaal (nuwe kode) vergelyk: underruns/uur, wissels, catchup. (b) Crossfade-toets: VM radio-toets is 12 Nov geskrap; nuwe VM uit ~/VMs/debian-13-generic-amd64.qcow2, draai twee-toon-switch (fade.out vs onmiddellike vervaag) en meet. (c) Merge `pre-release` na main na goedkeuring.
- Volgende: Schalk trek 13 Nov sender-logs (`netbird ssh root@100.117.206.117 'journalctl -u radio-orania --since ... --no-pager' > ~/Downloads/radio-<datum>.log`); vergelyk met ~/Downloads/radio-nag.log.
