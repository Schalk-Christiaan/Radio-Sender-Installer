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
The dashboard tab holding fault-injection tests (simulated source/internet loss, a service-crash test, heartbeat and soundcard checks) used to verify failover behavior without a real outage.

**Aktiewe Bron** (active source):
Whichever of the primary stream, backup stream, or local noodmusiek is actually on-air at a given moment, as tracked by `active_source` and reported by `radioctl status`. Distinct from which sources are merely *configured*.

**Noodmusiek**:
The local music/sweeper fallback that plays when both the primary and (if configured) backup streams are unreachable or silent.
