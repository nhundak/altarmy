# Cooldowns tab

Profession cooldown overview and raid/heroic lockouts.

## Purpose

Know which crafts are ready, whether mats are on hand, mail stockpile reagents from a bank alt, and track instance lockouts.

## Sub-views

Persisted as Crafting vs **Raids** (`AltArmyTBC_Options.cooldowns.activeView`).

### Crafting

Columns: recipe/category, character, mats availability, time remaining. Sortable by recipe, character, mats, and time. Live refresh while the tab is open.

Alchemy transmutes and enchanting spheres share one cooldown per group, so the list shows **one row per character** for each group. By default (**Auto**) that row uses the recipe they last crafted if they still know it, otherwise Primal Might then Arcanite (transmutes) or Void Sphere then Prismatic Sphere.

Click the Recipe cell on a grouped row to pick **Auto** or a specific recipe that character knows (listed A–Z after Auto). The cell becomes a search field with Cancel (same pattern as adding a character to a guild group). Matching text in the dropdown is highlighted in green. A manual pick is saved per character and wins over last-cast until you choose Auto again. Single-recipe rows (Spellcloth, Shadowcloth, Primal Mooncloth, Brilliant Glass) are not pickable.

Tooltips: reagent counts, craftability, character-specific material context (bags + bank + mail). Hovering any Recipe cell or a recipe in the picker shows the same recipe tooltip. The hover highlight and picker apply only to grouped rows.

**Stockpile send**

- With the mailbox open, use **Send Materials** then click rows (except the Recipe cell) to prepare mail transfer to that character (same realm).
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
