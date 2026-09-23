# Search tab

Toolbar Search mode: find items and recipes across characters (and optionally guildmates).

## Purpose

Locate items in bags, bank, and mail snapshots; find known recipes; filter by CraftLib skill/difficulty when CraftLib is present.

## Access

- The toolbar search box is shown on the Summary tab (and stays while in Search mode); typing switches into Search mode.
- There is no side tab for Search. In Search mode the tab the search started from (Summary) stays highlighted, and clicking any side tab clears the query and leaves Search. Closing Search settings with an empty search box also returns to that tab.
- A native **Filter** dropdown (the Professions-window style) appears left of the search box once it has at least one character; the search box keeps a fixed width. Its menu has **Items**, **Recipes** and **Guild recipes** checkboxes (Guild recipes only when guild sharing is on; greyed out while Recipes is off), then **Advanced** (silver gear icon), which opens the Search settings side panel. The toolbar settings button also opens Search settings and is highlighted while recipe filters are active ("Filters Active", shown left of the Filter button).

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
