# AltArmy TBC — Search Tab

This document describes the **Search** tab in detail: purpose, how search works, UI, and result format.

---

## 1. Purpose

The Search tab lets the user **find items across all characters** (bags and bank only). There is no search over guild bank or “crafted by” — only inventory and bank.

---

## 2. How Search Works

- User enters an item name (or partial name) in the **main window search box** and presses Enter or Search, **or** uses search controls on the Search tab itself.
- Search runs over **bags and bank** of all characters (respecting Summary filters if desired, e.g. realm/faction).
- Results show:
  - **Item**: Icon, name, total count (per character and/or globally).
  - **Owner**: Character name.
  - **Location**: Realm (and account if multi-account).
  - **Source**: Bag or Bank (and optionally which bag/slot).

No “Crafts” or “Guild bank” source in the initial version.

---

## 3. Search Tab UI

- **Search input**: Edit box to type item name (or partial). Search button (and optionally Reset/Clear).
- **Categories** (optional): Item classes (Weapons, Armor, Containers, Gems, Consumables, Trade Goods, etc.) with subclasses. User can **browse by category** or **search by name**. If scope is kept minimal, name-only search may be sufficient initially.
- **Results list/table**: Each row represents an occurrence (or grouped by character):
  - Item icon and name.
  - Character name.
  - Realm (and account if applicable).
  - Count (and slot/source: bag vs bank).
  - Optional “Go to” or “View” action that switches to the Characters tab with that character and (if possible) focuses the relevant bag/bank.

---

## 4. Result Columns and Grouping

Typical columns:

| Column   | Description                    |
|----------|--------------------------------|
| Item     | Icon, name, quality            |
| Character| Owner character name           |
| Realm    | Realm (and account if used)    |
| Count    | Number of that item            |
| Source   | Bag / Bank (and which bag)     |

Results can be grouped by character, by item, or flat list; implementation choice. Sorting by item name, character, count, or source is useful.

---

## 5. Quick Search from Header

The main window header has a search edit box. When the user types and presses Enter (or Search):

- Focus switches to the **Search** tab (if not already there).
- The search is executed with the typed string.
- Results are shown as above.

---

## 6. Data Source

Search uses **DataStore Containers** (bags and bank) for all characters. No guild bank, no recipe or craft data. Item names/IDs come from the same container data; no separate “crafted by” or recipe search.
