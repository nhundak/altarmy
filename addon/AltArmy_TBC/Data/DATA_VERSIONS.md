# Data Version Changelog

This file documents the data format versions used by AltArmy TBC's DataStore.
Each module has its own version number that is incremented when the storage format changes.

Canonical table: `DATA_VERSIONS` in [`DataStore.lua`](DataStore/DataStore.lua).

## Module Versions

### character (v1)
- **v1**: Initial version. Stores name, realm, level, class, classFile, race, faction, money, xp, xpMax, restXP, played, lastLogout, lastUpdate.

### guildMembership (v1)
- **v1**: Guild name / membership fields on the character for guild-tab and sharing eligibility (written with character scans).

### containers (v2)
- **v1**: Initial version. Stores bag/bank contents in `char.Containers[bagID]` with `links` and `items` tables. Also stores `bagInfo` and `bankInfo` summaries.
- **v2**: Also stores equipped bag identity on inventory bags 1–4 and bank bags 5–11 as `bagLink` / `bagItemID` (backpack, keyring, and main bank container are not items).

### equipment (v1)
- **v1**: Initial version. Stores equipped gear in `char.Inventory[slot]` (slots 1-19). Stores full link if enchanted, otherwise itemID.

### gearScores (v1)
- **v1**: Cached gear-score values from optional providers (TacoTip / GearScoreTBCClassic) for score-sort and missing-data checks.

### professions (v1)
- **v1**: Initial version. Stores profession skills in `char.Professions[name]` with rank, maxRank, isPrimary/isSecondary, and Recipes table. Primary profession names in `char.Prof1` and `char.Prof2`. Cooldown / specialization state lives alongside profession data.

### reputations (v2)
- **v1**: Initial version. Stored `char.Reputations[factionID]` using a broken `FACTION_STANDING_THRESHOLDS[standingID]` mix; cross-standing sort/order was wrong.
- **v2**: Stores `{ s = standingID, e = earnedValue, b = bottomValue, t = topValue }` per faction from `GetFactionInfo` so labels, colors, bars, and sort match the game.

### mail (v1)
- **v1**: Initial version. Stores mailbox contents in `char.Mails[]` with icon, itemID, count, sender, link, money, subject, lastCheck, daysLeft, returned.

### auctions (v1)
- **v1**: Initial version. Stores auction listings in `char.Auctions[]` and bids in `char.Bids[]` with itemID, count, bidAmount, buyoutAmount, timeLeft.

### currencies (v1)
- **v1**: Initial version. Stores TBC currency item counts in `char.Currencies[itemID] = count`.

### talents (v1)
- **v1**: Talent tab point totals for primary-spec inference (gear upgrade / compare warnings and missing-data).

### levelHistory (v1)
- **v1**: Level-up milestones in `char.levelHistory.milestones[level]` with `reachedAt`, `playedTotal`, `playedLevel`, `zone`, `money`, `restXP`, `gear`, `deaths` (bracket count). Death log in `char.levelHistory.deaths[]` with `at`, `level`, `zone`, `playedTotal`, `killerName`, `killerGuid`. Account import gate `levelHistoryImport.questieAt` and `levelHistoryImport.nitAt`; per-character `levelHistory.meta.importedRxpAt`.
- **OrphanImports**: Imports for characters AltArmy has never scanned live in `OrphanImports.levelHistory[realm][name]` (same `levelHistory` shape). Merged into `Characters` on first login via `ScanCharacter`. Not shown in Summary/Gear UI.

## Domains without `dataVersions` keys

These are persisted on the character (or in other SavedVariables) but are not tracked in `DATA_VERSIONS` today:

- **Raid lockouts** — `char.RaidLockouts` / `lastLockoutScan` via `DataStoreLockouts` (list replaced each scan).
- **Guild share** — `AltArmyTBC_GuildData` and `AltArmyTBC_SharingSettings` (protocol versioning is separate from character `dataVersions`).
