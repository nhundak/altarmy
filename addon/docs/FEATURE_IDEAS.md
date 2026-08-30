# AltArmy TBC — Feature Ideas

Possible new features for `AltArmy_TBC`, compared against popular WoW alt/account-management addons. Status is relative to the current codebase. Shipped details live in [FEATURES.md](FEATURES.md) and [tabs/](tabs/).

## Comparison baseline

Compared against:

- [BagSync](https://www.curseforge.com/wow/addons/bagsync)
- [SavedInstances](https://www.curseforge.com/wow/addons/saved_instances)
- [Altoholic](https://www.wowinterface.com/downloads/info8533-Altoholic.html)
- [OneWoW Alt Tracker](https://www.curseforge.com/wow/addons/onewow-alt-tracker)

## Status

| Idea | Status | Notes |
|---|---|---|
| Leveling timeline analytics | **Shipped** | [tabs/graphs.md](tabs/graphs.md) |
| Lockouts planner | **Partial** | [tabs/cooldowns.md](tabs/cooldowns.md) Raids view lists active lockouts; no “available now” list |
| Mail expiration alerts | **Partial** | Login chat within 5 days; no mailbox-attention UI ([FEATURES.md](FEATURES.md) alerts) |
| Global tooltip integration | **Not started** | Search already breaks down location *inside* the addon |
| Daily/weekly task tracker | **Not started** | |
| Gold and economy history | **Not started** | Research: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md) |
| Recipe gap intelligence | **Not started** | Recipe search covers *known* recipes only |
| Craft queue and material planner | **Not started** | Cooldown stockpile mailing is the related foundation |
| Character notes and tags | **Partial** | Bank-alt flag only ([FEATURES.md](FEATURES.md)) |
| Actionable suggestion panel | **Not started** | Separate chat alerts exist (cooldowns, mail, gear upgrades) |
| Data freshness indicators | **Partial** | Missing-data `!` and Last Online; no per-domain scan age |
| Guild data sharing | **Shipped** | [tabs/guild.md](tabs/guild.md) |

---

## Highest-value additions (best TBC fit)

### 1) Lockouts planner — partial

**Shipped:** Cooldowns → Raids view — per-character heroic/raid lockouts, reset timers, sort by instance/character/time.

**Remaining:** “Available now” / “can run tonight” for characters who are *not* locked.

### 2) Daily/weekly task tracker — not started

- Checklist per character for repeatable chores; reset-aware status; optional custom tasks.
- (`SearchTasks.lua` is the Search work queue, not a chore tracker.)

### 3) Global tooltip integration — not started

- On item tooltips *anywhere in-game*, show totals across characters with location breakdown.
- Search already shows Bags / Bank / Mail / equipped / keyring inside the addon. No external `GameTooltip` hook.

### 4) Mail expiration and pending mailbox alerts — partial

**Shipped:** login chat within 5 days; mail gold in Summary; mail items in Search.

**Remaining:** mailbox-attention UI, gold/items waiting indicator, opt-in / threshold controls.

### 5) Gold and economy history — not started

- Account and per-character gold deltas over time; optional source grouping.
- Related today: Summary gold; `/altarmy networth`. Design notes: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md).

### 6) Recipe gap intelligence — not started

- Unknown but learnable recipes; “who can learn now” vs skill gate.
- Related: known-recipe Search + CraftLib difficulty for learned recipes.

## Differentiator ideas

### Craft queue and material planner — not started

- Queue crafts across alts; missing mats and best source character.
- Related: Cooldowns stockpile send / send-all (cooldown reagents only).

### Character notes and tags — partial

**Shipped:** bank-alt flag with auto-detect, Summary icon, hide-from-Summary.

**Remaining:** freeform notes and general tags (transmute alt, raid-ready, etc.).

### Actionable suggestion panel — not started

- Unify cooldown-ready, lockouts resetting, mail expiring, rested XP into one “next actions” surface.

### Data freshness indicators — partial

**Shipped:** missing-data `!`, Last Online, Guild “shared data outdated.”

**Remaining:** per-domain last-scan display and “stale even though data exists” warnings.

## Suggested remaining work order

### Phase 1

- Lockouts “available now.”
- Mail attention UI.
- Global tooltip integration.

### Phase 2

- Daily/weekly task tracker.
- Gold and economy history.
- Per-domain last-scan freshness.

### Phase 3

- Recipe gap intelligence.
- Craft queue / material planner.
- Actionable suggestion panel.
- General character notes and tags.

## Notes for scoping

- Prefer strong TBC relevance first (lockouts, cooldowns, mail, gold).
- Keep data collection event-driven.
- Add opt-in controls for noisy reminders.
