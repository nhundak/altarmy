# AltArmy TBC — High-Level Structure

This document describes the **AltArmy TBC** WoW addon from a high-level perspective: purpose, architecture, tabs, and data strategy. It is a reduced-scope alt-management addon inspired by Altoholic Vanilla.

---

## 1. Purpose

AltArmy TBC provides:

- **Character list and summary** — See all characters (realm, faction, level, money, etc.) in one place.
- **Per-character inventory** — View one character’s bags and bank.
- **Cross-character item search** — Find which character has an item (bags and bank only).

There is **no** guild feature, no calendar/agenda, no comparison grids, no account sharing, and no mail/auction tracking. Profession data is limited to **skill levels** (for the summary); there is no recipe browser or “crafted by” search.

---

## 2. Architecture Overview

- **AltArmy TBC** — Core addon: main window, tabs, options, minimap button, and UI logic.
- **DataStore** — External addon library used for persistence. AltArmy TBC depends on DataStore and only the DataStore modules it needs (see §6).

Data is stored via DataStore; AltArmy TBC focuses on UI and addon logic.

---

## 3. Main Window

- **Single main frame** (Auction House–style), movable.
- **Tabs**: Three top-level tabs only:
  1. **Summary** — Account-level character list and summary view.
  2. **Characters** — Per-character detail (containers only).
  3. **Search** — Find items across all characters (bags and bank).

- **Header**: Title, search edit box, Search button (and Reset if desired), close button. Quick search from the header can jump to the Search tab and run a find.

No Guild, Agenda, or Grids tabs.

---

## 4. Scope Summary

| Area              | In scope                                                                 | Out of scope / deferred                    |
|-------------------|---------------------------------------------------------------------------|--------------------------------------------|
| **Summary**       | Single summary view (character list + columns: name, level, money, etc.) | Extra summary modes (Bag Usage, Skills, Activity, Misc) initially |
| **Characters**    | One character at a time; **Containers** (bags + bank) only               | Quests, talents, spellbook, pets, mail, auctions, recipe browser |
| **Professions**   | Profession **skill levels** only (for summary)                           | Recipes, cooldowns, “can craft” search     |
| **Search**        | Items in **bags and bank** per character                                 | Guild bank, “crafted by”                   |
| **Other**         | Minimal options, minimal minimap button                                  | Account sharing, tooltips (deprioritized), guild, calendar, grids |

---

## 5. Document Map

- **This file** — High-level structure, architecture, scope, DataStore usage.
- **[ALTARMY_TBC_SUMMARY.md](ALTARMY_TBC_SUMMARY.md)** — Summary tab: layout, columns, filters, actions.
- **[ALTARMY_TBC_CHARACTERS.md](ALTARMY_TBC_CHARACTERS.md)** — Characters tab: selection, Containers view only.
- **[ALTARMY_TBC_SEARCH.md](ALTARMY_TBC_SEARCH.md)** — Search tab: how search works, UI, result columns.
- **[ALTARMY_TBC_OPTIONS_AND_MINIMAP.md](ALTARMY_TBC_OPTIONS_AND_MINIMAP.md)** — Options and minimap (minimal).

---

## 6. DataStore Usage

AltArmy TBC **uses the DataStore library** for persistence. Only the DataStore modules required for the in-scope features are used:

- **Characters** — Character list, realm, faction, level, class, money, played time, rest XP, profession skill levels, etc.
- **Containers** — Bags and bank contents (item IDs, counts, slot indices).

No DataStore modules (or features) for: guild, calendar, mail, auctions, quests, talents, spellbook, companions, or recipes beyond what is needed to display profession levels.

Data is captured when the user opens bags and bank; profession levels when the profession pane is opened or via existing DataStore profession hooks, as appropriate for the chosen DataStore API.

---

## 7. Out of Scope (Explicit)

- **Guild** — No guild tab, no guild roster, no guild bank in search.
- **Calendar / Agenda** — No calendar, no event list, no cooldown/lockout UI.
- **Grids** — No comparison grids (equipment, reputations, dailies, attunements, keys, tradeskills, dungeons).
- **Account sharing** — No send/request data to another player.
- **Mail & Auctions** — No mailbox or AH tracking; no Mail or Auctions sub-views.
- **Quests, talents, spellbook, pets** — No character sub-views for these.
- **Recipe browser / “crafted by”** — Profession levels only; no recipe list or craft-based search.
- **Tooltips** — “Owned by” / “crafted by” on item tooltips are deprioritized.
