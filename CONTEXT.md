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

- 2026-11-17: Op sender (main 35bda96): watchdog sonder `nmcli up` (modem is elke 5s afgesny), 2 toets-teikens, ou 10-gsm-only.conf weg, monitor buffer.adaptative, ALSA buffer_size=0.5 (proefloop-sed reggemaak). Alles werk, 0 underruns.
- Modem (ZTE 19d2:1405, API http://192.168.0.1/goform/goform_get_cmd_process, Referer-kop, geen wagwoord): `modem_sim_undetected` sedert ~24 Mrt. Schalk moet SIM fisies nagaan.
- Oop: NetBird bestuur /etc/resolv.conf (DNS-afhanklikheid) - net met Schalk se go op sender.
- Argitektuurverslag (scratchpad architecture-review-20261117.html): foute (1) rugsteunlyn nooit getoets, (2) watchdog begin met aanname primêr werk, (3) "connected" != bruikbaar, (4) dashboard skraap status-teks, (5) ntfy-tou verlore by herbegin.
- Klaar (gecommit, nog nie gepush/ontplooi nie): foute 1-4 reggemaak. Watchdog toets albei lyne, begin uit werklike toets, lees ZTE-modem, skryf `/opt/radio-orania/network/status` (sleutel=waarde); `radioctl status --kv` + `radioctl modem`; dashboard Modem-kaartjie; ntfy as rugsteunlyn afgaan. VM-getoets (6 scenario's, regte roetes). Fout 5 gelos.
- Volgende: push + `radioctl update` op sender net met Schalk se go (herbegin watchdog en notify).
