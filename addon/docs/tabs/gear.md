# Gear tab

Equipment grid across characters, plus item-check, compare, and upgrade workflows.

## Purpose

Compare what each alt is wearing; drop an item to see who can use it and how it scores against equipped gear; get upgrade alerts in the world.

## Layout

- Rows = equipment slots; columns = characters.
- Side settings for sort, pin/hide, icon size, and spacing.
- Item-check / compare panels when an item is focused.

## Grid

- Hover tooltips on equipped items; shift-click inserts item links into chat.
- Character ordering: primary/secondary sort, show self first, pin/hide.
- Appearance: icon size (small/medium/large), spacing (compact/normal/comfortable).
- Score-sort row: sort columns by character level, average item level, time played, or gear score (TacoTip / GearScoreTBCClassic when loaded).

## Item check (“who can use this”)

- Drag/drop (or focus) an item to rank characters by likely usability.
- Headers show class / equip / level fit hints.

## Compare panel

- Select a character column (and slot) while an item is focused.
- Stat delta rows vs equipped piece; dual-wield offhand DPS is scaled to match upgrade scoring.
- Debug Dump button when `/altarmy debug on` — see [COMPARE_PANEL_DEBUG_DUMP.md](../COMPARE_PANEL_DEBUG_DUMP.md).

## Upgrade scoring and alerts

- Built-in spec scales (Pawn-style weights) for “is this an upgrade?”
- Optional gear-score providers for scoring and missing-data hints.
- Chat alerts (clickable) for loot, Need/Greed rolls, quest rewards, and level-up upgrades for the current character and/or alts.
- Quest reward overlays on turn-in and quest log (upgrade vs vendor).
- Toggles live under Interface Options → AltArmy → **Gear**.

## Data source

DataStore equipment, containers (for usability context), talents (spec warnings), gear score modules. Settings: `AltArmyTBC_GearSettings`. Options: [options.md](options.md).
