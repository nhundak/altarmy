# AltArmy TBC Feature Ideas

This document captures possible new features for `AltArmy_TBC` based on a comparison with popular WoW alt/account-management addons.

## Comparison baseline

Compared against:

- [BagSync](https://www.curseforge.com/wow/addons/bagsync)
- [SavedInstances](https://www.curseforge.com/wow/addons/saved_instances)
- [Altoholic](https://www.wowinterface.com/downloads/info8533-Altoholic.html)
- [OneWoW Alt Tracker](https://www.curseforge.com/wow/addons/onewow-alt-tracker)

## Highest-value additions (best TBC fit)

### 1) Lockouts planner tab

- Track per-character heroic and raid lockouts.
- Show reset timers and "available now" sorting.
- Include quick visibility for "can run tonight" planning.

Why: SavedInstances-style lockout visibility is one of the most useful alt management workflows and maps well to TBC.

### 2) Daily/weekly task tracker

- Checklist per character for repeatable chores.
- Reset-aware status and countdown.
- Optional custom user-defined tasks.

Why: Gives users a clear "what should I do next on this alt?" flow.

### 3) Global tooltip integration

- On item tooltips anywhere in-game, show totals across all characters.
- Break down by location (bags, bank, mail, AH snapshot).
- Keep current shift-click behaviors for fast linking.

Why: BagSync-style "hover once, know where everything is" drastically reduces alt swapping friction.

### 4) Mail expiration and pending mailbox alerts

- Track mailbox age and warn when mail nears expiration.
- Surface "gold/items waiting in mailbox" by character.
- Add quick "mail attention needed" indicators.

Why: Natural extension of the current stockpile-mail workflow.

### 5) Gold and economy history

- Track account and per-character gold deltas over time.
- Session/day/week views.
- Optional source grouping where possible (mail, AH, vendor, etc.).

Why: Adds trend visibility and supports farming/crafting planning.

### 6) Recipe gap intelligence

- Highlight recipes that are unknown but learnable by specific alts.
- Show "who can learn now" vs "needs skill level."
- Add "best alt for this recipe/item" hints.

Why: Builds on existing recipe search with progression guidance similar to Altoholic patterns.

## Differentiator ideas

### Craft queue and material planner

- Queue target crafts across multiple alts.
- Compute missing mats and best source character automatically.
- Reuse current cooldown + stockpile logic as a foundation.

### Character notes and tags

- Add tags like "bank alt", "transmute alt", "raid-ready."
- Filter/sort tabs by tags.

### Actionable suggestion panel

- Show "best next actions":
  - Cooldowns ready
  - Lockouts resetting soon
  - Mail expiring soon
  - Characters with rested XP opportunities

### Data freshness indicators

- Display last scan time by character and data domain.
- Warn when major domains are stale (e.g., mail fresh, reps stale).

### Leveling timeline analytics

- Record the calendar date/time when each character hits a new level.
- Record cumulative played time at each level-up milestone.
- Show a graph of leveling pace over time (per character and optional account comparison).
- Highlight slow/fast level bands to compare routes or play patterns.

## Suggested implementation order

### Phase 1 (quick wins)

- Global tooltip integration
- Lockouts planner tab
- Mail expiration alerts

### Phase 2 (medium effort)

- Daily/weekly task tracker
- Gold and economy history

### Phase 3 (advanced)

- Recipe gap intelligence
- Craft queue and material planner
- Actionable suggestion panel
- Leveling timeline analytics (level-up timestamps + played-time graph)

## Notes for scoping

- Prefer features with strong TBC relevance first (lockouts, cooldowns, mail, gold).
- Keep data collection event-driven to avoid login performance spikes.
- Add opt-in controls for potentially noisy reminders.
