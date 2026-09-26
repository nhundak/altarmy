"""WoW: Forever's Legacy talents that change what crafting earns or costs.

Characters carry every Legacy talent the addon saw as (spell id, rank); only the ones here have an effect.
The spell ids are Forever's DB2 `TraitDefinition.SpellID`s (TraitSystem 45, the Legacy trees 1187-1189).
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

MASTER_CHEF = 1225457
BARTERING = 1225459


@dataclass(frozen=True)
class LegacyTalent:
    spell_id: int
    name: str
    max_rank: int
    per_rank: float  # extra_result: chance of one extra result; vendor_discount: percent off
    effect: str  # extra_result | vendor_discount
    profession: str = ""  # extra_result: the profession whose crafts it applies to


LEGACY_TALENTS: dict[int, LegacyTalent] = {
    t.spell_id: t
    for t in (
        LegacyTalent(MASTER_CHEF, "Master Chef", 5, 0.10, "extra_result", "Cooking"),
        LegacyTalent(BARTERING, "Bartering", 2, 5, "vendor_discount"),
    )
}


def known(talents: Iterable[tuple[int, int]]) -> list[tuple[LegacyTalent, int]]:
    """The registered talents among `talents`, each with its rank (capped at its max), in their order."""
    return [(t, min(rank, t.max_rank)) for spell_id, rank in talents if (t := LEGACY_TALENTS.get(spell_id))]


def extra_results(talents: Iterable[tuple[int, int]]) -> tuple[tuple[str, float], ...]:
    """(profession, chance of one extra result per craft) for each such talent."""
    return tuple(
        (t.profession, t.per_rank * rank) for t, rank in known(talents) if t.effect == "extra_result"
    )


def vendor_discount(talents: Iterable[tuple[int, int]]) -> int:
    """Percent off vendor prices."""
    return round(sum(t.per_rank * rank for t, rank in known(talents) if t.effect == "vendor_discount"))
