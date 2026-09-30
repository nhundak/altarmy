# Economy tab

Auction-house economics: what each Waylaid Crate costs to buy and fill, and Alt Army's crafting planner on alt-army.com.

## Purpose

Find the cheapest way to earn Merchant's Favor from Waylaid Crates, using the auction house scan Alt Army already takes. Learn what alt-army.com does with that data and how to upload it automatically.

## Availability

**WoW Forever only.** Waylaid Crates, the full auction house scan and alt-army.com's prices exist only there. On TBC Anniversary the side tab is hidden (`Tabs/TabEconomy.lua` checks `DataStore.IsWowForever`), and the tabs below it move up.

## Sub-views

Two sub-views, switched with the tabs that hang above the panel in the toolbar row (`UI/TopTabs.lua`, same as Gear and Cooldowns). The last one used is remembered (`AltArmyTBC_Options.economy.activeView`).

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
- Hovering a row shows the crate's tooltip plus every bundle with its cost, "only N listed" or "not listed".
- A line above the table says how old the scan is and whose auction house it is. The table refreshes when a scan finishes while it is open.
- Merchant's Favor per crate isn't shown. Guides disagree on it, and it may differ by tier or between gathered and crafted crates, so compare crates of the same tier.

**No scan yet** for this realm and faction: the table is replaced by a message to visit an auction house and use the Alt Army scan button, plus a **Scan the auction house automatically when it opens** checkbox. It is the same setting as Options → General → Auction House.

### Supply Chain

A scrolling page about alt-army.com's crafting planner:

1. What the site does: ranks recipes your characters can craft by profit or profit per hour, from Alt Army's auction scans, and plans buying, crafting and mailing across your alts.
2. A carousel of three screenshots (search results, flow chart, detailed steps) with Previous / Next and a caption.
3. How to set up **Alt Army Sync**, the Windows app that uploads `AltArmy_TBC.lua` whenever the game saves it: create an account, download and run the app, sign in.
4. Read-only boxes with the website and download addresses to copy with Ctrl+C.

## Data source

- Prices: `AltArmyTBC_AuctionBook` via `AuctionBook.Latest(realm, faction)` and `AuctionBook.Decode(items)`.
- Crates and bundles: `Data/Economy/WaylaidCrates.lua`, generated from WoW Forever's game data by `python scripts/generate-waylaid-crates.py` (`npm run crates:generate`). It reads the item table in the altarmy-profit repo checked out next to this one (`../wow-profit/data/altarmy-profit.sqlite`). Keeping it current:
  - altarmy-profit's `ingest` reruns the generator whenever it loads Forever data into that SQLite file, so a changed crate list shows up here as an uncommitted change.
  - The pre-commit hook (`.githooks/pre-commit`, enabled by `npm install` or `npm run hooks:install`) runs `--check` (`npm run crates:check`) and blocks a commit while the file is out of date. It skips when the database or Python isn't there.
- Costs and sorting: `Data/Economy/WaylaidCosts.lua` (pure, unit-tested).
- Screenshots: `Textures/Economy/*.tga`, converted from PNGs by `python scripts/convert-economy-screenshots.py`.
