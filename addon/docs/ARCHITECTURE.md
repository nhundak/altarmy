# AltArmy TBC — Architecture

High-level structure of the addon: purpose, UI, data layer, and SavedVariables. For the shipped feature catalog see [FEATURES.md](FEATURES.md). For data-layer details see [`AltArmy_TBC/Data/DESIGN.md`](../AltArmy_TBC/Data/DESIGN.md).

## Purpose

AltArmy TBC is an **account-wide alt management** addon for TBC Classic. It:

- Scans and persists character data while you play (event-driven, internal DataStore).
- Shows cross-character dashboards (summary, gear, reputation, cooldowns/lockouts, search, graphs).
- Optionally shares character cards and recipes with guildmates (Guild tab + Search merge).

It is **not** an external DataStore consumer. Persistence lives inside the addon under `AltArmy.DataStore`.

## Layout on disk

| Path | Role |
|------|------|
| `AltArmy_TBC/Core.lua` | Main frame shell, toolbar, side tabs wiring, Search mode overlay |
| `AltArmy_TBC/Tabs/` | Per-tab UI |
| `AltArmy_TBC/UI/` | Theme, minimap, options, shared widgets, onboarding dialogs |
| `AltArmy_TBC/Data/` | DataStore, aggregation, search, guild share, gear/cooldown logic |
| `AltArmy_TBC/Libs/` | Bundled libraries (AceComm, LibDBIcon, etc.) |

Visual language: [`UI/Theme.lua`](../AltArmy_TBC/UI/Theme.lua) — see [UI_DESIGN.md](UI_DESIGN.md).

## Main window

- Native Blizzard window: `PortraitFrameTemplate`, 640 × 484 (the height of Forever's CharacterFrame). It has a close button, and it can be dragged by the title bar and closed with Escape.
- The portrait circle and title (`Alt Army - <Tab>`) follow the active tab.
- Open with `/altarmy` or `/alta`, or the minimap button.
- **Toolbar row** under the title bar: a search slot and the active tab's settings button. The slot holds the global item/recipe search box (`SearchBoxTemplate`) on Summary (`MainTabs` `headerSearch`) and in Search mode. Reputation (faction filter) and Guild (character/profession search) put their own box in the same slot via `AltArmy.PlaceInToolbarSearchSlot`. Gear, Cooldowns and Graphs show no search. In Search mode the row also shows the Items / Recipes / Guildmate recipes checkboxes, and the search box narrows to make room for them.
- Typing in the search box switches the window into **Search mode**, which has no side tab of its own.
- Template availability per client is detected in `UI/NativeUI.lua`, so missing templates fall back to the themed look.

### Side tabs

The tabs are icon flyouts on the right edge (`UI/SideTabs.lua`), anchored like CharacterFrame's mode tabs. Hovering one shows its name.
- Forever: `LargeSideTabButtonTemplate`.
- TBC Anniversary: classic spellbook skill-line tabs.

The order, icons, titles, and each tab's settings button action live in `UI/MainTabs.lua`.

| Tab | Notes |
|-----|--------|
| **Summary** | Character list overview |
| **Gear** | Equipment grid, item check, compare / upgrades |
| **Reputation** | Faction × character matrix |
| **Cooldowns** | Crafting cooldowns + **Raids** lockout sub-view |
| **Graphs** | Level progress over time |
| **Guild** | Shown only when guild sharing is enabled and the realm has a guilded character |

`Tabs/TabCharacters.lua` is an unloaded placeholder. There is no Characters containers tab; inventory is reached via **Search**.

## Data strategy

- **Internal DataStore** (`AltArmy.DataStore`) owns `AltArmyTBC_Data` and scans on WoW events (with delayed rescans where the client loads late).
- Higher layers (`SummaryData`, `Characters`, search/gear helpers) read through DataStore APIs; tabs should not write SavedVariables for character domains.
- Optional addons (Auctionator, CraftLib, TacoTip, GearScoreTBCClassic, RestedXP, Questie, NovaInstanceTracker, Zygor) enrich features when present; they are not required to load AltArmy.

See [DESIGN.md](../AltArmy_TBC/Data/DESIGN.md) and [DATA_VERSIONS.md](../AltArmy_TBC/Data/DATA_VERSIONS.md).

## SavedVariables

Declared in `AltArmy_TBC.toc`:

| Variable | Role |
|----------|------|
| `AltArmyTBC_Data` | Account-wide character / domain data |
| `AltArmyTBC_Options` | Global options (realm filter, bank alts, cooldowns, debug, etc.) |
| `AltArmyTBC_GearSettings` | Gear tab settings |
| `AltArmyTBC_ReputationSettings` | Reputation tab settings |
| `AltArmyTBC_SummarySettings` | Summary tab settings |
| `AltArmyTBC_SearchSettings` | Search settings |
| `AltArmyTBC_GraphSettings` | Graphs tab settings |
| `AltArmyTBC_GuildData` | Received guild-share payloads |
| `AltArmyTBC_SharingSettings` | Own guild-share preferences (opt-in) |

## Document map

- [FEATURES.md](FEATURES.md) — shipped features
- [FEATURE_IDEAS.md](FEATURE_IDEAS.md) — roadmap
- [tabs/](tabs/) — per-tab detail
- [README.md](README.md) — full docs index
