import csv
import json
import urllib.error
from pathlib import Path

import pytest
from sqlalchemy import Connection, func, select
from sqlalchemy.engine import Row

from altarmy_profit import db, ingest, prices, schema, spelltext, store

from .conftest import FOREVER, set_prices, write_csv


def item(conn: Connection, item_id: int, game_version: str = FOREVER) -> Row[tuple[object, ...]]:
    t = schema.items
    return conn.execute(select(t).where(t.c.game_version == game_version, t.c.id == item_id)).one()


def count(conn: Connection, table: str) -> int:
    return int(conn.execute(select(func.count()).select_from(schema.metadata.tables[table])).scalar_one())


def test_build_db_loads_items_and_recipes(db2_paths: dict[str, Path], conn: Connection) -> None:
    stats = ingest.build_db(db2_paths, conn, FOREVER)
    assert stats == {"items": 3, "recipes": 1, "disenchant_rows": 0, "vendor_items": 0}

    robe = item(conn, 3)
    assert (robe.name, robe.quality, robe.item_level, robe.class_id, robe.sell_price) == (
        "Green Robe",
        2,
        20,
        4,
        500,
    )

    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.id, recipe.name, recipe.skill_name, recipe.output_item_id) == (
        100,
        "Green Robe",
        "Tailoring",
        3,
    )
    assert recipe.min_skill == 25 and recipe.output_count == 1

    rr = schema.recipe_reagents
    reagents = [tuple(r) for r in conn.execute(select(rr.c.slot, rr.c.item_id, rr.c.count))]
    assert sorted(reagents) == [(0, 1, 10), (1, 2, 1)]


def test_build_db_loads_cast_time_and_station(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.cast_time_ms, recipe.station) == (3000, "anvil")  # SpellMisc -> SpellCastTimes; focus 1


def test_build_db_loads_the_skill_the_recipe_item_requires(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the robe item teaches the robe's craft spell (on learn, through ItemXItemEffect) and requires 50
    assert conn.execute(select(schema.recipes.c.learn_skill)).scalar_one() == 50


def test_learn_skills_take_the_lowest_rank_of_the_items_teaching_a_spell(tmp_path: Path) -> None:
    effects = write_csv(  # TBC's shape: each effect names its item
        tmp_path / "ItemEffect.csv",
        ["ID", "TriggerType", "SpellID", "ParentItemID"],
        [
            {"ID": 1, "TriggerType": 0, "SpellID": 483, "ParentItemID": 10},  # "Learning", on use
            {"ID": 2, "TriggerType": 6, "SpellID": 700, "ParentItemID": 10},
            {"ID": 3, "TriggerType": 6, "SpellID": 700, "ParentItemID": 11},  # another pattern, lower
            {"ID": 4, "TriggerType": 6, "SpellID": 701, "ParentItemID": 12},  # requires no skill
            {"ID": 5, "TriggerType": 0, "SpellID": 702, "ParentItemID": 13},  # not a recipe item
        ],
    )
    ranks = {10: 75, 11: 60, 12: 0, 13: 40}
    assert ingest.learn_skills({"ItemEffect": effects}, ranks) == {700: 60}


def test_craft_stations_are_the_foci_profession_spells_need(db2_paths: dict[str, Path]) -> None:
    assert ingest.craft_stations(db2_paths) == {1: "Anvil"}  # the robe's; the forge and fire go unused


def test_zone_boxes_are_the_whole_map_assignments(tmp_path: Path) -> None:
    uma = write_csv(
        tmp_path / "UiMapAssignment.csv",
        [
            "UiMin_0",
            "UiMin_1",
            "UiMax_0",
            "UiMax_1",
            "Region_0",
            "Region_1",
            "Region_2",
            "Region_3",
            "Region_4",
            "Region_5",
            "ID",
            "UiMapID",
            "MapID",
            "AreaID",
        ],
        [
            {
                "UiMin_0": 0,
                "UiMin_1": 0,
                "UiMax_0": 1,
                "UiMax_1": 1,
                "Region_0": 1000,
                "Region_1": -5000,
                "Region_2": -1e6,
                "Region_3": 2000,
                "Region_4": -4000,
                "Region_5": 1e6,
                "ID": 1,
                "UiMapID": 1454,
                "MapID": 1,
                "AreaID": 1637,
            },
            # a corner of a map (a sub-zone overlay): not the whole map
            {
                "UiMin_0": 0.5,
                "UiMin_1": 0,
                "UiMax_0": 1,
                "UiMax_1": 1,
                "Region_0": 0,
                "Region_1": 0,
                "Region_2": 0,
                "Region_3": 1,
                "Region_4": 1,
                "Region_5": 1,
                "ID": 2,
                "UiMapID": 1454,
                "MapID": 1,
                "AreaID": 1637,
            },
        ],
    )
    names = write_csv(tmp_path / "UiMap.csv", ["Name_lang", "ID"], [{"Name_lang": "Orgrimmar", "ID": 1454}])
    assert ingest.zone_boxes(uma, names) == [(1, "Orgrimmar", 1000.0, -5000.0, 2000.0, -4000.0, 1637)]


def test_build_db_without_cast_time_or_focus_reads_zero(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    paths = {
        **db2_paths,
        "SpellMisc": write_csv(
            tmp_path / "NoMisc.csv", ["ID", "SpellID", "CastingTimeIndex", "DifficultyID"], []
        ),
        "SpellCastingRequirements": write_csv(
            tmp_path / "NoReq.csv", ["ID", "SpellID", "RequiresSpellFocus"], []
        ),
    }
    ingest.build_db(paths, conn, FOREVER)
    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.cast_time_ms, recipe.station) == (0, "")


def test_build_db_loads_tooltip_fields(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    robe = item(conn, 3)._mapping
    assert {k: robe[k] for k in TOOLTIP_COLUMNS} == {
        "bonding": 2,
        "required_level": 12,
        "inventory_type": 20,
        "item_delay": 0,
        "container_slots": 0,
        "subclass_name": "Cloth",
        "required_skill": "Tailoring",
        "required_skill_rank": 50,
        "description": "Soft and green.",
        "icon": "inv_chest_cloth_39",
        "armor": 46,
        "dmg_min": 0,
        "dmg_max": 0,
        "dps": 0.0,
        "stats": '["+9 Intellect"]',
        "effects": json.dumps(ROBE_EFFECTS),
    }
    assert (item(conn, 1).icon, item(conn, 2).icon) == ("inv_fabric_linen_01", None)  # 2: not in the manifest
    linen = item(conn, 1)
    assert (linen.subclass_name, linen.required_skill, linen.description) == (None, None, None)
    assert (linen.armor, linen.dps, linen.stats, linen.effects) == (0, 0.0, "[]", "[]")


SPELL_POWER_LINE = "Increases damage and healing done by magical spells and effects by up to 6."
ROBE_EFFECTS = [
    {"trigger": "Equip", "text": SPELL_POWER_LINE},
    {"trigger": "Use", "text": "Restores 1050 to 1750 health. (2 Min Cooldown)"},
]

TOOLTIP_COLUMNS = {
    "bonding",
    "required_level",
    "inventory_type",
    "item_delay",
    "container_slots",
    "subclass_name",
    "required_skill",
    "required_skill_rank",
    "description",
    "icon",
    "armor",
    "dmg_min",
    "dmg_max",
    "dps",
    "stats",
    "effects",
}


def _robe_row(db2_paths: dict[str, Path], **changes: object) -> tuple[list[str], dict[str, object]]:
    """The fixture's ItemSparse header and its Green Robe row with `changes` applied."""
    rows = _read(db2_paths["ItemSparse"])
    robe: dict[str, object] = {**next(r for r in rows if r["ID"] == "3"), **changes}
    return list(rows[0]), robe


def test_build_db_loads_weapon_damage(db2_paths: dict[str, Path], conn: Connection, tmp_path: Path) -> None:
    # A rare one-hand dagger (subclass 15) at ilvl 20: 10 DPS at speed 1.8 with a 40% spread is 14-22.
    header, dagger = _robe_row(
        db2_paths,
        Display_lang="Dagger",
        OverallQualityID=3,
        InventoryType=13,
        ItemDelay=1800,
        DmgVariance=0.4,
    )
    paths = {
        **db2_paths,
        "Item": write_csv(
            tmp_path / "Dagger.csv",
            ["ID", "ClassID", "SubclassID", "IconFileDataID"],
            [{"ID": 3, "ClassID": 2, "SubclassID": 15}],
        ),
        "ItemSparse": write_csv(tmp_path / "DaggerSparse.csv", header, [dagger]),
        "ItemDamageOneHand": write_csv(
            tmp_path / "ItemDamageOneHand.csv",
            ["ID", "ItemLevel", "Quality_0", "Quality_1", "Quality_2", "Quality_3"],
            [{"ID": 20, "ItemLevel": 20, "Quality_2": 8.0, "Quality_3": 10.0}],
        ),
    }
    ingest.build_db(paths, conn, FOREVER)
    got = item(conn, 3)
    assert (got.armor, got.dmg_min, got.dmg_max, got.dps, got.stats) == (0, 14, 22, 10.0, "[]")


def test_build_db_reads_the_no_disenchant_flag(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    header, robe = _robe_row(db2_paths, Flags_0=0x8000 | 0x40)  # ITEM_FLAG_NO_DISENCHANT, plus another
    paths = {**db2_paths, "ItemSparse": write_csv(tmp_path / "NoDE.csv", [*header, "Flags_0"], [robe])}
    ingest.build_db(paths, conn, FOREVER)
    assert item(conn, 3).disenchantable is False


def test_build_db_items_are_disenchantable_without_the_flag(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)  # the fixture has no Flags_0 column
    assert item(conn, 3).disenchantable is True


def test_build_db_without_stat_tables_reads_empty(db2_paths: dict[str, Path], conn: Connection) -> None:
    gone = ("RandPropPoints", "ItemArmorTotal", "ItemEffect", "Spell")
    paths = {k: v for k, v in db2_paths.items() if k not in gone}
    ingest.build_db(paths, conn, FOREVER)
    robe = item(conn, 3)
    assert (robe.armor, robe.stats, robe.effects) == (0, "[]", "[]")


def test_build_db_reads_tbc_item_effects_by_parent_item(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    # TBC's ItemEffect names the item itself and there is no ItemXItemEffect; a chance-on-hit effect
    # and an equip effect with a cooldown (not shown on Equip lines).
    paths = {
        **db2_paths,
        "ItemEffect": write_csv(
            tmp_path / "TbcItemEffect.csv",
            ["ID", "LegacySlotIndex", "TriggerType", "CoolDownMSec", "SpellID", "ParentItemID"],
            [
                {
                    "ID": 1,
                    "LegacySlotIndex": 1,
                    "TriggerType": 1,
                    "CoolDownMSec": 5000,
                    "SpellID": 950,
                    "ParentItemID": 3,
                },
                {"ID": 2, "LegacySlotIndex": 0, "TriggerType": 2, "SpellID": 950, "ParentItemID": 3},
            ],
        ),
    }
    del paths["ItemXItemEffect"]
    ingest.build_db(paths, conn, "tbc", max_level=70)
    assert json.loads(item(conn, 3, "tbc").effects)[1:] == [
        {"trigger": "Chance on hit", "text": "Restores 1050 to 1750 health."},
        {"trigger": "Equip", "text": "Restores 1050 to 1750 health."},
    ]


def test_spell_data_follows_references_and_prefers_the_normal_difficulty(
    db2_paths: dict[str, Path], tmp_path: Path
) -> None:
    paths = {
        **db2_paths,
        "Spell": write_csv(
            tmp_path / "Spell2.csv",
            ["ID", "Description_lang"],
            [
                {"ID": 950, "Description_lang": "$@spelldesc951 for $951d."},
                {"ID": 951, "Description_lang": "Heals $s1"},
                {"ID": 952, "Description_lang": "unrelated"},
            ],
        ),
        "SpellEffect": write_csv(
            tmp_path / "SpellEffect2.csv",
            ["ID", "SpellID", "EffectIndex", "EffectBasePointsF", "DifficultyID", "EffectAuraPeriod"],
            [
                {"ID": 1, "SpellID": 951, "EffectBasePointsF": 5, "DifficultyID": 2},
                {"ID": 2, "SpellID": 951, "EffectBasePointsF": 7, "DifficultyID": 0},
                {"ID": 3, "SpellID": 951, "EffectBasePointsF": 9, "DifficultyID": 3},
            ],
        ),
        "SpellMisc": write_csv(
            tmp_path / "SpellMisc2.csv",
            ["ID", "SpellID", "DurationIndex", "DifficultyID", "CastingTimeIndex"],
            [{"ID": 1, "SpellID": 951, "DurationIndex": 9}],
        ),
    }
    data = ingest.spell_data(paths, [950])
    assert set(data.descriptions) == {950, 951}
    assert data.effects[951][0].base == 7
    assert data.durations == {951: 30000}
    assert spelltext.expand(data.descriptions[950], 950, data) == "Heals 7 for 30 sec."


def test_build_db_shows_ratings_raw_at_other_level_caps(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    header, robe = _robe_row(
        db2_paths, StatModifier_bonusStat_0=32, StatPercentEditor_0=7000
    )  # 21 crit rating
    paths = {**db2_paths, "ItemSparse": write_csv(tmp_path / "Rating.csv", header, [robe])}
    ingest.build_db(paths, conn, "tbc", max_level=70)
    assert (
        json.loads(item(conn, 3, "tbc").effects)[0]["text"] == "Increases your critical strike rating by 21."
    )
    ingest.build_db(paths, conn, FOREVER, max_level=60)
    assert (
        json.loads(item(conn, 3).effects)[0]["text"]
        == "Improves your chance to get a critical strike by 1.5%."
    )


def _read(path: Path) -> list[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def test_download_caches_an_optional_table_the_build_lacks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fetch(url: str) -> bytes:
        raise urllib.error.HTTPError(url, 400, "Bad Request", None, None)  # type: ignore[arg-type]

    monkeypatch.setattr(ingest, "_fetch", fetch)
    path = ingest.download("ItemArmorShield", "1.0", tmp_path, optional=True)
    assert path.read_bytes() == b""
    assert list(ingest._optional_rows({"ItemArmorShield": path}, "ItemArmorShield")) == []
    assert list(ingest._optional_rows({}, "ItemArmorShield")) == []
    with pytest.raises(urllib.error.HTTPError):
        ingest.download("Item", "1.0", tmp_path)


def test_build_db_preserves_prices_and_other_versions(db2_paths: dict[str, Path], conn: Connection) -> None:
    ah = set_prices(conn, {1: 45})
    ingest.build_db(db2_paths, conn, "tbc")
    ingest.build_db(db2_paths, conn, FOREVER)
    ingest.build_db(db2_paths, conn, FOREVER)  # idempotent rebuild
    assert prices.load_current(conn, ah) == {1: 45}
    assert count(conn, "recipes") == 2  # one per version
    assert store.load_market(conn, "tbc", None).items.keys() == {1, 2, 3}


def test_build_db_loads_disenchant_csv(db2_paths: dict[str, Path], conn: Connection, tmp_path: Path) -> None:
    de = write_csv(
        tmp_path / "de.csv",
        [
            "item_class",
            "quality",
            "min_ilvl",
            "max_ilvl",
            "result_item_id",
            "chance",
            "min_count",
            "max_count",
        ],
        [
            {
                "item_class": 4,
                "quality": 2,
                "min_ilvl": 15,
                "max_ilvl": 25,
                "result_item_id": 9,
                "chance": 0.75,
                "min_count": 1,
                "max_count": 2,
            }
        ],
    )
    assert ingest.build_db(db2_paths, conn, FOREVER, de)["disenchant_rows"] == 1
    ((row),) = store.load_market(conn, FOREVER, None).disenchant
    assert (row.result_item_id, row.chance, row.max_count) == (9, 0.75, 2)


def test_build_db_loads_vendor_items(db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path) -> None:
    assert ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)["vendor_items"] == 2
    assert sorted(conn.execute(select(schema.vendor_items.c.item_id)).scalars()) == [2, 99]
    thread = item(conn, 2)
    assert (thread.buy_price, thread.buy_count) == (51, 5)
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)  # rebuild replaces, not appends
    assert count(conn, "vendor_items") == 2


def test_int_parsing_is_forgiving() -> None:
    assert ingest._int("12") == 12
    assert ingest._int("3.0") == 3
    assert ingest._int("") == 0
    assert ingest._int(None, 7) == 7
    assert ingest._int("abc", 5) == 5


def test_parse_latest_build_picks_product() -> None:
    payload = json.dumps(
        {
            "wow": {"product": "wow", "version": "12.1.0.69933"},
            "wow_classic_beta": {"product": "wow_classic_beta", "version": "1.60.1.69977"},
        }
    ).encode()
    assert ingest.parse_latest_build(payload, "wow_classic_beta") == "1.60.1.69977"
    assert ingest.parse_latest_build(payload, "wow") == "12.1.0.69933"
    with pytest.raises(ValueError, match="wow_nope"):
        ingest.parse_latest_build(payload, "wow_nope")


def test_update_downloads_builds_and_records_build(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[tuple[str, Path]] = []

    def fake_download_all(build: str, cache_dir: Path) -> dict[str, Path]:
        calls.append((build, cache_dir))
        return db2_paths

    monkeypatch.setattr(ingest, "download_all", fake_download_all)
    stats = ingest.update(conn, FOREVER, "1.2.3.4", tmp_path / "cache")
    assert calls == [("1.2.3.4", tmp_path / "cache")]
    assert stats["recipes"] == 1
    assert db.get_build(conn, FOREVER) == "1.2.3.4"


@pytest.mark.parametrize(
    ("row", "count"),
    [
        ({"EffectBasePointsF": "3"}, 3),  # Forever: the (average) count as a float
        (
            {"EffectBasePointsF": "0", "EffectBasePoints": "2", "EffectDieSides": "1"},
            3,
        ),  # TBC Thorium Grenade
        ({"EffectBasePointsF": "0", "EffectBasePoints": "199", "EffectDieSides": "1"}, 200),  # Thorium Shells
        (
            {"EffectBasePointsF": "0", "EffectBasePoints": "0", "EffectDieSides": "5"},
            3,
        ),  # Heavy Dynamite: 1-5
        ({"EffectBasePointsF": "0", "EffectBasePoints": "1", "EffectDieSides": "3"}, 3),  # Iron Grenade: 2-4
        ({"EffectBasePointsF": "0", "EffectBasePoints": "0", "EffectDieSides": "0"}, 1),
        ({"EffectBasePointsF": ""}, 1),  # no count columns at all
    ],
)
def test_output_count_from_either_clients_spell_effect(row: dict[str, str], count: int) -> None:
    assert ingest.output_count(row) == count


def test_build_db_reads_tbc_style_output_counts(db2_paths: dict[str, Path], conn: Connection) -> None:
    write_csv(
        db2_paths["SpellEffect"],
        [
            "ID",
            "Effect",
            "EffectItemType",
            "EffectBasePointsF",
            "EffectBasePoints",
            "EffectDieSides",
            "SpellID",
        ],
        [
            {
                "ID": 1,
                "Effect": 24,
                "EffectItemType": 3,
                "EffectBasePointsF": 0,
                "EffectBasePoints": 2,
                "EffectDieSides": 1,
                "SpellID": 900,
            }
        ],
    )
    ingest.build_db(db2_paths, conn, FOREVER)
    assert conn.execute(select(schema.recipes.c.output_count)).scalar_one() == 3
