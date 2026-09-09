---
status: accepted
---

# Dashboard navigation: single screen, arrow-switched tabs, numbered per-tab menus

The beheerpaneel-skerm (`templates/radio-dashboard.sh`) needed a way to organize BEHEER, INSTELLINGS, and GEVAARLIK actions without hiding any of them behind a screen swap. We settled on one continuously-visible screen (STATUS always shown) with mutually-exclusive tabs switched only by ◄/► arrow keys, where every tab's options are a numbered list restarting at 1 per tab (select by typing the number + Enter) — including BEHEER's own actions (Begin/Stop/Herbegin/etc.), which previously were instant single-letter keys.

This was the third iteration of the dashboard's settings UI in one session; the first two were each rejected as still being a hidden "sub-menu" from the user's perspective. Recorded here so a future session doesn't re-litigate the same ground.

## Considered Options

- **Mode-swap settings screen** (original design): `[C]` replaced STATUS/OPDRAGTE entirely with a tabbed sub-screen. Rejected: hides the main status/actions while browsing settings.
- **Collapsible `[I]`/`[G]` toggle sections on the main screen**: both sections independently expandable, no mutual exclusion, no tab bar. Rejected: still functions as a hidden sub-menu — content isn't visible until a key reveals it, which is exactly what the user meant by "no sub-menus."
- **Direct letter-jump to each tab** (e.g. `[R]`/`[I]`/`[G]`): rejected because `[R]` already means "Herbegin" inside the BEHEER tab's own numbered list. Arrows-only avoids the collision and keeps one consistent navigation model.
- **Keep BEHEER's actions as instant single-letter keys**, with only INSTELLINGS/GEVAARLIK numbered: rejected in favor of consistency — every tab behaves the same way (type a number, press Enter).
- **Global numbering across all tabs** (the previous 1–12 scheme, with gaps): rejected — numbers now restart at 1 per tab, since only one tab's list is visible at a time.

## Consequences

- BEHEER's actions lose their instant single-keypress behavior: Begin/Stop/Herbegin/etc. now require typing a number and pressing Enter, same as INSTELLINGS/GEVAARLIK.
- `[Q]` Verlaat na shell is the only action that stays a standing, always-accessible letter key — it isn't part of any tab's numbered list, since it must work regardless of which tab is active.
- GEVAARLIK is reached the same way as any other tab, with no extra confirm-to-open step; the destructive items inside it (uninstall) keep their own per-action Y/N confirmation.

## Update: INLIGTING tab (STELSEL moved off the always-visible area)

Two tabs were added after this ADR was first written, both following the same rules above (arrows-only, numbered from 1, no extra gate):

- **TOETS** — fault-injection tests (simulated source/internet loss, service-crash, heartbeat, soundcard). Added alongside the original three tabs.
- **INLIGTING** — added later to hold STELSEL (network buffer, data usage, CPU/memory/temperature) plus Logs (moved off BEHEER). STELSEL was originally specified as always-visible under STATUS regardless of active tab (see the original paragraph above); the user later asked for it to move into its own tab together with Logs instead, so it no longer falls under the "always visible" rule — `update_stelsel_body()` in the dashboard now only runs while INLIGTING is the active tab.

Current tab order (before the ONDERHOUD split below): BEHEER (default) → INLIGTING → INSTELLINGS → GEVAARLIK → TOETS.

## Update: ONDERHOUD tab (category-fit cleanup)

An audit of every dashboard item against its tab found four items that didn't match their tab's category, purely by function rather than history:

- **Media** (BEHEER → INLIGTING): it's a read-only display (File Browser credentials), not a live-broadcast control action like Begin/Stop/Herbegin/Monitor.
- **Rugsteun**, **Opdateer sagteware**, **Herkonfigureer**, **Kleurskema** (previously split across BEHEER and INSTELLINGS → all four now in a new **ONDERHOUD** tab): none of these are live-broadcast control, and none map to a single `radioctl set <SLEUTEL>` value the way every other INSTELLINGS item does — Kleurskema in particular never touches `environment.conf` or the radio service at all, it only writes `~/.radio-dashboard-colors` for the `radio-admin` user. Grouping them separately keeps INSTELLINGS as "change one config key" and BEHEER as "control the live broadcast," with ONDERHOUD as "maintain the system/panel."

**Wagwoorde wys stays in GEVAARLIK** despite being a read-only display like Media, not moved to INLIGTING — this was a deliberate call, not an oversight: GEVAARLIK may gain more genuinely destructive actions later, and the user wants credentials display kept alongside them rather than mixed into the general-purpose INLIGTING tab.

Current tab order: BEHEER (default) → INLIGTING → INSTELLINGS → ONDERHOUD → GEVAARLIK → TOETS.
