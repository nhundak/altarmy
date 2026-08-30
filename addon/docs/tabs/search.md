# Search tab

Header Search mode: find items and recipes across characters (and optionally guildmates).

## Purpose

Locate items in bags, bank, and mail snapshots; find known recipes; filter by CraftLib skill/difficulty when CraftLib is present.

## Access

- Header search box on the main window always available; typing switches into Search mode.
- Not a top-level tab strip button.

## Results

- Categories: Items, Recipes (toggles).
- Virtualized list for large result sets.
- Item rows: grouped with aggregate totals; location suffixes (Bags / Bank / Mail / equipped / keyring).
- Delayed “You may also be interested in” section (broader text / tooltip-aware matching).
- Shift-click: item links; recipe/spell links when available.

## Settings

- Realm filter guidance (respects global realm filter).
- Optional CraftLib filters: recipe level range, difficulty bands, source types.
- Guildmate-shared recipes merged into recipe results when guild sharing data is available (presence / whisper helpers).
- Specialist yield-bonus markers (alchemy / cloth) when CraftLib is available.

## Data source

Search index/engine over DataStore containers, mail, professions/recipes; guild recipes via guild-share receive store. Settings: `AltArmyTBC_SearchSettings`.
