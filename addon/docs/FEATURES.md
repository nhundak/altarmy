# AltArmy TBC — Features

Shipped features in the current codebase. Per-tab detail: [tabs/](tabs/). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Roadmap: [FEATURE_IDEAS.md](FEATURE_IDEAS.md).

## What the addon does

AltArmy TBC is an account-wide alt management addon for TBC Classic that:

- Collects and persists character data automatically while you play.
- Presents cross-character information in tabbed dashboards.
- Supports item and recipe search across characters (optional CraftLib skill/difficulty filters; optional guildmate recipes).
- Tracks profession cooldown readiness, stockpile mailing, and raid/heroic lockouts.
- Graphs leveling progress over calendar and played time.
- Optionally shares character cards and recipes with guildmates.
- Provides configurable filters, sorting, pin/hide, bank-alt flags, and alerts.

## UI design system

- Shared warm bronze / dark panel theme in `AltArmy_TBC/UI/Theme.lua` (see [UI_DESIGN.md](UI_DESIGN.md)).
- All tabs, settings panels, popovers, and Interface Options use the same backdrop recipe and color roles.

## Main UI and access

- Main frame is movable, closable, and registered for Escape closing.
- Open with `/altarmy` or `/alta`.
- Minimap button (left-click toggle, drag to move).
- Header search box switches into Search mode when populated.
- `/altarmy networth [all] [scale]` — vendor + Auctionator AH value across characters (Auctionator required).

## Tabs

| Tab | Doc |
|-----|-----|
| [Summary](tabs/summary.md) | Character overview, totals, missing-data warnings, bank-alt icons |
| [Gear](tabs/gear.md) | Equipment grid, item check, compare panel, upgrade scoring / alerts |
| [Reputation](tabs/reputation.md) | Faction matrix, score-sort, optional Zygor guide links |
| [Cooldowns](tabs/cooldowns.md) | Crafting cooldowns + Raids lockouts, stockpile send / send-all |
| [Search](tabs/search.md) | Items and recipes (header Search mode) |
| [Graphs](tabs/graphs.md) | Level progress charts and history imports |
| [Guild](tabs/guild.md) | Opt-in guild data sharing (conditional tab) |
| [Options](tabs/options.md) | Interface Options + slash commands |

There is no Characters containers tab; inventory is via Search.

## Cross-cutting

### Realm filtering and character visibility

- Global realm filter: current realm only, or all realms.
- Applied across Summary, Gear, Reputation, Search, Cooldowns, and Graphs.
- Per-tab pin/hide (and related sort) settings on major matrix/list tabs.

### Bank alts

- Per-character bank-alt flag in Options (Characters).
- Auto-detect suggest dialog; Summary bank icon; optional hide-from-Summary.
- Stockpile mailing workflows assume a bank-alt source.

### Alerts and reminders

- **Cooldowns:** chat, raid-warning style, or both; per-category reminder intervals; optional specialization-dependent visibility.
- **Gear upgrades:** chat (and clickable links) for loot, Need/Greed, quest rewards, and level-up upgrades for you or alts; quest-reward overlays on turn-in / quest log.
- **Mail expiry:** login chat when any character’s soonest mail returns within 5 days.

### Optional addon integrations

| Addon | Used for |
|-------|----------|
| CraftLib | Recipe skill levels, difficulty bands, Search filters, yield-bonus markers |
| Auctionator | `/altarmy networth` AH pricing |
| TacoTip / GearScoreTBCClassic | Gear score providers for score-sort and upgrades |
| RestedXP (RXPGuides) | Level history import; quest-reward conflict dialog |
| Questie / NovaInstanceTracker | Level history import into Graphs |
| Zygor Guides | Reputation tab guide links |

### Data collection and persistence

Stored under `AltArmyTBC_Data`, `AltArmyTBC_Options`, tab settings tables, `AltArmyTBC_GuildData`, and `AltArmyTBC_SharingSettings` (see [ARCHITECTURE.md](ARCHITECTURE.md)).

Core domains include: character basics, containers/bank, equipment, currencies, professions/recipes, cooldowns/specialization, lockouts, reputations, mail, auctions/bids, talents, level history.

Scanning is event-driven with delayed rescans where needed.
