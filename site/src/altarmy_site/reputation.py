"""The reputations that change what city vendors charge.

A vendor charges less to a character in good enough standing with the vendor's faction; how much at each
standing is the game version's `GameVersion.reputation_discounts`. Only the two sides' home factions count:
every vendor in the city presets whose faction has a reputation belongs to one of them (the gnomes and the
trolls have no capital of their own, but their vendors stand in Ironforge, Stormwind and Orgrimmar). The
Alt Army addon's export sends the same eight, and only they are stored.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping

# Faction ids (DB2 `Faction`, the same in every game version) and their names.
CITY_FACTIONS: dict[int, str] = {
    72: "Stormwind",
    47: "Ironforge",
    69: "Darnassus",
    54: "Gnomeregan Exiles",
    76: "Orgrimmar",
    68: "Undercity",
    81: "Thunder Bluff",
    530: "Darkspear Trolls",
}
HATED, NEUTRAL, HONORED, EXALTED = 1, 4, 6, 8  # standing ids, as the game numbers them


def city_standings(pairs: Iterable[tuple[int, int]]) -> tuple[tuple[int, int], ...]:
    """The (faction id, standing) pairs among `pairs` that are a `CITY_FACTIONS` faction at a real standing
    (Hated to Exalted), by faction id; a faction given twice keeps its last standing."""
    kept = {f: s for f, s in pairs if f in CITY_FACTIONS and HATED <= s <= EXALTED}
    return tuple(sorted(kept.items()))


def vendor_discounts(
    standings: Iterable[tuple[int, int]], schedule: Mapping[int, int]
) -> tuple[tuple[int, int], ...]:
    """(faction id, percent off at that faction's vendors) for each standing `schedule` (standing ->
    percent) gives a discount, by faction id."""
    return tuple((f, schedule[s]) for f, s in sorted(standings) if schedule.get(s, 0) > 0)
