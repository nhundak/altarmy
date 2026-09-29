# External auction house price feeds

Which third-party sources could supply auction house prices to `altarmy-profit`, beside the addon scans
users upload. Surveyed 2026-09-26; every claim below was checked against the live site or API that day
unless marked otherwise. The hosted plan's decision that addon uploads are the primary source
([HOSTED_PLAN.md](HOSTED_PLAN.md), section 1) stands; this file is about what could be added on top.

## Summary

- **Blizzard's Game Data API serves no auction data for Classic Era, Anniversary or Forever.** The
  Era/Anniversary auction endpoints have returned 404 since late 2024 (Blizzard: "on the radar, no
  ETA", March 2025, nothing since). Forever has no namespace at all. Every feed that resells Blizzard
  data (TradeSkillMaster, Undermine Exchange, Saddlebag, AtlasForge) inherits this, whatever its landing
  page says. `scripts/probe_blizzard_api.py` is the check to rerun before assuming this is still true.
- **Forever beta prices exist only as crowdsourced scans**, collected by four fan sites with their own
  addons. Three of them have no API. **AHledger** has a documented, free, keyed API and is the prime
  candidate for a Forever feed.
- **Nothing helps TBC Anniversary today.** Its only sources are addon scans, ours or anyone's.

## AHledger (implemented 2026-09-27)

`src/altarmy_profit/ahledger.py`, run hourly as `altarmy-profit ahledger`. Findings while building it:

- **Row order is `item:median:minBuyout:quantity:median7d:median30d:low30d:high30d`**: the median comes
  first (the developers page's "Row: item id, median, minimum buyout, quantity, 7 day median, 30 day
  median, 30 day low, 30 day high"). The table below had them swapped at first.
- The header's unix time equalled the newest scan's `observedAt` to the second (Wool Cloth, 2026-09-27
  07:12:36Z), so it is the time of the newest scan in the table. Rows carry no time of their own; only
  `/v1/prices/{market}/{item}` gives an item's `latest.observedAt`, and the poller never calls it (one
  request per market an hour, to stay well clear of the rate limit). Its hourly `p25` was tried as the
  buy price for rows whose listing median is far above the min buyout, and dropped (2026-09-29): with a
  handful of auctions its percentiles count listings, not units, so a 64-unit market of two auctions
  priced Mana Potions at the dear one. Reagents are bought at the min buyout. It keeps each market's last
  table
  and records only rows new or changed since, at the new table's time: off by at most the gap between
  tables. A market's first table is recorded as seen when fetched; it starts the history, and uploads
  come after it.
- **Auctionator on Forever names no faction.** Forever's 12.x client loads Auctionator's modern AH code
  (`Source_ModernAH`), whose price database key is `GetNormalizedRealmName()` alone; the legacy code that
  appends `UnitFactionGroup` loads only on vanilla, tbc and wrath clients. Nothing in `Auctionator.lua`
  names the faction, so uploads take it from the uploader's characters on the realm. AHledger's markets
  are per faction and map onto the same houses.

## AHledger (survey)

Site: https://ahledger.com/wow-forever. API docs: https://ahledger.com/developers. Terms:
https://ahledger.com/terms. Run by Hubrig Crew Marketing LLC; the site started in 2026.

How it gets data: players run the AHledger addon at the auction house and a desktop "AHledger sync"
uploads the scan under an upload key. Each scan becomes rows in the market's time series, then hourly and
daily rollups and 7/30/90-day medians. For retail it polls Blizzard's API instead (its `/health` shows
those pollers), so if Blizzard ever adds a Forever namespace it would switch sources and keep working.

The API, as verified on 2026-09-26:

| Call | Returns |
|------|---------|
| `GET https://api.ahledger.com/v1/markets` | every market: `id`, `game`, `ruleset`, `faction`, `region`, `label` |
| `GET /v1/pricetable/{market}` | every priced item as text: header `AHL1\|forever/normal/horde/us\|<unix time>\|<count>`, then `item:median:minBuyout:quantity:...` lines (about 1,900 items, 68 KB, 5-minute cache) |
| `GET /v1/prices/{market}/{itemId}?range=7d` | `latest` (`observedAt`, `source`, `minBuyout`, `median`, `quantity`, `auctions`, `median7d`, `median30d`, `median90d`) and a `series` of hourly points (`min`, `median`, `p25`, `p75`, `quantity`, `auctions`); ranges 24h, 7d, 30d, 90d |
| `GET /v1/items/{itemId}?game=forever` | item name, quality, class, level, vendor value, icon |
| `GET /health` | database, workers, backup age, ingestion lag per polled market |

- Markets are `game.ruleset.faction.region`: six Forever markets (`forever.normal.alliance.us`,
  `forever.normal.horde.us`, `forever.pvp.*.us`, `forever.rp.*.us`); Normal and PvP had scans, RP none.
- Prices are integer copper. Wool Cloth (2592) on Normal Horde had a scan at 06:25 UTC on the survey
  day, with several scans a day in the series: the beta data is live.
- No key needed. A key (from the account page, sent as a Bearer token or `x-ahl-api-key`) moves the
  limit from per IP to per account. Limit 300 requests per minute, 429 with `Retry-After`; responses
  carry `Cache-Control`. During the beta, breaking changes keep the old version for at least 30 days and
  are announced on the developers page.
- Terms: free for personal or commercial use on two conditions: credit AHledger with a link to
  ahledger.com wherever the data is shown, and do not present it as your own scan or resell it as a
  feed. Paid Trader and Desk plans exist for the site's own features, not for the API.

Fit with this app:

- The price table is one request per market and maps straight onto `prices.record_snapshot`: one
  `price_snapshots` row with a new source (`ahledger`), `min_buyout` from the table, `seen_at` from the
  header's time. Its `median7d` and `median30d` cap the sell price (`price_current.sell_cap`, stored
  only when below the min buyout: a lone absurd ask); our own `price_daily` stays the basis of
  `median_7d`.
- **Markets are per ruleset and faction, not per realm.** That matches the beta, which has one realm per
  ruleset (`ClassicBetaPvE`, `ClassicBetaPvP2`), but `auction_houses` is keyed by realm and faction. If
  launch brings several realms per ruleset, AHledger's numbers would be pooled across them. Decide then
  whether to map one AHledger market onto every realm of its ruleset, or to add a ruleset-level house.
- Treat it as an upload: screen it with `prices.screen` like any other scan, record it as a snapshot so
  the newest `seen_at` wins, and show the credit link wherever its prices appear (the terms require it).
- A single-operator fan site is a dependency risk: keep our own uploads primary and let the feed fill
  realms nobody has scanned.

## Everything else

### TradeSkillMaster

https://tradeskillmaster.com/public-data. The keyed "Public Web API" (realm-api, pricing-api, OAuth
tokens) no longer exists: the support article now describes only static CSVs, and the Swagger page at
pricing-api.tradeskillmaster.com has no spec behind it.

- CSVs at `https://public-data.tradeskillmaster.com/{gameType}/{region}/realm/{realmSlug}/items.csv`
  plus `{gameType}/{region}/region/items.csv`. Game types that answer: `retail` and `classic`. Tried and
  404: `mop`, `era`, `classic-era`, `anniversary`, `classicann`, `sod`, `hardcore`.
- Classic realm slugs are realm plus faction (`whitemane-horde`, `mankrik-alliance`). Anniversary slugs
  (`nightslayer-alliance`, `dreamscythe-horde`) 404.
- Per-realm columns: `itemId,name,marketValue,minBuyout,recent,historical,updatedAt`; region columns:
  `marketValue,historical,avgSalePrice,saleRate,soldPerDay`. Copper integers.
- Every Classic per-realm row has an **empty `updatedAt`**, consistent with frozen snapshots from before
  Blizzard's endpoints died. Retail rows carry the current hour.
- "No rate limits" is false: Cloudflare answered 429 (error 1015) after about four quick requests.
- No license text; for websites and tools TSM asks to be contacted.

Verdict: nothing for Anniversary or Forever, and if Blizzard's endpoints return, a Blizzard poller of our
own gets the same data fresher and under clearer terms.

### Blizzard-derived sites (no Anniversary or Forever data)

- **Undermine Exchange** (https://undermine.exchange/api.html): retail only, says so explicitly. Free tier
  behind a Patreon login, 3,000 points per hour, hourly snapshots, 14-day hourly history. The best
  designed of the paid feeds, but the wrong game.
- **Saddlebag Exchange** (https://saddlebagexchange.com/wow): retail and "US/EU Classic" via Blizzard's
  API, so Classic is dead there too. Its addon exports the user's own auctions, not scans.
- **AtlasForge** (https://atlasforge.gg/wow-classic/auctions): lists Era, Hardcore, SoD and Anniversary
  realms, with a banner that auction data is unavailable while Blizzard's API is down. No API.
- **TheWoWDB** (https://thewowdb.com/): retail from Blizzard, plus crowdsourced Forever beta scans from
  its own addon (one connected realm, about 2,450 items). One person runs it; no API or export.
- **WoWAuctions.net**: MoP Classic and Era only, free, ad-supported, no API, source undisclosed.
- **NexusHub**: gone; the domain no longer resolves.

### Other Forever beta sites (no API)

- **Booty Bay Broker** (https://bootybaybroker.com/forever): Forever prices from player scans uploaded by
  a desktop companion. Its FAQ says the code is on GitHub and mentions API endpoints, but no repository
  was found, the CurseForge "Companion" addon only exports inventory as a paste code, and Cloudflare
  blocks every scripted request to the site (403 challenge page). Its claim that TBC Anniversary is
  "sourced hourly from TSM" contradicts what TSM publishes. Not something to depend on.
- **WarcraftForever.games** (https://warcraftforever.games/ah): ForeverAH addon scans of one realm
  (Classic Beta PvP 2, both factions), 16 scans by 2026-09-21. Fan site, no API.

### Blizzard's own API

Unchanged from [HOSTED_PLAN.md](HOSTED_PLAN.md) section 14: `dynamic-classicann-*` lists the Anniversary
realms and each realm's three houses, and every house 404s; Era is the same; Forever has no namespace.
Forum threads: [Era endpoints 404](https://us.forums.blizzard.com/en/blizzard/t/404-for-all-classic-era-namespace-auction-house-endpoints/54307)
(March to August 2025) and [Thunderstrike auction API](https://us.forums.blizzard.com/en/blizzard/t/tbc-classic-anniversary-thunderstrike-auction-api/58703)
(June 2026). Forever runs on the modern 12.x client, so a namespace may appear at or after its launch
(2026-11-04); rerun `scripts/probe_blizzard_api.py` with a Forever namespace guess when it does.

## Status

1. Done (2026-09-27): each AHledger market maps to its ruleset's realm (`GameVersion.ahledger_realms`; one
   realm per ruleset at launch too, so edit the map when launch realms are named) and faction.
2. Done: source `ahledger`, the hourly `ahledger` job (at :20, before the merge), screened like uploads
   with a fixed trust; the newest capture wins against uploads either way.
3. Done: the price freshness line and the Upload page's coverage credit AHledger with a link.
4. Keep the Blizzard probe as the trigger for a first-party poller; it supersedes any third party.
5. Optional: ask AHledger (contact form) for a per-row observed time in the price table, which would date
   changes exactly instead of to within a poll.
