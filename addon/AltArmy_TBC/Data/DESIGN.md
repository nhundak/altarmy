# Data Folder — Design Principles

This folder holds the **data layer** for AltArmy TBC: persistence, aggregation, and list/view logic. UI (tabs) and other features consume this layer; they do not read SavedVariables or WoW APIs directly for character data.

---

## Layering

Data flows in one direction:

1. **DataStore.lua** — Persistence and scanning  
   - Owns `AltArmyTBC_Data` (SavedVariables).  
   - Scans the current character on WoW events (e.g. `PLAYER_ENTERING_WORLD`, `PLAYER_MONEY`, `TIME_PLAYED_MSG`).  
   - Exposes: `GetRealms()`, `GetCharacters(realm)`, `GetCharacter(name, realm)`, `GetCurrentCharacter()`, and per-field getters on character data.

2. **SummaryData.lua** — Aggregation and formatting  
   - Reads from DataStore only (no direct SavedVariables access).  
   - Builds a flat list of character entries for the Summary tab.  
   - Entry shape: `name`, `realm`, `level`, `restXp`, `money`, `played`, `lastOnline` (raw values: copper, seconds, timestamps).  
   - Provides display helpers: `GetMoneyString`, `GetTimeString`, `FormatLastOnline`, `FormatRestXp`.

3. **Characters.lua** — List and view  
   - Gets list via `SummaryData.GetCharacterList()`.  
   - Maintains a cached list and a view (indices); supports sorting.  
   - Exposes: `InvalidateView()`, `GetView()`, `GetList()`, `Sort(ascending, sortKey)`.  
   - Tabs (e.g. TabSummary) use Characters for the scroll list; they do not call SummaryData or DataStore directly for that list.

**Rule:** Each layer talks only to the layer below. Tabs talk to Characters (or SummaryData only for formatting); they do not talk to DataStore for list data.

---

## Single Source of Truth

- **DataStore** is the only writer to `AltArmyTBC_Data`. All character data comes from WoW APIs + events and is written in DataStore.
- **SummaryData** is stateless for the list: each `GetCharacterList()` call builds the list from DataStore. No local cache of the full list.
- **Characters** caches the list and view. When underlying data may have changed (e.g. after login, tab show), the UI calls `Characters:InvalidateView()` so the next `GetView()`/`GetList()` rebuilds from SummaryData.

---

## Raw Values vs Display

- **Stored and passed:** Raw values (copper, seconds since epoch, seconds played). This keeps sorting and logic simple and locale-independent.
- **Display:** Formatting (e.g. "5g 20s", "2d 3h ago", "50%") lives in SummaryData helpers or in the UI (TabSummary column `GetText`). The data layer does not store formatted strings for these fields.

---

## TBC Compatibility

- No external addon dependencies. DataStore is internal; no DataStore_Characters or similar.
- WoW API usage is defensive: check for function existence (e.g. `UnitName and UnitName("player")`, `GetRealmName and GetRealmName()`) so the addon runs on TBC Classic even when some APIs differ or are missing.
- SavedVariables key is `AltArmyTBC_Data`; structure is `Characters[realm][name] = charData`.

---

## Extensibility

- **DataStore:** New character fields can be added to the scanned `charData` and exposed via new getters. Event handlers can be extended to update them.
- **SummaryData:** New entry fields can be added to the table returned by `GetCharacterList()`; new formatting helpers can be added alongside existing ones.
- **Characters:** `Sort()` can be extended to support new sort keys; the view/list model stays index-based so UI code does not need to change for new columns.

---

## Namespace

All modules live under the `AltArmy` global:

- `AltArmy.DataStore` — DataStore API  
- `AltArmy.SummaryData` — SummaryData API and formatting  
- `AltArmy.Characters` — Characters list/view API  

The Data folder does not introduce new globals beyond these namespaces.
