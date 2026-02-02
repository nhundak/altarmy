# Altoholic Vanilla — Project Structure (Feature Overview)

This document describes the **Altoholic Vanilla** WoW addon from a **user and feature** perspective: what the UI contains, what pages exist, and what the user can do on each. It is intended as a reference for building a similar alt-management addon (e.g. AltArmy TBC), not as code documentation.

---

## 1. Addon Architecture Overview

Altoholic is split into **multiple addon modules**:

| Module | Purpose |
|--------|--------|
| **Altoholic** | Core: main window, options, account sharing, minimap button, tooltips, events/calendar logic |
| **Altoholic_Summary** | Account-level summary: characters list, filters, totals |
| **Altoholic_Characters** | Per-character detail: bags, quests, talents, mail, AH, spellbook, professions, pets |
| **Altoholic_Search** | Cross-character item search (bags, bank, crafts) |
| **Altoholic_Guild** | Guild roster with alts and sorting |
| **Altoholic_Agenda** | Calendar and event list (cooldowns, lockouts) |
| **Altoholic_Grids** | Comparison grids: equipment, reputations, dailies, attunements, keys, tradeskills, dungeons |

Data is stored via a separate **DataStore** addon (and its modules); Altoholic focuses on UI and logic.

---

## 2. Main Window

- **Single main frame** (Auction House–style), movable, with **6 top-level tabs** and a **global search** area.
- **Header**: Title, search label, search edit box, Reset/Search buttons, close button.
- **Quick search**: User can type an item name in the edit box and press Enter (or click Search) to jump to the **Search** tab and run a find.

**Tabs (left to right):**

1. **Summary** — Account overview and character list  
2. **Characters** — Detailed view for one character  
3. **Search** — Find items across all characters  
4. **Guild** — Guild members and alts  
5. **Agenda** — Calendar and events  
6. **Grids** — Side-by-side comparison views  

---

## 3. Summary Tab

**Purpose:** See all characters (optionally filtered by realm, faction, level, class, profession) and switch between different “summary” views.

### 3.1 Left menu (summary modes)

User picks one of five **summary modes**; the main pane shows a table of characters (and realms) with mode-specific columns.

| Mode | Description | Typical columns |
|------|-------------|------------------|
| **Account Summary** | Default overview | Name, Level, Rest XP, Money, Played, AiL, etc. |
| **Bag Usage** | Inventory capacity | Name, Level, Bag slots, Free bag, Bank slots, Free bank |
| **Skills** | Professions and skill levels | Name, Level, profession columns (e.g. Mining, Herbalism, Tailoring) with rank and recipe counts |
| **Activity** | Mail and AH activity | Name, Level, Mails, Last mail check, Auctions, Bids, AH last visit |
| **Miscellaneous** | Other info | Name, Level, Guild, Hearthstone, Class/Spec |

- **Sorting**: User can sort by column (click header); ascending/descending is toggled.
- **Totals row**: Bottom shows totals (e.g. gold, levels, played time).
- **Expand/Collapse**: “ALL” toggle to expand or collapse realm/character rows.

### 3.2 Filter icons (top)

Icons let the user **filter** which characters appear in the list:

- **Realms** — This realm / All realms (and per-account scope).
- **Faction** — Alliance / Horde (or both).
- **Level** — Min/max level range.
- **Professions** — Only characters with a given profession.
- **Class** — Only a given class.

### 3.3 Actions and shortcuts

- **Account Sharing** button — Opens the account-sharing dialog (request or send data to another player).
- **Options** (Altoholic and DataStore) — Open Blizzard Interface Options to the addon/DataStore category.
- **Right-click** on a character — Context menu: view that character in the Characters tab, delete alt, request account update, delete realm, etc.

---

## 4. Characters Tab

**Purpose:** Inspect **one character** in detail: bags, quests, talents, auctions, mail, companions, spellbook, professions.

### 4.1 Character selection

- Character is chosen from the **Summary** (click a row) or from the **Grids** tab (click a class icon).
- A **realm/account** picker and **class icons** (or similar) are used to choose which character is “current”.
- **Status line** at bottom shows current character name and the active sub-view (e.g. “Containers”, “Quest Log”).

### 4.2 Sub-views (icon bar)

User switches sub-views by clicking icons:

| View | Content |
|------|--------|
| **Containers (Bags)** | All bags and bank slots in a grid. Shows bag type, size, free slots. Click bag for tooltip; items show icon, count, quality. Can view “all bags in one” or per-bag. |
| **Quest Log** | Quest list for the character (by category/header). Shows name, level, type (e.g. daily), completion, rewards, money. |
| **Talents** | Talent trees (specs). User selects spec; tree shows spent points. Can compare with another character or guild member in a second panel. |
| **Auctions** | Current **auctions** and **bids** for this character. Sort by name, owner/high bidder, price. |
| **Mail** | Mailbox snapshot: subject, sender, expiry. Sort by subject, sender, expiry. User must have opened mailbox on that character for data to be present. |
| **Companions (Pets)** | Mounts and non-combat pets. Paginated list; click for spell link; shift-click to insert link in chat. |
| **Spellbook** | Spells by school (e.g. Fire, Frost). Paginated; shows spell icon and rank. |
| **Recipes (Professions)** | Recipes for a chosen profession. Categories and color (orange/yellow/green/grey). Filter by slot (e.g. weapon, armor). Click row to see recipe; shift-click to link profession in chat. |

- **Sort buttons** — Available where relevant (e.g. 4 columns for character-level sort options).

---

## 5. Search Tab

**Purpose:** Find **items** across all characters (and optionally guild bank / crafts).

### 5.1 How search works

- User enters an item name (or partial name) in the **main window search box** and presses Enter or Search, **or** uses search controls on the Search tab.
- Results show: **item** (icon, name, count), **owner** (character), **location** (realm, account), and **source** (e.g. bag, bank, craft).
- Results can be split by **source**: e.g. player bags, guild bank, player crafts, guild crafts.

### 5.2 Search tab UI

- **Categories**: Item classes (Weapons, Armor, Containers, Gems, Consumables, Trade Goods, etc.) with subclasses (e.g. 1H Axe, Cloth).
- User can **browse by category** or **search by name**.
- Each result row: item icon/name, character, realm, count, and a “source” button (e.g. “Containers”, “Recipes”) that can open the relevant character/view.

---

## 6. Guild Tab

**Purpose:** View **guild roster** with optional “main vs alts” grouping and sorting.

### 6.1 Single main view: Guild Members

- List of guild members (and, if data is available, their **alts** on the same realm/account).
- **Sort** by: Name, Level, Average Item Level (AiL), Game version, Class.
- Data comes from guild roster and from Altoholic’s own alt tracking (e.g. who has Altoholic and which alts they have).

---

## 7. Agenda Tab

**Purpose:** **Calendar** and **event list** for profession cooldowns, instance lockouts, and other time-based events.

### 7.1 Left menu

- **Calendar** — The only visible menu item in the Vanilla version; “Contacts” and others exist in code but are hidden.

### 7.2 Calendar

- **Month view**: Classic calendar grid (weekdays, days of month). User can change month (previous/next).
- **Option**: Week starts on Monday or Sunday.
- **Event list** (e.g. beside or below calendar): List of **upcoming events** grouped by date, e.g.:
  - **Profession cooldowns** — “Transmute X ready in …” (per character).
  - **Instance lockouts** — “Molten Core unlocks in …” (per character).
  - **Calendar events** — From in-game calendar (if used).
  - **Item timers** — E.g. item use cooldowns.

- Clicking an event can show details (character, realm, time left). The addon can show **notifications** when cooldowns are ready or soon.

---

## 8. Grids Tab

**Purpose:** Compare **many characters at once** in a grid: one row per “thing” (e.g. item slot, faction, daily quest), one column per character.

### 8.1 Setup

- **Realm selector** — Choose realm (and account).
- **Character columns** — User assigns characters to columns (e.g. via class icons); typically up to 12 columns.
- **Grid type** — Chosen via icon buttons (see below).

### 8.2 Grid types

| Grid | Rows | Per-cell content |
|------|------|-------------------|
| **Equipment** | Equipment slots (head, neck, weapon, etc.) | Item icon and optional ilvl/stat summary for that character’s slot |
| **Reputations** | Factions (by expansion/category) | Standing (e.g. Friendly, Exalted) or value for that character |
| **Daily Quests** | List of daily quests | Whether that character has completed it (e.g. check/cross) |
| **Attunements** | Raid attunement quests (e.g. Onyxia, MC, BWL, Naxx) | Attuned or not (icon/text) |
| **Keys** | Dungeon keys (e.g. Shadowforge Key, Skeleton Key) | Whether character has the key (e.g. bag/bank count) |
| **Tradeskills** | Profession + optional recipe or group | Skill level or “can craft” for that character |
| **Dungeons** (optional/hidden in some builds) | Raid/dungeon list (e.g. 10/40 man) | Instance lockout or completion state |

- Some grids have a **view dropdown** (e.g. Tradeskills: choose expansion and profession; Dungeons: choose raid size).
- **Status line** — Short description of current grid (e.g. “Daily Quests”).

---

## 9. Account Sharing

**Purpose:** Send or receive **full Altoholic (DataStore) data** with another player (e.g. alt on another account).

- **Access**: Button on Summary tab (“Account Sharing”) or similar.
- **Dialog**:
  - **Source account name** (who is sending).
  - **Target**: “Use target” (current target) or “Use name” (type character name).
  - **Content list**: Checkboxes to select what to share (e.g. characters, inventory, mail, professions).
  - **Send / Request** — Request data from the other player or send your own.
  - **Status** — Transfer progress or error message.
- **Requirement**: Both sides must enable account sharing in options.

---

## 10. Options

- **Altoholic options** (Interface → Addons → Altoholic): General settings, **minimap icon** (show/hide, angle, radius), **tooltip** options (e.g. show bag contents, show alts), **UI** options (e.g. which tabs/sort defaults), **account sharing** enable/disable.
- **DataStore options**: Per-module settings (e.g. what to store, mail scan behavior). Accessed from Summary tab or Interface Options.

---

## 11. Minimap Button

- **Left-click**: Open/close the main Altoholic window.
- **Right-click + drag**: Reposition the minimap icon (angle/radius saved in options).
- **Tooltip**: Short text explaining left-click to open, right-click to drag.

---

## 12. Tooltips

- **Item tooltips**: Can show “owned by” (which alt has it, where) and “could be crafted by” (which alt knows the recipe). Configurable in options.
- **Custom Altoholic tooltip** is used in many frames to avoid conflicting with default game tooltips.

---

## 13. Data and Scanning (User Perspective)

- **Bags / Bank**: Data is captured when the user opens bags and bank (no need to open every bag manually for basic scan; bank must be opened).
- **Guild bank**: User must open each guild bank tab for it to be stored.
- **Mail**: Character must be at a mailbox; addon reads visible mails (mail body scan can be disabled in DataStore options).
- **Professions**: User must open the profession pane at least once per character for recipes/cooldowns to be stored.
- **Quests / talents / spellbook**: Stored when the addon’s events fire (e.g. login, zone change, or when the user opens the relevant UI).

---

## 14. Summary Table: Where Features Live

| Feature | Tab | Sub-page / Grid |
|--------|-----|------------------|
| Character list, filters, totals | Summary | Account Summary, Bag Usage, Skills, Activity, Miscellaneous |
| Account sharing dialog | Summary (button) | — |
| Bags & bank | Characters | Containers |
| Quest log | Characters | Quest Log |
| Talents | Characters | Talents |
| Auctions & bids | Characters | Auctions |
| Mail | Characters | Mail |
| Pets & mounts | Characters | Companions |
| Spellbook | Characters | Spellbook |
| Recipes | Characters | Recipes |
| Item search | Search | — |
| Guild roster | Guild | Guild Members |
| Calendar & events | Agenda | Calendar |
| Equipment grid | Grids | Equipment |
| Reputation grid | Grids | Reputations |
| Daily quests grid | Grids | Dailies |
| Attunements grid | Grids | Attunements |
| Keys grid | Grids | Keys |
| Tradeskills grid | Grids | Tradeskills |
| Dungeons grid | Grids | Dungeons |
| Options | — | Interface Options + in-frame shortcuts |
| Minimap | — | Minimap button |

---

This document reflects the **Altoholic Vanilla** codebase (WoW Classic–oriented). For a TBC-focused addon, you can reuse this structure and adjust content (e.g. TBC reputations, dungeons, attunements, profession caps, and events) as needed.
