# AltArmy TBC — Summary Tab

This document describes the **Summary** tab in detail: purpose, layout, columns, filters, and actions.

---

## 1. Purpose

The Summary tab shows **all characters** (optionally filtered by realm, faction, level, class, profession) in a single table. Initially there is **one summary view** (no mode switcher). The table displays a fixed set of columns so the user can see levels, money, rest XP, played time, and similar at a glance.

---

## 2. Layout

- **Top**: Filter icons or controls (realm, faction, level, class, profession) so the user can narrow which characters appear.
- **Main area**: A **single table** of characters (and realms, if multi-realm).
  - One row per character (or realm header row with character rows beneath, depending on design).
  - Columns are defined by the single summary view (see §3).
- **Bottom** (optional): Totals row (e.g. total gold, total levels) and an expand/collapse control (e.g. “ALL”) for realm/character grouping.

No left menu or mode switcher in the initial version — only this one summary view.

---

## 3. Summary View — Columns

The single summary view shows a table with columns such as:

| Column       | Description                          |
|-------------|--------------------------------------|
| Name        | Character name                       |
| Realm       | Realm (if multi-realm)               |
| Level       | Character level                      |
| Class       | Class (and optionally spec)          |
| Money       | Gold (or copper) on that character   |
| Rest XP     | Rest state / amount                  |
| Played      | Time played                          |
| Profession 1| First profession name + skill level  |
| Profession 2| Second profession name + skill level |

Additional columns (e.g. AiL, last login) can be added later. Profession columns use **skill level only** (no recipe counts or cooldowns).

- **Sorting**: User can sort by column (click header); ascending/descending toggles.
- **Totals row**: Optional row at bottom showing totals (e.g. total gold, total levels) for visible characters.

---

## 4. Filters

Filter controls at the top (icons or dropdowns) limit which characters appear:

- **Realm** — This realm / All realms (and per-account scope if applicable).
- **Faction** — Alliance / Horde / Both.
- **Level** — Min and/or max level range.
- **Class** — Only characters of a given class.
- **Profession** — Only characters that have a given profession (by name or skill level threshold).

Exact UI (icons vs dropdowns) is implementation-defined; the goal is to support these filter dimensions.

---

## 5. Actions and Shortcuts

- **Options** — Open Blizzard Interface Options to the AltArmy TBC (and DataStore) category.
- **Right-click on a character row** — Context menu:
  - View this character in the **Characters** tab (make them the selected character).
  - Delete alt (remove from DataStore).
  - Other realm/character actions as needed (e.g. delete realm).

No Account Sharing button.

---

## 6. Navigation to Other Tabs

- **Click a character row** (or “View character” from context menu) — Switch to the **Characters** tab with that character selected.
- **Search box in header** — User can type an item name and press Enter/Search to jump to the **Search** tab with that query (if implemented in the main frame).

---

## 7. Data Source

All data for the Summary tab comes from **DataStore**: character list, realm, faction, level, class, money, rest XP, played time, and profession **skill levels** only. No quest, talent, mail, or auction data is used.
