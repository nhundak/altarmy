# Summary tab

Character overview list for the account (respecting the global realm filter).

## Purpose

See levels, rest XP, money, played time, and last online at a glance; pin/hide characters; spot missing gathered data.

## Layout

- Scrollable character table with a totals row.
- Settings panel for pin/hide and related display options.
- Global realm filter (Options / General) limits which characters appear.

## Columns

| Column | Notes |
|--------|--------|
| Name | Class-colored with class icon; bank-alt icon when flagged |
| Level | Fractional level support |
| Rest XP | Rested experience |
| Money | Bags + mail gold |
| Played | Time played |
| Last online | Relative last logout |
| Warning | Single `!` when data has not been gathered yet (tooltip lists actions) |

Click headers to sort ascending/descending.

## Character visibility

- Pin / hide via Summary settings.
- Bank alts: icon on the name column; optional hide-from-Summary (Options → Characters).
- Click bank-alt icon to jump to Options for that character.

## Missing data

One gold `!` per character with a de-duped action list (`GetMissingDataInfo`). Covers never-gathered modules, stale reputation schema, professions needing an open window, talents, etc. See the summary-missing-data Cursor skill for the design contract.

## Data source

`SummaryData` / `Characters` over DataStore character, money, mail gold, and related modules. Settings: `AltArmyTBC_SummarySettings`.
