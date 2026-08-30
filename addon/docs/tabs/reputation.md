# Reputation tab

Faction × character reputation matrix.

## Purpose

See standing and progress for every tracked faction across alts; sort by faction or by character; optionally open Zygor reputation guides.

## Layout

- Rows = factions; columns = characters.
- Per-cell standing label and progress bar.
- Faction name filter to reduce visible rows.
- Settings panel for pin/hide and character sort (same pattern as Gear).
- Score-sort row (level / iLvl / played / gear score) for column ordering.

## Sorting

- Sort character columns by a selected faction’s value.
- Sort faction rows by a selected character’s value.
- Handles mixed/legacy reputation data and undiscovered factions.

## Integrations

- When Zygor Guides Viewer is installed, faction rows can open matching reputation guides.

## Data source

DataStore reputations (schema v2). Settings: `AltArmyTBC_ReputationSettings`.
