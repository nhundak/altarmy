"""Item tooltip numbers from the client's DB2 tables: stats, armor and weapon damage (pure, no I/O).

ItemSparse does not hold an item's stats, only *allocations*: a stat type and a weight out of 10000 per
slot, scaled by RandPropPoints for the item's level, quality and equip slot group. Armor and weapon
damage are not on the item at all but in per-item-level tables. Ingest parses the tables into
`GameTables`, `compute` turns one item's `ItemSpec` into the tooltip lines the game shows, and the
results are stored denormalized on `items` (rendered text: one stat-name table, one set of level-cap
rating divisors and one rounding policy, next to their tests).

Combat ratings (hit, crit, dodge, ...) are shown as percentages at level 60, using divisors from the
client's GameTables (which wago.tools does not serve, so they are hard-coded here; hit and crit verified
against Wowhead's Classic tooltips). At any other level cap ratings are shown raw, as TBC does.
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

Quality7 = tuple[float, ...]  # a table row's Quality_0..6 (or Qualitymod_0..6): poor .. artifact
Points5 = tuple[int, ...]  # RandPropPoints' five slot-group columns
LEVEL_60 = 60  # the level cap whose rating divisors are known


@dataclass(frozen=True)
class Effect:
    """A green tooltip line: `trigger` is "Use", "Equip" or "Chance on hit"."""

    trigger: str
    text: str


@dataclass(frozen=True)
class ItemSpec:
    """What Item and ItemSparse say about one item."""

    class_id: int
    subclass_id: int
    quality: int
    item_level: int
    inventory_type: int
    delay_ms: int
    dmg_variance: float
    stats: tuple[tuple[int, int], ...]  # (StatModifier_bonusStat_n, StatPercentEditor_n); -1 types dropped


@dataclass(frozen=True)
class GameTables:
    """The DB2 lookups the formulas need, parsed by ingest. Any mapping may be empty (an older client, or
    a table the build does not serve): the fields it feeds then read 0."""

    rand_prop_points: Mapping[int, tuple[Points5, Points5, Points5]]  # ilvl -> (epic, superior, good)
    armor_total: Mapping[int, tuple[float, float, float, float]]  # ilvl -> cloth, leather, mail, plate
    armor_quality: Mapping[int, Quality7]  # ilvl -> Qualitymod_q
    armor_location: Mapping[int, tuple[float, float, float, float]]  # inventory type -> cloth .. plate
    shield: Mapping[int, Quality7]  # ilvl -> a shield's armor by quality
    damage: Mapping[str, Mapping[int, Quality7]]  # DAMAGE_TABLES key -> ilvl -> DPS by quality


EMPTY_TABLES = GameTables({}, {}, {}, {}, {}, {})


@dataclass(frozen=True)
class Computed:
    """One item's tooltip numbers and lines."""

    armor: int
    dmg_min: int
    dmg_max: int
    dps: float
    stats: tuple[str, ...]  # white lines: "+18 Strength", "+25 Fire Resistance"
    effects: tuple[Effect, ...]  # green lines from the stats (spell effects are appended by ingest)


CLASS_WEAPON = 2
CLASS_ARMOR = 4
INV_CHEST = 5
INV_ROBE = 20
INV_TWO_HAND = 17
SUBCLASS_SHIELD = 6
ARMOR_TYPES = {1: 0, 2: 1, 3: 2, 4: 3}  # armor subclass -> column: cloth, leather, mail, plate
RANGED_SUBCLASSES = {2, 3, 16, 18}  # bow, gun, thrown, crossbow
SUBCLASS_WAND = 19
DAMAGE_TABLES = ("one_hand", "two_hand", "ranged", "wand")

# InventoryType -> RandPropPoints column group: 0 head/chest/robe/legs/two-hand, 1 shoulder/waist/feet/hands/
# trinket, 2 neck/wrist/finger/shield/back/held in off-hand, 3 one-hand weapons, 4 ranged/thrown/relic.
SLOT_INDEX: Mapping[int, int] = {
    1: 0,
    5: 0,
    7: 0,
    17: 0,
    20: 0,
    3: 1,
    6: 1,
    8: 1,
    10: 1,
    12: 1,
    2: 2,
    9: 2,
    11: 2,
    14: 2,
    16: 2,
    23: 2,
    13: 3,
    21: 3,
    22: 3,
    15: 4,
    25: 4,
    26: 4,
    28: 4,
}

# White "+{n} <stat>" lines, by ItemSparse stat type (the client's ITEM_MOD enum).
STAT_NAMES: Mapping[int, str] = {
    0: "Mana",
    1: "Health",
    3: "Agility",
    4: "Strength",
    5: "Intellect",
    6: "Spirit",
    7: "Stamina",
    51: "Fire Resistance",
    52: "Frost Resistance",
    53: "Holy Resistance",
    54: "Shadow Resistance",
    55: "Nature Resistance",
    56: "Arcane Resistance",
}

# Green "Equip:" lines whose number is the stat value itself.
EQUIP_TEXT: Mapping[int, str] = {
    38: "+{n} Attack Power.",
    39: "+{n} ranged Attack Power.",
    41: "Increases healing done by spells and effects by up to {n}.",
    42: "Increases damage done by magical spells and effects by up to {n}.",
    43: "Restores {n} mana per 5 sec.",
    45: "Increases damage and healing done by magical spells and effects by up to {n}.",
    46: "Restores {n} health per 5 sec.",
    47: "Decreases the magical resistances of your spell targets by {n}.",
    48: "Increases the block value of your shield by {n}.",
    84: "Increases damage done by Holy spells and effects by up to {n}.",
    85: "Increases damage done by Fire spells and effects by up to {n}.",
    86: "Increases damage done by Nature spells and effects by up to {n}.",
    87: "Increases damage done by Frost spells and effects by up to {n}.",
    88: "Increases damage done by Shadow spells and effects by up to {n}.",
    89: "Increases damage done by Arcane spells and effects by up to {n}.",
}

# Combat ratings: name (for the raw "Increases your <name> rating by {n}." line), the level-60 text and
# the level-60 rating per 1% (0: no conversion known, so the raw line is used at every level).
RATINGS: Mapping[int, tuple[str, str, float]] = {
    12: ("defense", "Increased Defense +{n}.", 0),
    13: ("dodge", "Increases your chance to dodge an attack by {pct}%.", 13.8),
    14: ("parry", "Increases your chance to parry an attack by {pct}%.", 13.8),
    15: ("shield block", "Increases your chance to block attacks with a shield by {pct}%.", 5),
    31: ("hit", "Improves your chance to hit by {pct}%.", 10),
    32: ("critical strike", "Improves your chance to get a critical strike by {pct}%.", 14),
    36: ("haste", "", 0),
    37: ("expertise", "", 0),
    44: ("armor penetration", "", 0),
}

BONUS_ARMOR = 50  # added to the table armor, no line of its own


def _round(x: float) -> int:
    """Half-up, as the client rounds (Python's round is half-even)."""
    return math.floor(x + 0.5)


def stat_values(spec: ItemSpec, tables: GameTables) -> list[tuple[int, int]]:
    """(stat type, value) per allocation, in the item's order; empty when the item level has no
    RandPropPoints row or the slot is not one that carries stats."""
    points = tables.rand_prop_points.get(spec.item_level)
    slot = SLOT_INDEX.get(spec.inventory_type)
    if points is None or slot is None:
        return []
    group = points[0] if spec.quality >= 4 else points[1] if spec.quality == 3 else points[2]
    if slot >= len(group):
        return []
    return [(stat, _round(weight * group[slot] / 10000)) for stat, weight in spec.stats if stat >= 0]


def armor(spec: ItemSpec, values: Sequence[tuple[int, int]], tables: GameTables) -> int:
    """The armor line's number: the tables' armor for cloth/leather/mail/plate and shields, plus bonus
    armor."""
    bonus = sum(v for stat, v in values if stat == BONUS_ARMOR)
    if spec.class_id != CLASS_ARMOR:
        return bonus
    ilvl, q = spec.item_level, spec.quality
    if spec.subclass_id == SUBCLASS_SHIELD:
        row = tables.shield.get(ilvl)
        return (_round(row[q]) if row is not None and q < len(row) else 0) + bonus
    col = ARMOR_TYPES.get(spec.subclass_id)
    if col is None:
        return bonus
    inv = INV_CHEST if spec.inventory_type == INV_ROBE else spec.inventory_type
    total = tables.armor_total.get(ilvl)
    quality = tables.armor_quality.get(ilvl)
    location = tables.armor_location.get(inv)
    if total is None or quality is None or location is None or q >= len(quality):
        return bonus
    return _round(total[col] * quality[q] * location[col]) + bonus


def damage_table(subclass_id: int, inventory_type: int) -> str:
    """Which ItemDamage table a weapon's DPS is in."""
    if subclass_id in RANGED_SUBCLASSES:
        return "ranged"
    if subclass_id == SUBCLASS_WAND:
        return "wand"
    return "two_hand" if inventory_type == INV_TWO_HAND else "one_hand"


def damage(spec: ItemSpec, tables: GameTables) -> tuple[int, int, float]:
    """(min, max, DPS) of a weapon; zeros for anything else or an unknown item level."""
    if spec.class_id != CLASS_WEAPON or spec.delay_ms <= 0:
        return 0, 0, 0.0
    table = tables.damage.get(damage_table(spec.subclass_id, spec.inventory_type), {})
    row = table.get(spec.item_level)
    if row is None or spec.quality >= len(row):
        return 0, 0, 0.0
    dps = row[spec.quality]
    average = dps * spec.delay_ms / 1000
    spread = spec.dmg_variance / 2
    return _round(average * (1 - spread)), _round(average * (1 + spread)), round(dps, 2)


def _percent(value: int, divisor: float) -> str:
    return f"{round(value / divisor, 1):g}"


def stat_lines(values: Sequence[tuple[int, int]], max_level: int) -> tuple[list[str], list[Effect]]:
    """The white stat lines and the green Equip lines for the stat values, in the item's order. Unknown
    stat types (and bonus armor, which is in the armor line) produce nothing."""
    white: list[str] = []
    green: list[Effect] = []
    for stat, n in values:
        if n == 0:
            continue
        if stat in STAT_NAMES:
            white.append(f"{n:+d} {STAT_NAMES[stat]}")
        elif stat in EQUIP_TEXT:
            green.append(Effect("Equip", EQUIP_TEXT[stat].format(n=n)))
        elif stat in RATINGS:
            name, text, divisor = RATINGS[stat]
            if text and max_level == LEVEL_60:
                pct = _percent(n, divisor) if divisor else ""
                green.append(Effect("Equip", text.format(n=n, pct=pct)))
            else:
                green.append(Effect("Equip", f"Increases your {name} rating by {n}."))
    return white, green


def compute(spec: ItemSpec, tables: GameTables, max_level: int = LEVEL_60) -> Computed:
    """Everything the tooltip shows for one item that the tables can tell."""
    values = stat_values(spec, tables)
    dmg_min, dmg_max, dps = damage(spec, tables)
    white, green = stat_lines(values, max_level)
    return Computed(armor(spec, values, tables), dmg_min, dmg_max, dps, tuple(white), tuple(green))
