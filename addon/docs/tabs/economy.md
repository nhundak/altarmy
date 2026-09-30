# Economy tab

Every character's currencies side by side, auction-house economics (what each Waylaid Crate costs to buy and fill), and Alt Army's crafting planner on alt-army.com.

## Purpose

See how much of each currency every alt holds. Find the cheapest way to earn Merchant's Favor from Waylaid Crates, using the auction house scan Alt Army already takes. Learn what alt-army.com does with that data and how to upload it automatically.

## Availability

**WoW Forever only.** Waylaid Crates, the full auction house scan and alt-army.com's prices exist only there. On TBC Anniversary the side tab is hidden (`Tabs/TabEconomy.lua` checks `DataStore.IsWowForever`), and the tabs below it move up.

## Sub-views

Three sub-views, switched with the tabs that hang above the panel in the toolbar row (`UI/TopTabs.lua`, same as Gear and Cooldowns). Currency is first and is the default. The last one used is remembered (`AltArmyTBC_Options.economy.activeView`).

### Currency

A grid of currencies (rows) × characters (columns), like the Reputation tab, with columns half again as wide. Its top tab uses the Character window's own Currency side-tab icon (`INV_SideTab_Currency_c60`).

- **Rows:** **Gold** first, above every header: each character's money in gold, silver and copper. When that is too wide for the column, copper is left out, then silver (hover the cell for the full amount). Then every currency any shown character has, grouped under the same headers and in the same order as the Character window's Currency tab. Each currency row has its icon; hovering it shows the game's currency tooltip.
- **Cells:** how much of that currency the character has, e.g. "1,500". A grey 0 means none. A dash means Alt Army hasn't recorded that character's currencies yet (log in on it once). Hovering a cell shows the amount and, for capped currencies, the cap.
- **Sorting:**
  - The score-sort row under the character names (level / item level / played / gear score, as on Gear and Reputation) orders the columns.
  - Clicking a currency sorts the characters by how much of it they have (click again to flip). Clicking the score selector returns to score sorting.
  - Clicking a character's name sorts the currencies within each header by that character's amount: high first, low first, then off.
- **Filter currency** box in the toolbar row, beside the settings button (shown only on this view): shows only the currencies whose name contains the text (case-insensitive; Gold counts as a currency). Headers stay only while one of their currencies matches. Matching text is green, as in other searches. When nothing matches, the grid says so.
- **Settings** (toolbar gear button, shown only on this view): Pin current character, and pin / hide per character, like Reputation. Saved in `AltArmyTBC_Options.economy.currency`. Bank alts are hidden, and the global realm filter applies.
- Characters with no currency data yet still show their gold; their currency cells show a dash.

### Waylaid Crates

A Waylaid Crate is filled with **any one** of the bundles its label lists (for example Apprentice Ore takes 20 Copper Ore or 20 Tin Ore), then turned in for Merchant's Favor. The table lists every Waylaid Crate on the newest Alt Army scan of the current realm and faction's auction house.

| Column | Meaning |
|--------|---------|
| Crate | The shipment (icon; green for crafted-goods crates, white for gathered goods) |
| Crate price | The cheapest crate listed |
| Cheapest fill | The bundle that costs least to buy in full, e.g. "20 x Tin Ore" |
| Fill cost | That bundle bought cheapest-first up the auction house's listings |
| Total | Crate price + fill cost |

- Default order: Total, cheapest first. Every column header sorts, and the choice is saved.
- A bundle counts only if enough units are listed to buy all of it. When none can be, Cheapest fill says **not enough listed** or **none listed**, Total shows a dash, and the crate sorts last.
- The unread **Waylaid Crate** (its shipment is random until the label is read) shows its price only.
- An asterisk marks a cost that reaches the scan's dearest listings. Those are saved together at their cheapest price, so the cost is a close estimate.
- Hovering a row shows the crate's tooltip plus every bundle with its cost, "only N listed" or "not listed", cheapest first (bundles that can't be bought in full at the bottom).
- The row below the table shows, on the left, how old the scan is ("Scanned 12 min ago"): white under 15 minutes, yellow up to 30, red after that. On the right, an **Auto scan when opening AH** checkbox (same setting as Options → General → Auction House). While the auction house is open, a **Scan now** button sits in the middle; it reads "Scan in m:ss" while the game's 15-minute scan cooldown runs (same as the button on the auction house). If the scan found no Waylaid Crates, the table says so. The table refreshes when a scan finishes while it is open.
- Merchant's Favor per crate isn't shown. Guides disagree on it, and it may differ by tier or between gathered and crafted crates, so compare crates of the same tier. What we have measured so far is below.

#### Merchant's Favor: tested in game

Not enough yet to show Favor per crate or rank by gold per Favor. Record new results here.

| Waylaid Crate (quality) | Filled, it became (quality) | Merchant's Favor |
|-------------------------|-----------------------------|------------------|
| Apprentice Curiosities (white) | Sealed Apprentice Crate (white) | 5 |
| Apprentice Fabrics (green) | Sealed Apprentice Crate (green) | 10 |

Early reading: the sealed crate keeps the Waylaid Crate's quality, and within the Apprentice tier green is worth twice white. Untested: Journeyman, Expert and Artisan crates, and whether every crate of one tier and quality gives the same Favor.

**No scan yet** for this realm and faction: the table is replaced by a message to visit an auction house and use the Alt Army scan button, plus a **Scan the auction house automatically when it opens** checkbox. It is the same setting as Options → General → Auction House.

### Supply Chain

A scrolling page about alt-army.com's crafting planner:

1. The title **Put your army to work** with a read-only box holding `https://alt-army.com/profit` to copy with Ctrl+C.
2. What the site does: compares your characters' professions against auction house data to find the most profitable crafts, with price comparisons and step-by-step instructions.
3. A carousel of three screenshots (flow chart, detailed steps, search results), all drawn 280 pixels tall, with small previous / next arrows fixed at the left and right edges of the page.

## Data source

- Currencies: `DataStore:ScanCurrencyList` (`Data/DataStore/DataStoreCurrencies.lua`) reads `C_CurrencyInfo`'s currency list on login and whenever `CURRENCY_DISPLAY_UPDATE` fires. It expands collapsed headers to read them and collapses them again afterwards. Rows and sorting: `Data/Economy/CurrencyGrid.lua` (pure, unit-tested).

- Prices: `AltArmyTBC_AuctionBook` via `AuctionBook.Latest(realm, faction)` and `AuctionBook.Decode(items)`.
- Crates and bundles: `Data/Economy/WaylaidCrates.lua`, generated from WoW Forever's game data by `python scripts/generate-waylaid-crates.py` (`npm run crates:generate`). It reads the item table in the altarmy-profit repo checked out next to this one (`../wow-profit/data/altarmy-profit.sqlite`). Keeping it current:
  - altarmy-profit's `ingest` reruns the generator whenever it loads Forever data into that SQLite file, so a changed crate list shows up here as an uncommitted change.
  - The pre-commit hook (`.githooks/pre-commit`, enabled by `npm install` or `npm run hooks:install`) runs `--check` (`npm run crates:check`) and blocks a commit while the file is out of date. It skips when the database or Python isn't there.
- Costs and sorting: `Data/Economy/WaylaidCosts.lua` (pure, unit-tested).
- Screenshots: `Textures/Economy/*.tga`, converted from PNGs by `python scripts/convert-economy-screenshots.py`.
