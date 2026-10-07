"""Item stats, armor and damage from the DB2 formulas (verified against Wowhead's Classic tooltips)."""

from altarmy_site import itemstats
from altarmy_site.itemstats import Effect, GameTables, ItemSpec

# RandPropPoints for ilvl 61 as the Forever client has it (epic, superior, good; five slot groups each).
POINTS_61 = ((45, 34, 25, 19, 14), (35, 26, 20, 15, 11), (27, 20, 15, 11, 8))
TABLES = GameTables(
    rand_prop_points={61: POINTS_61, 20: ((60, 40, 30, 20, 10), (40, 30, 20, 15, 8), (30, 20, 15, 10, 6))},
    armor_total={61: (100.0, 200.0, 400.0, 5000.0), 20: (46.4, 90.0, 180.0, 360.0)},
    armor_quality={61: (0.9, 1.0, 1.1, 1.12, 1.13, 1.2, 1.3), 20: (0.9, 1.0, 1.0, 1.1, 1.2, 1.3, 1.4)},
    armor_location={1: (0.1, 0.1, 0.1, 0.1), 5: (1.0, 1.0, 1.0, 1.0), 14: (0, 0, 0, 0)},
    shield={61: (500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0)},
    damage={
        "two_hand": {63: (40.0, 45.0, 50.0, 53.9, 60.0, 80.40234375, 90.0)},
        "one_hand": {20: (5.0, 7.0, 10.0, 12.0, 14.0, 16.0, 18.0)},
        "wand": {20: (5.0, 7.0, 9.0, 11.0, 13.0, 15.0, 17.0)},
    },
)

LIONHEART_HELM = ItemSpec(
    class_id=4,
    subclass_id=4,
    quality=4,
    item_level=61,
    inventory_type=1,
    delay_ms=0,
    dmg_variance=0.0,
    stats=((4, 4000), (32, 6222), (31, 4444), (-1, 0)),
)


def test_lionheart_helm_stats_armor_and_rating_lines() -> None:
    got = itemstats.compute(LIONHEART_HELM, TABLES)
    assert got.armor == 565  # 5000 * 1.13 * 0.1
    assert got.stats == ("+18 Strength",)
    assert got.effects == (
        Effect("Equip", "Improves your chance to get a critical strike by 2%."),
        Effect("Equip", "Improves your chance to hit by 2%."),
    )
    assert (got.dmg_min, got.dmg_max, got.dps) == (0, 0, 0.0)


def test_ratings_stay_raw_at_another_level_cap_and_defense_is_always_raw() -> None:
    spec = ItemSpec(4, 4, 4, 61, 1, 0, 0.0, ((32, 6222), (12, 2000), (36, 2000)))
    got = itemstats.compute(spec, TABLES, max_level=70)
    assert got.effects == (
        Effect("Equip", "Increases your critical strike rating by 28."),
        Effect("Equip", "Increases your defense rating by 9."),
        Effect("Equip", "Increases your haste rating by 9."),
    )
    at_60 = itemstats.compute(spec, TABLES, max_level=60)
    assert at_60.effects[1:] == (
        Effect("Equip", "Increased Defense +9."),
        Effect("Equip", "Increases your haste rating by 9."),
    )


def test_fractional_percentages_keep_one_decimal() -> None:
    spec = ItemSpec(4, 1, 4, 61, 1, 0, 0.0, ((32, 1556),))  # 7 crit rating
    assert itemstats.compute(spec, TABLES).effects == (
        Effect("Equip", "Improves your chance to get a critical strike by 0.5%."),
    )


def test_spell_power_resistance_and_bonus_armor() -> None:
    # A robe: slot group 0 of the "good" column; bonus armor adds to the armor line without a line of its own.
    spec = ItemSpec(4, 1, 2, 20, 20, 0, 0.0, ((5, 3000), (45, 2000), (51, 5000), (50, 1000)))
    got = itemstats.compute(spec, TABLES)
    assert got.stats == ("+9 Intellect", "+15 Fire Resistance")
    assert got.effects == (
        Effect("Equip", "Increases damage and healing done by magical spells and effects by up to 6."),
    )
    assert got.armor == 46 + 3  # 46.4 * 1.0 * 1.0 rounded, plus 1000 * 30 / 10000


def test_shield_armor_comes_from_its_own_table() -> None:
    spec = ItemSpec(4, 6, 3, 61, 14, 0, 0.0, ())
    assert itemstats.compute(spec, TABLES).armor == 800


def test_two_hander_damage_and_dps() -> None:
    sulfuras = ItemSpec(2, 5, 5, 63, 17, 3700, 0.5, ((7, 2000),))
    got = itemstats.compute(sulfuras, TABLES)
    assert (got.dmg_min, got.dmg_max, got.dps) == (223, 372, 80.4)
    assert got.armor == 0
    assert got.stats == ()  # ilvl 63 has no RandPropPoints row here: no stats rather than wrong ones


def test_one_hand_and_wand_tables() -> None:
    dagger = ItemSpec(2, 15, 2, 20, 13, 1800, 0.4, ())
    assert itemstats.damage(dagger, TABLES) == (14, 22, 10.0)
    wand = ItemSpec(2, 19, 2, 20, 26, 1500, 0.2, ())
    assert itemstats.damage(wand, TABLES) == (12, 15, 9.0)  # 13.5 -> 12.15 / 14.85
    assert itemstats.damage_table(2, 15) == "ranged"
    assert itemstats.damage_table(1, 17) == "two_hand"


def test_unknown_stats_and_missing_tables_produce_nothing() -> None:
    spec = ItemSpec(4, 4, 4, 61, 1, 0, 0.0, ((999, 5000), (4, 0)))
    got = itemstats.compute(spec, TABLES)
    assert (got.stats, got.effects, got.armor) == ((), (), 565)
    nothing = itemstats.compute(LIONHEART_HELM, itemstats.EMPTY_TABLES)
    assert nothing == itemstats.Computed(0, 0, 0, 0.0, (), ())
    unknown_slot = ItemSpec(4, 4, 4, 61, 99, 0, 0.0, ((4, 4000),))
    assert itemstats.stat_values(unknown_slot, TABLES) == []
