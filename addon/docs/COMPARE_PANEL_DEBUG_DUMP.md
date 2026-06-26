# Gear compare panel debug dumps

When `/altarmy debug on` is active, the Gear tab compare panel shows a **Dump** button in the top-right corner. Click it while comparing a focused item against an alt's equipped piece to capture a structured snapshot for offline debugging.

WoW addons cannot write arbitrary files. Dumps are appended to **SavedVariables** and flushed to disk when you `/reload` or log out.

## Enable and capture

1. Run `/altarmy debug on`.
2. Open the Gear tab, drop or focus an item, and select a character column to compare.
3. Click the bordered **Dump** button below the compare warnings on the left, or run `/altarmy debug dump`.
4. Run `/reload` (or log out).
5. Open the SavedVariables file on disk (path below).

The newest dumps are at the end of `AltArmyTBC_Options.debug.comparePanelDumps`. The buffer keeps the last **20** entries.

## File location (Windows)

```
<WoW Install>\_classic_\WTF\Account\<ACCOUNT_NAME>\SavedVariables\AltArmy_TBC.lua
```

The client folder name (`_classic_`, `_anniversary_`, etc.) depends on your install. Search for `AltArmy_TBC.lua` under `WTF` if unsure.

Look for a block like:

```lua
AltArmyTBC_Options = {
    debug = {
        enabled = true,
        comparePanelDumps = {
            {
                version = 1,
                timestamp = 1719331200,
                character = { ... },
                context = { ... },
                items = { ... },
                comparison = { ... },
                weights = { ... },
            },
            -- older dumps ...
        },
    },
}
```

## Payload structure

Each dump is one Lua table with these top-level keys.

### `version`

Schema version (currently `1`). Bump when fields change.

### `timestamp`

Unix time from `time()` when the dump was created.

### `character`

Who the comparison is for:

| Field       | Meaning                                      |
|------------|-----------------------------------------------|
| `name`     | Character name                                |
| `realm`    | Realm name                                    |
| `classFile`| WoW class token (`MAGE`, `WARRIOR`, …)        |
| `specKey`  | Resolved spec used for weights (`frost`, …)   |
| `level`    | Character level                               |

### `context`

Compare session settings:

| Field                     | Meaning                                                                 |
|--------------------------|-------------------------------------------------------------------------|
| `invSlot`                | Inventory slot ID being compared (e.g. `1` = head)                      |
| `techniqueId`            | Scoring provider id (`custom`, `ilvl`, `gearscore`)                    |
| `techniqueLabel`         | Display label shown in the UI                                           |
| `upgradeMaxDelta`        | Denominator for weighted % when using focus-mode max-delta scaling      |
| `upgradeThresholdPercent`| Upgrade threshold from gear options (if set)                            |
| `weightedChangePercent`  | Percent shown on the Weighted row (`delta / upgradeMaxDelta * 100` or `delta / oldTotal * 100`) |

### `items.focused` and `items.equipped`

Both items in the comparison. `equipped` is `nil` when the slot is empty.

| Field            | Meaning                                                        |
|-----------------|----------------------------------------------------------------|
| `link`          | Full item hyperlink                                            |
| `name`          | Item name from `GetItemInfo`                                   |
| `cacheSource`   | How stats were resolved: `api`, `tooltip`, `pending`, `none`   |
| `parseSnapshot` | Tooltip/API parsing detail (see below)                         |
| `scoreBreakdown`| Per-stat weighted score math (see below)                       |

#### `parseSnapshot` (tooltip scraping)

| Field          | Meaning                                                                 |
|---------------|-------------------------------------------------------------------------|
| `itemId`      | Numeric item id                                                         |
| `itemName`    | Name at parse time                                                      |
| `apiRaw`      | Table from `GetItemStats` (API keys → values)                           |
| `tooltipRaw`  | Stats parsed from tooltip lines via regex                               |
| `mergedRaw`   | API + tooltip merge (tooltip fills gaps API misses)                     |
| `normalized`  | Short keys used for scoring (`int`, `sta`, `heal`, …)                     |
| `tooltipLines`| Raw tooltip text lines, in order                                        |
| `incomplete`  | `true` if tooltip was still loading when parsed                         |

**How to read parsing issues**

1. Compare `apiRaw` vs `tooltipRaw` — missing keys in `apiRaw` often need tooltip rules.
2. Check `mergedRaw` — this is what normalization runs on.
3. Walk `tooltipLines` — if a line has stats but `tooltipRaw` is empty, the regex did not match.
4. Compare `normalized` on focused vs equipped — these feed the stat comparison rows.
5. If `incomplete = true`, reload and dump again after the item cache is warm.

#### `scoreBreakdown` (weight calculations)

| Field           | Meaning                                                          |
|----------------|------------------------------------------------------------------|
| `technique`    | Scoring mode used for this breakdown                             |
| `total`        | Final score from `ScoreItem` (matches comparison summary totals) |
| `weightedSum`  | Sum of `statValue * weight` over normalized stats (custom mode)  |
| `contributions`| Array of per-stat rows (sorted by key)                           |

Each `contributions[]` entry:

| Field          | Meaning                                    |
|---------------|--------------------------------------------|
| `key`         | Normalized stat key (`int`, `sta`, …)      |
| `statValue`   | Value from normalized stats                |
| `weight`      | Pawn-derived weight for this class/spec    |
| `contribution`| `statValue * weight`                       |

For `custom` technique, `total` should equal `weightedSum` (within float tolerance). For `ilvl` / `gearscore`, `contributions` may be sparse; use `total` and `comparison.summary`.

### `comparison`

The same structure the UI uses from `GearCompare.BuildComparison`:

- `focusedName`, `equippedName`
- `techniqueId`, `techniqueLabel`
- `summary`: `{ newTotal, oldTotal, delta }`
- `sections[]`: panel rows (`label`, `newValue`, `oldValue`, `delta`, `weight`, `weightedDelta`, `percent`, …)

Cross-check UI rows against `comparison.sections` and totals against `items.*.scoreBreakdown.total`.

### `weights`

Full weight table for the resolved `classFile` + `specKey` (normalized stat key → multiplier). Zero or missing weights mark stats as "unimportant" in the compare panel.

## Typical debugging workflow

1. Reproduce the wrong verdict or stat row in-game.
2. Click **Dump** with the same character column selected.
3. `/reload` and open `AltArmy_TBC.lua`.
4. Copy the last `comparePanelDumps` entry into a test fixture or inspect in-editor.
5. Focus on:
   - Wrong `normalized` → fix `ItemStats` parsing/normalization.
   - Right stats, wrong score → fix `weights` or `BuildScoreBreakdown`.
   - Right score, wrong % or verdict → fix `upgradeMaxDelta`, threshold, or `GetWeightedChangePercent`.

## Related chat debug

These do not write SavedVariables but complement dumps:

- `/altarmy debug stats` — stat parse lines in chat (enable **Item stat parsing** in Debug options).
- `/altarmy debug item <link>` — full multi-alt comparison report in chat (enable **Item comparison**).

The Dump button always refreshes parse snapshots (`forceRefresh = true`) so the SavedVariables capture reflects the click moment, not a stale cache.
