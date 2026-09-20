---
name: debug-compare-dump
description: >-
  Locate and analyze AltArmy gear compare panel debug dumps (comparePanelDumps
  in WoW SavedVariables). Use when the user mentions compare dumps, the Dump
  button, item stat parsing bugs, wrong compare rows, or SavedVariables
  debugging for ItemStats/GearCompare.
---
# Debug compare panel dumps

## Find the dump file

1. Read `.cursor/local.json` (machine-specific; gitignored). Key: `wowSavedVariables`.
2. If missing, copy `.cursor/local.json.example` and set the path to `AltArmy_TBC.lua` under your WoW install's `WTF/Account/<ACCOUNT>/SavedVariables/`.
3. Common Windows client folders: `_anniversary_`, `_classic_`, `_classic_era_` (not always `_classic_`).

## Sync into the workspace (preferred for analysis)

After the user clicks **Dump** in-game and runs `/reload`:

```bash
npm run dump:sync
```

This copies SavedVariables to `debug/compare-dump-source/AltArmy_TBC.lua` inside the repo (gitignored). Analyze that file instead of searching the filesystem.

## Where dumps live in SavedVariables

- Table: `AltArmyTBC_Options.debug.comparePanelDumps`
- Only the **latest** dump is kept (`comparePanelDumps` length 1; each Dump replaces the previous).
- Full schema: [docs/COMPARE_PANEL_DEBUG_DUMP.md](../../docs/COMPARE_PANEL_DEBUG_DUMP.md)

Search synced file:

```bash
rg -n "comparePanelDumps" debug/compare-dump-source/AltArmy_TBC.lua
```

## What to inspect first

| Symptom | Check in dump |
|--------|----------------|
| Wrong stat row label/value | `items.*.parseSnapshot.normalized`, `tooltipLines`, `mergedRaw` |
| Wrong weight (x0) | `character.specKey`, `weights`, `comparison.sections` |
| Score mismatch | `items.*.scoreBreakdown` vs `comparison.summary` |
| Snapshot vs UI disagree | `parseSnapshot.normalized` vs `scoreBreakdown.contributions` (cache refresh) |

## In-game capture checklist

1. `/altarmy debug on`
2. Gear tab: focus item, select character column, open compare
3. Click **Dump** (or `/altarmy debug dumpcompare`)
4. `/reload`
5. `npm run dump:sync`

## Optional fixture for tests

Copy the last `comparePanelDumps` entry into `spec/fixtures/compare-dumps/` as a named repro when adding regression tests.
