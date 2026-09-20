---
name: summary-missing-data
description: >-
  AltArmy Summary tab missing-data warnings: one exclamation mark, one tooltip,
  de-duped action list via GetMissingDataInfo. Use when editing TabSummary,
  SummaryData, summary warning columns, missing-data tooltips, adding new
  gathered-data checks, or after addon version migrations.
---
# Summary missing-data warnings

## When warnings appear

Missing-data `!` marks are **expected** after users upgrade to a new addon version. Migrations often introduce new modules, data formats, or scan requirements (e.g. reputation v2, cooldown specs, gear scores) that existing SavedVariables do not satisfy until each character logs in and the relevant windows are opened. The warning is intentional UX: it tells the user what to do to backfill data — not a sign that migration failed. When adding a new gathered-data type or bumping a `dataVersions` module, add a condition in `GetMissingDataInfo` with a clear user action; do not add separate Summary UI for it.

## Design contract

- Summary tab shows **one** gold `!` per character row, in the **Warning** column only.
- **One** tooltip per mark: title `Some data for <name> has not been gathered yet.` plus a **de-duped** bulleted list of actions (`* ...` lines).
- All missing-data conditions (modules, talents, reputations, professions, poisons, cooldown specs, gear scores, etc.) are aggregated in **`GetMissingDataInfo`** — not split across multiple Summary columns or parallel tooltip APIs.

## Architecture

| Layer | File | Responsibility |
|-------|------|----------------|
| Data | `AltArmy_TBC/Data/Characters/SummaryData.lua` | `GetMissingDataInfo` (aggregator), `addUniqueInstruction` (dedup), `PresentMissingDataTooltip` (tooltip) |
| UI | `AltArmy_TBC/Tabs/TabSummary.lua` | Single `Warning` column renders `!` and calls `PresentMissingDataTooltip` |
| Tests | `spec/Data/SummaryData_spec.lua` | Every new condition needs `GetMissingDataInfo` coverage + dedup case where applicable |

## Exceptions (related but separate)

- `GetTalentSpecMissingInfo` is for `GearUpgrade.GetCompareSpecWarning` (compare panel talent-only signal) — **not** for Summary UI.
- Gear/Reputation tabs use `AltArmy_TBC/UI/ScoreSortRow.lua` for gear-score `!` marks — unrelated to Summary tab design.

## Anti-patterns (do not reintroduce)

- A second Summary column that shows its own `!` for a subset of missing data (e.g. the old `TalentSpec` column).
- Separate tooltip presenters per condition type on Summary (e.g. `PresentTalentSpecMissingTooltip` driving its own column).
- Duplicate `* Log in with this character` lines in the tooltip.

## Checklist: adding a new missing-data condition

1. Add detection + instruction string in `GetMissingDataInfo` via `addUniqueInstruction`.
2. Add unit test(s) in `SummaryData_spec.lua` (including dedup with existing instructions).
3. Do **not** add UI in `TabSummary.lua` beyond the existing `Warning` column.
4. Run `npm run check` and `npm test`.
