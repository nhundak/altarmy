# Options and slash commands

Interface Options panel (AddOns → AltArmy) and user-facing slash commands.

## Options tabs

| Tab | Contents |
|-----|----------|
| **General** | Minimap show/hide; global realm filter (current / all realms) |
| **Characters** | Per-character bank-alt flags; delete character data (self-delete protected + confirmation) |
| **Gear** | Gear upgrade notification toggles (current character / alts; loot, quest rewards, etc.) |
| **Cooldowns** | Per-category UI visibility, alerts, reminder intervals; specialization-related options |
| **Debug** | Hidden until `/altarmy debug on`; search timing, cooldown scan logging, item stats, guild share verbose, etc. |

Shared theme with the main UI ([UI_DESIGN.md](../UI_DESIGN.md)).

## Minimap

- Left-click: open/close main window.
- Drag: reposition (LibDBIcon).
- Show/hide under General options.

## Slash commands

| Command | Action |
|---------|--------|
| `/altarmy` / `/alta` | Open main UI |
| `/altarmy networth [all] [scale]` | Net worth (vendor + Auctionator); `all` = all realms; scale 0–1 (default 0.9) |
| `/altarmy debug on` / `off` | Show/hide Debug options tab and enable/suppress debug logging |

Additional `debug …` subcommands exist for developers (mail alerts, compare dump, guild share inject, etc.); they are not part of the product feature surface.

## Related UI

- Bank-alt suggest dialog (auto-detect).
- Guild share onboarding.
- RestedXP quest-reward conflict dialog when RXP and AltArmy upgrade overlays would clash.
