# Options and slash commands

Interface Options panel (AddOns → AltArmy) and user-facing slash commands.

## Options tabs

| Tab | Contents |
|-----|----------|
| **General** | Collapsible sections, drawn like the Keybindings page's (all but Advanced start open): **General** (minimap show/hide; global realm filter, current / all realms), **Guild** (guild data sharing: main, display name, data retention, chat; shown while guild sharing is available), **Auction House** (side by side, half the width each: the **Scan AH automatically** checkbox (scan when the auction house opens) and the scan mode dropdown (`AltArmyTBC_Options.auctionScanMode`): **Prefer full scans** (the default: a full scan when the game allows one, a summary scan otherwise), **Only full scans** (no scan during the 15-minute cooldown: the scan buttons are disabled and the automatic scan does nothing) or **Only summary scans**; a saved "Prefer full scans" checkbox turned off reads as Only summary scans. Its help icon explains that a full scan knows how many units sit at each price but is slower and allowed once every 15 minutes, while a summary scan is fast but less accurate. The Economy tab's summary-scan info tooltip opens the Options here with the dropdown flashed (`flash = "scanMode"`); WoW Forever only) and **Advanced**, last and closed at first (**Read recipes automatically**, on by default: reads the character's missing or out-of-date recipes in the background at login and after learning one, so no profession window has to be opened; its help icon says it is recommended, but can be turned off if the occasional sound of the skill book opening is unwelcome or it causes problems for other addons; with it off, the Summary warning names each profession window to open, even for alts; WoW Forever only). Scrolls when the open sections outgrow the panel |
| **Characters** | Per-character bank-alt flags; delete character data (self-delete protected + confirmation) |
| **Gear** | Gear upgrade notification toggles (current character / alts; loot, quest rewards, etc.) |
| **Cooldowns** | One collapsible section per category (all start open), drawn like the General tab's: UI visibility, alerts, reminder intervals; specialization-related options. On WoW Forever, shows a "work in progress" banner and only the Transmute and Research (Comprehension) categories (the others are TBC-specific crafts), and hides the "Only if Master of Transmutation" toggles; a saved value for them is ignored there |
| **Debug** | Hidden until `/altarmy debug on`; search timing, cooldown scan logging, item stats, guild share verbose, **Clear auction data** (deletes stored auction house scans; keeps the scan cooldown), etc. |

Shared theme with the main UI ([UI_DESIGN.md](../UI_DESIGN.md)).

Options opened on a particular control (for example from the Alt Army scan button's settings icon, or from the guild-sharing prompts) switch to its tab, open only the section it is in (the others close), scroll it into view and flash it.

## Minimap

- Left-click: open/close main window.
- Left-click while holding an item (window closed): opens the window on **Gear → Upgrade Check** with that item loaded for comparison. The next click closes the window as usual.
- Drag: reposition (LibDBIcon).
- Show/hide under General options.

## Slash commands

| Command | Action |
|---------|--------|
| `/altarmy` / `/alta` | Open main UI |
| `/altarmy networth [all] [scale]` | Net worth (vendor + Auctionator); `all` = all realms; scale 0–1 (default 0.9) |
| `/altarmy export` | Export for altarmy-profit (see below; there is no button for it) |
| `/altarmy scan` | Scan the open auction house (same as the **Alt Army scan** button): the kind the scan mode allows now (Options → General → Auction House) |
| `/altarmy debug on` / `off` | Show/hide Debug options tab and enable/suppress debug logging |

Additional `debug …` subcommands exist for developers (mail alerts, compare dump, guild share inject, etc.); they are not part of the product feature surface.

## Export for altarmy-profit

Only `/altarmy export` opens it. An **Export** dialog with one selected line of text (starts with `AAX1:`) and
"Copy this string into the alt army website to upload your data": press Ctrl+C and paste it on the Upload tab of
the altarmy-profit site (alt-army-prod.web.app), which then knows your characters without a SavedVariables
upload or `/reload`. It holds every saved character's realm, full name, GUID, faction, class, level, professions
(rank and max), learned recipe ids, Legacy talents and standing with the eight city factions (the site discounts
vendor prices by reputation), plus the client's interface number and build so the site can tell TBC
Anniversary from Forever. The string is LibDeflate-compressed text built by `Data/ProfitExport.lua`; its
format is documented there, and `spec/fixtures/profit_export_v2.txt` (format v2) is the golden string the site's parser is
tested against (the altarmy-profit repo keeps a copy).

## Related UI

- Bank-alt suggest dialog (auto-detect).
- Guild share onboarding.
- RestedXP quest-reward conflict dialog when RXP and AltArmy upgrade overlays would clash.
