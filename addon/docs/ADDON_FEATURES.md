# AltArmy TBC Addon Features

This document summarizes the implemented features in the `AltArmy_TBC` addon based on the current codebase.

## What the addon does

AltArmy TBC is an account-wide alt management addon for TBC Classic that:

- Collects and persists character data automatically while you play.
- Presents cross-character information in tabbed dashboards.
- Supports item and recipe search across characters.
- Tracks profession cooldown readiness and supports stockpile mailing workflows.
- Provides configurable filters, sorting, pin/hide behavior, and alerts.

## UI design system

- Shared warm bronze / dark panel theme in `AltArmy_TBC/UI/Theme.lua` (see [UI_DESIGN.md](UI_DESIGN.md)).
- All tabs, settings panels, popovers, and Interface Options use the same backdrop recipe and color roles.

## Main UI and access

- Main frame is movable, closable, and registered for `Escape` closing.
- Open with slash commands:
  - `/altarmy`
  - `/alta`
- Minimap button support (toggle window with left click, drag to move).
- Header search box is always available and switches into Search mode when populated.

## Tabs and feature set

### Summary tab

- Character overview list with columns:
  - Name (class-colored with icon)
  - Level (fractional level support)
  - Rest XP
  - Money (including mail money)
  - Played time
  - Last online
- Clickable column sorting with ascending/descending toggles.
- Per-character pin/hide controls via Summary settings panel.
- Realm filtering support (current realm or all realms).
- Totals row for aggregate level, money, and played time.
- Missing data warning indicator with detailed tooltip instructions.

### Gear tab

- Gear grid view:
  - Rows are equipment slots.
  - Columns are characters.
  - Hover tooltips per equipped item.
  - Shift-click to insert item links into chat.
- Character ordering and visibility controls:
  - Primary/secondary sort.
  - Show self first.
  - Pin/hide characters.
- Appearance controls:
  - Icon size (small/medium/large).
  - Spacing (compact/normal/comfortable).
- Optional "who can use this" workflow:
  - Drag/drop an item to rank characters by likely usability.
  - Shows class/equip/level fit hints in headers.

### Reputation tab

- Reputation matrix:
  - Rows are factions.
  - Columns are characters.
  - Per-cell standing and progress bar.
- Faction name filter input to reduce visible rows.
- Sort interactions:
  - Sort character columns by selected faction value.
  - Sort faction rows by selected character value.
- Handles mixed/legacy reputation data and undiscovered faction states.
- Per-character pin/hide and sort controls in Reputation settings panel.

### Cooldowns tab

- Profession cooldown list with columns:
  - Recipe/category
  - Character
  - Mats availability
  - Time remaining
- Sortable by recipe, character, mats, and time.
- Live periodic refresh while tab is open.
- Tooltip enrichment:
  - Reagent counts.
  - Craftability data.
  - Character-specific material context.
- Stockpile send workflow:
  - Click cooldown rows to prepare stockpile transfer by mail.
  - Computes feasible transfer quantity from available mats.
  - Supports stack split/merge attachment planning.
  - Sends mail attachments to target character on same realm.
  - Includes user feedback for missing materials, mailbox state, and send success.

### Search tab

- Unified search results for:
  - Items (bags, bank, mail snapshots)
  - Recipes
- Category toggles (Items, Recipes).
- Virtualized rendering for large result sets.
- Grouped item rows with aggregate totals.
- Additional delayed "You may also be interested in" section:
  - Uses broader searchable text and tooltip-aware matching.
- Shift-click behavior:
  - Item rows insert item links.
  - Recipe rows insert recipe/spell links when available.
- Search settings panel includes realm filter guidance.

## Data collection and persistence

Data is stored in SavedVariables under:

- `AltArmyTBC_Data` (account-wide character/domain data)
- `AltArmyTBC_Options` and tab-specific settings tables

Core data domains include:

- Character basics (name, class, level/xp/rested xp, played, money, logout time)
- Containers and bank
- Equipment
- Currencies
- Professions and recipes
- Cooldowns and specialization state
- Reputations
- Mail
- Auctions/bids

Data scanning is event-driven and includes delayed rescans where needed to capture late-loading UI/game data.

## Realm filtering and character visibility

- Global realm filter supports:
  - Current realm only
  - All realms
- Applied consistently across Summary, Gear, Reputation, Search, and Cooldowns.
- Per-tab character pin/hide settings are available for major matrix/list tabs.

## Alerts and reminders

Cooldown availability alerts support:

- Chat output
- Center-screen raid-warning style output
- Combined output mode
- Per-category reminder intervals while cooldown is ready
- Optional specialization-dependent visibility/alerts for relevant professions

## Options panel

Interface options panel includes tabs for:

- General
- Characters
- Cooldowns
- Debug (toggleable via slash debug commands)

Notable controls:

- Show/hide minimap button
- Global realm filter dropdown
- Character data delete action (with self-delete protection and confirmation)
- Per-cooldown-category UI/alert/reminder configuration
- Debug toggles for search timing and cooldown scan logging

## Debug controls

Slash command extensions:

- `/altarmy debug on`
- `/altarmy debug off`

When enabled, debug options are exposed in the options UI and can emit targeted diagnostics to chat.

