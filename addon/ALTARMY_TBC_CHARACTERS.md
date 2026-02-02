# AltArmy TBC — Characters Tab

This document describes the **Characters** tab in detail: purpose, character selection, and the single sub-view (Containers).

---

## 1. Purpose

The Characters tab lets the user inspect **one character** at a time. In the initial scope, the only content is **Containers** (bags and bank). There are no sub-views for quests, talents, spellbook, pets, mail, auctions, or recipes.

---

## 2. Character Selection

- The character is chosen from the **Summary** tab (e.g. click a row or “View character” from the context menu). There is no Grids tab, so character selection is only from Summary (or from a realm/character picker on the Characters tab itself).
- **Realm/account picker** and **character list** (or class icons / dropdown) on the Characters tab allow switching the “current” character without going back to Summary.
- A **status line** at the bottom (or header) shows the current character name and the active view (e.g. “Containers”).

---

## 3. Sub-views (Initial Scope: Containers Only)

In the initial version there is **one sub-view**:

| View         | Content |
|-------------|--------|
| **Containers (Bags & Bank)** | All bags and bank slots in a grid. Shows bag type, size, free slots. Items show icon, count, quality. User can view “all bags in one” or per-bag. Click bag or item for tooltip. |

No icon bar or tabs for other views (Quest Log, Talents, Auctions, Mail, Companions, Spellbook, Recipes). Those are out of scope.

If the UI is built with an icon bar for future expansion, only the Containers icon is enabled initially.

---

## 4. Containers View — Details

- **Bags**: All equipped bags and their slots in a grid. For each bag: type (e.g. bag type), size, number of free slots.
- **Bank**: Bank slots and bank bags (if any). Same treatment: grid of slots, bag type/size, free slots.
- **Items**: Each slot shows item icon, stack count, and quality color. Click for tooltip (default WoW or custom frame).
- **Layout**: “All bags in one” view and/or per-bag views; implementation can match Altoholic-style layout or a simpler single grid.

Data is read from **DataStore Containers**; no mail, auction, or recipe data is involved.

---

## 5. Profession Levels (Summary Only)

Profession **skill levels** (e.g. Mining 300, Tailoring 250) are stored and displayed in the **Summary** tab only. The Characters tab does **not** show a Recipes or Profession browser; it only shows Containers. If profession levels are shown anywhere on the Characters tab (e.g. in the status line or a small info block), they are display-only from the same DataStore character data used by Summary.

---

## 6. Data Source

- **Containers**: DataStore Containers module (bags and bank).
- **Character info** (name, level, class, realm, profession levels): DataStore Characters (or equivalent) module.

No DataStore modules for quests, talents, spellbook, mail, auctions, companions, or recipes.
