# AltArmy TBC Feature Ideas

Possible new features for `AltArmy_TBC`, compared against popular WoW alt/account-management addons. Status below is relative to the current codebase (see [ADDON_FEATURES.md](ADDON_FEATURES.md) for the shipped feature set).

## Comparison baseline

Compared against:

- [BagSync](https://www.curseforge.com/wow/addons/bagsync)
- [SavedInstances](https://www.curseforge.com/wow/addons/saved_instances)
- [Altoholic](https://www.wowinterface.com/downloads/info8533-Altoholic.html)
- [OneWoW Alt Tracker](https://www.curseforge.com/wow/addons/onewow-alt-tracker)

## Status

| Idea | Status | Notes |
|---|---|---|
| Leveling timeline analytics | **Shipped** | Graphs tab + `DataStoreLevelHistory` |
| Lockouts planner | **Partial** | Cooldowns → Raids view tracks active lockouts; no “available now” list |
| Mail expiration alerts | **Partial** | Login chat when mail returns within 5 days; no mailbox-attention UI |
| Global tooltip integration | **Not started** | Search already breaks down location *inside* the addon |
| Daily/weekly task tracker | **Not started** | |
| Gold and economy history | **Not started** | Research only: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md) |
| Recipe gap intelligence | **Not started** | Recipe search covers *known* recipes only |
| Craft queue and material planner | **Not started** | Cooldown stockpile mailing is the related foundation |
| Character notes and tags | **Partial** | Bank-alt flag only |
| Actionable suggestion panel | **Not started** | Separate chat alerts exist (cooldowns, mail, gear upgrades) |
| Data freshness indicators | **Partial** | Missing-data `!` and Last Online; no per-domain scan age |

---

## Highest-value additions (best TBC fit)

### 1) Lockouts planner tab — partial

**Shipped** (Cooldowns tab → Raids view: `TabCooldownsRaids.lua`, `LockoutData.lua`, `DataStoreLockouts.lua`):

- Per-character heroic and raid lockouts.
- Reset remaining timers (including “Ready”).
- Sort by instance, character, or time; default is soonest reset first.

**Remaining:**

- “Available now” / “can run tonight” visibility for characters who are *not* locked (the Raids view only lists active lockouts).

Why: SavedInstances-style lockout visibility is one of the most useful alt management workflows and maps well to TBC.

### 2) Daily/weekly task tracker — not started

- Checklist per character for repeatable chores.
- Reset-aware status and countdown.
- Optional custom user-defined tasks.

(`SearchTasks.lua` is the Search tab work queue, not a chore tracker.)

Why: Gives users a clear “what should I do next on this alt?” flow.

### 3) Global tooltip integration — not started

- On item tooltips *anywhere in-game*, show totals across all characters.
- Break down by location (bags, bank, mail, AH snapshot).
- Keep current shift-click behaviors for fast linking.

**Already related:** Search item rows show character + location (`Bags` / `Bank` / `Mail` / equipped / keyring) and aggregate totals. Auction snapshots are stored (`DataStoreAuctions`) but are not a Search location. There is no `GameTooltip` hook outside the addon UI.

Why: BagSync-style “hover once, know where everything is” drastically reduces alt swapping friction.

### 4) Mail expiration and pending mailbox alerts — partial

**Shipped** (`MailAlerts.lua`, `DataStoreMail.lua`):

- Login chat warning when any character’s soonest mail returns within 5 days (`/altarmy debug mail {name}` to test).
- Mail gold is included in the Summary money column.
- Mail items appear in Search with a `(Mail)` location suffix.

**Remaining:**

- Surface “gold/items waiting in mailbox” by character as its own view or indicator.
- Quick “mail attention needed” UI (not only login chat).
- Opt-in / threshold controls for the reminder.

Why: Natural extension of the current stockpile-mail workflow.

### 5) Gold and economy history — not started

- Track account and per-character gold deltas over time.
- Session/day/week views.
- Optional source grouping where possible (mail, AH, vendor, etc.).

**Already related:** Summary shows current gold (bags + mail). `/altarmy networth` snapshots vendor + Auctionator value. `PLAYER_MONEY` updates the live gold field; it is not a history log. Design notes: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md).

Why: Adds trend visibility and supports farming/crafting planning.

### 6) Recipe gap intelligence — not started

- Highlight recipes that are unknown but learnable by specific alts.
- Show “who can learn now” vs “needs skill level.”
- Add “best alt for this recipe/item” hints.

**Already related:** Search indexes *known* recipes per character (and optional guildmates). CraftLib colors skill/difficulty for recipes already learned.

Why: Builds on existing recipe search with progression guidance similar to Altoholic patterns.

## Differentiator ideas

### Craft queue and material planner — not started

- Queue target crafts across multiple alts.
- Compute missing mats and best source character automatically.
- Reuse current cooldown + stockpile logic as a foundation.

**Already related:** Cooldowns tab mats column, missing-mat chat, and stockpile send / send-all mailing (`StockpilePlan.lua`, `TabCooldowns.lua`). That flow is cooldown-reagent mailing, not an arbitrary craft queue.

### Character notes and tags — partial

- Add tags like “bank alt”, “transmute alt”, “raid-ready.”
- Filter/sort tabs by tags.

**Shipped:** Bank-alt flag (`BankAlt.lua`) with auto-detect, Summary icon, and hide-from-Summary. No freeform notes or general tags.

### Actionable suggestion panel — not started

- Show “best next actions”:
  - Cooldowns ready
  - Lockouts resetting soon
  - Mail expiring soon
  - Characters with rested XP opportunities

**Already related (separate surfaces, not a panel):** cooldown-ready chat alerts, mail-expiry login chat, gear-upgrade alerts, Summary Rest XP column, Raids lockout list.

### Data freshness indicators — partial

- Display last scan time by character and data domain.
- Warn when major domains are stale (e.g. mail fresh, reps stale).

**Shipped:** Summary (and Gear/Reputation score rows) missing-data `!` via `GetMissingDataInfo` — never-gathered modules, stale reputation schema, professions needing an open window, etc. Summary Last Online. Guild tab “shared data is outdated” tooltip. Internal `dataVersions` and `lastUpdate` exist but are not shown as per-domain scan age.

**Remaining:** last-scan timestamps by domain, and “this domain is stale even though data exists” warnings (as opposed to never gathered).

### Leveling timeline analytics — shipped

Graphs tab (`TabGraph.lua`, `LevelProgressData.lua`, `DataStoreLevelHistory.lua`):

- Calendar date/time (`reachedAt`) and cumulative played time at each level-up.
- Time-per-level and cumulative-played graphs, including multi-character comparison.
- Shrink-outliers option for slow level bands.

No remaining work for the idea as originally scoped.

## Suggested remaining work order

### Phase 1 (quick wins)

- Finish lockouts planner: “available now” / “can run tonight” (unlocked instances).
- Mail attention UI (gold/items waiting, indicator beyond login chat).
- Global tooltip integration.

### Phase 2 (medium effort)

- Daily/weekly task tracker.
- Gold and economy history.
- Data freshness: per-domain last-scan display.

### Phase 3 (advanced)

- Recipe gap intelligence.
- Craft queue and material planner.
- Actionable suggestion panel (unify existing cooldown / mail / rest XP / lockout signals).
- General character notes and tags (beyond bank alt).

## Notes for scoping

- Prefer features with strong TBC relevance first (lockouts, cooldowns, mail, gold).
- Keep data collection event-driven to avoid login performance spikes.
- Add opt-in controls for potentially noisy reminders.
