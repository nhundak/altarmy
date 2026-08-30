# Cooldowns tab

Profession cooldown overview and raid/heroic lockouts.

## Purpose

Know which crafts are ready, whether mats are on hand, mail stockpile reagents from a bank alt, and track instance lockouts.

## Sub-views

Persisted as Crafting vs **Raids** (`AltArmyTBC_Options.cooldowns.activeView`).

### Crafting

Columns: recipe/category, character, mats availability, time remaining. Sortable by recipe, character, mats, and time. Live refresh while the tab is open.

Tooltips: reagent counts, craftability, character-specific material context (bags + bank + mail).

**Stockpile send**

- Click rows to prepare mail transfer to that character (same realm).
- Computes feasible quantity from available mats; stack split/merge attachment planning.
- Feedback for missing materials, mailbox state, and send success.
- **Send-all** batch: distribute to multiple selected cooldown rows from one mailbox session.

### Raids

- Per-character heroic and raid lockouts (instance name, difficulty, time remaining / Ready).
- Sort by instance, character, or time (default: soonest reset first).
- Lists **active** lockouts only (no “available now / unlocked” planner yet — see [FEATURE_IDEAS.md](../FEATURE_IDEAS.md)).

## Alerts

Cooldown-ready alerts: chat, center-screen raid-warning style, or both; per-category reminder intervals; optional specialization-dependent visibility. Configured under Options → Cooldowns.

## Data source

`CooldownData`, `LockoutData`, DataStore professions / lockouts / containers / mail. Stockpile planning: `StockpilePlan`.
