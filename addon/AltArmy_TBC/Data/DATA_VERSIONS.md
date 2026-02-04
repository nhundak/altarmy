# Data Version Changelog

This file documents the data format versions used by AltArmy TBC's DataStore.
Each module has its own version number that is incremented when the storage format changes.

## Module Versions

### character (v1)
- **v1**: Initial version. Stores name, realm, level, class, classFile, race, faction, money, xp, xpMax, restXP, played, lastLogout, lastUpdate.

### containers (v1)
- **v1**: Initial version. Stores bag/bank contents in `char.Containers[bagID]` with `links` and `items` tables. Also stores `bagInfo` and `bankInfo` summaries.

### equipment (v1)
- **v1**: Initial version. Stores equipped gear in `char.Inventory[slot]` (slots 1-19). Stores full link if enchanted, otherwise itemID.

### professions (v1)
- **v1**: Initial version. Stores profession skills in `char.Professions[name]` with rank, maxRank, isPrimary/isSecondary, and Recipes table. Primary profession names in `char.Prof1` and `char.Prof2`.

### reputations (v1)
- **v1**: Initial version. Stores faction standings in `char.Reputations[factionID] = earnedValue`.

### mail (v1)
- **v1**: Initial version. Stores mailbox contents in `char.Mails[]` with icon, itemID, count, sender, link, money, subject, lastCheck, daysLeft, returned.

### auctions (v1)
- **v1**: Initial version. Stores auction listings in `char.Auctions[]` and bids in `char.Bids[]` with itemID, count, bidAmount, buyoutAmount, timeLeft.

### currencies (v1)
- **v1**: Initial version. Stores TBC currency item counts in `char.Currencies[itemID] = count`.
