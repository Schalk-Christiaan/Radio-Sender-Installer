---
status: accepted
---

# Dashboard navigation: single screen, arrow-switched tabs, numbered per-tab menus

The beheerpaneel-skerm (`templates/radio-dashboard.sh`) needed a way to organize RADIO/BEHEER, INSTELLINGS, and GEVAARLIK actions without hiding any of them behind a screen swap. We settled on one continuously-visible screen (STATUS + STELSEL always shown) with three mutually-exclusive tabs switched only by ◄/► arrow keys, where every tab's options are a numbered list restarting at 1 per tab (select by typing the number + Enter) — including RADIO/BEHEER's own actions (Begin/Stop/Herbegin/etc.), which previously were instant single-letter keys.

This was the third iteration of the dashboard's settings UI in one session; the first two were each rejected as still being a hidden "sub-menu" from the user's perspective. Recorded here so a future session doesn't re-litigate the same ground.

## Considered Options

- **Mode-swap settings screen** (original design): `[C]` replaced STATUS/OPDRAGTE entirely with a tabbed sub-screen. Rejected: hides the main status/actions while browsing settings.
- **Collapsible `[I]`/`[G]` toggle sections on the main screen**: both sections independently expandable, no mutual exclusion, no tab bar. Rejected: still functions as a hidden sub-menu — content isn't visible until a key reveals it, which is exactly what the user meant by "no sub-menus."
- **Direct letter-jump to each tab** (e.g. `[R]`/`[I]`/`[G]`): rejected because `[R]` already means "Herbegin" inside the RADIO/BEHEER tab's own numbered list. Arrows-only avoids the collision and keeps one consistent navigation model.
- **Keep RADIO/BEHEER's actions as instant single-letter keys**, with only INSTELLINGS/GEVAARLIK numbered: rejected in favor of consistency — every tab behaves the same way (type a number, press Enter).
- **Global numbering across all tabs** (the previous 1–12 scheme, with gaps): rejected — numbers now restart at 1 per tab, since only one tab's list is visible at a time.

## Consequences

- RADIO/BEHEER's actions lose their instant single-keypress behavior: Begin/Stop/Herbegin/etc. now require typing a number and pressing Enter, same as INSTELLINGS/GEVAARLIK.
- `[Q]` Verlaat na shell is the only action that stays a standing, always-accessible letter key — it isn't part of any tab's numbered list, since it must work regardless of which tab is active.
- GEVAARLIK is reached the same way as any other tab, with no extra confirm-to-open step; the destructive items inside it (uninstall) keep their own per-action Y/N confirmation.
