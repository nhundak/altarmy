"""Shared fixtures: the database (SQLite, or Postgres with TEST_DATABASE_URL) and a tiny fake DB2 CSV set
shaped like the wago.tools exports."""

import csv
import json
import os
import shutil
from collections.abc import Iterator, Mapping
from dataclasses import replace
from pathlib import Path

import pytest
from sqlalchemy import Connection, text

from altarmy_profit import auth, db, prices, schema, users
from altarmy_profit.versions import VERSIONS, GameVersion

from .test_altarmy import ALTARMY_SV
from .test_auctionator import _entry, _saved_variables

SV_DIR = "_classic_beta_/WTF/Account/ACCT/SavedVariables"  # under `wow_root`
FOREVER = "forever"
ME = "me"  # the signed-in user (linked) who owns what tests store; the `database` fixture registers them
TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")  # e.g. postgresql+psycopg://u:p@localhost/test


@pytest.fixture(scope="session")
def _migrated(tmp_path_factory: pytest.TempPathFactory) -> Path | None:
    """Migrate once per session: a SQLite template file each test copies, or the Postgres database
    (whose `public` schema is dropped first, so point TEST_DATABASE_URL at a throwaway database)."""
    if TEST_DATABASE_URL:
        database = db.Database(TEST_DATABASE_URL)
        with database.engine.begin() as conn:
            conn.execute(text("DROP SCHEMA public CASCADE"))
            conn.execute(text("CREATE SCHEMA public"))
        database.ensure_schema()
        database.dispose()
        return None
    template = tmp_path_factory.mktemp("template") / "template.sqlite"
    database = db.Database(db.sqlite_url(template))
    database.ensure_schema()
    database.dispose()
    return template


@pytest.fixture
def database(tmp_path: Path, _migrated: Path | None) -> Iterator[db.Database]:
    """An empty, migrated database with the game versions and the user `ME` registered."""
    if _migrated is None:
        assert TEST_DATABASE_URL
        database = db.Database(TEST_DATABASE_URL)
        tables = [t.name for t in schema.metadata.sorted_tables if t is not schema.game_versions]
        with database.engine.begin() as conn:
            conn.execute(text(f"TRUNCATE {', '.join(tables)} RESTART IDENTITY CASCADE"))
            conn.execute(schema.game_versions.update().values(build=None))
    else:
        path = tmp_path / "test.sqlite"
        shutil.copyfile(_migrated, path)
        database = db.Database(db.sqlite_url(path))
    database.ensure_schema()
    with database.begin() as conn:
        # revision 0002 creates the removed local mode's user; Postgres' TRUNCATE drops it: drop it here too
        conn.execute(schema.users.delete().where(schema.users.c.uid == "local"))
        users.ensure_user(conn, auth.User(ME, "linked"))
    yield database
    database.dispose()


@pytest.fixture
def conn(database: db.Database) -> Iterator[Connection]:
    """An autocommit connection, so what a test writes is visible to the API's own connections."""
    with database.engine.connect().execution_options(isolation_level="AUTOCOMMIT") as c:
        yield c


def set_prices(
    conn: Connection,
    item_prices: Mapping[int, int],
    realm: str = "Classic Beta PvE",
    faction: str = "",
    game_version: str = FOREVER,
) -> int:
    """Manual prices on an auction house (default: the one Classic Beta PvE's factions share, as the
    tailor's Auctionator scan would be). Returns its id."""
    ah = prices.auction_house(conn, game_version, realm, faction)
    for item_id, price in item_prices.items():
        prices.set_price(conn, ah, item_id, price)
    return ah


def write_csv(path: Path, header: list[str], rows: list[dict[str, object]]) -> Path:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=header, restval=0)
        w.writeheader()
        w.writerows(rows)
    return path


@pytest.fixture
def db2_paths(tmp_path: Path) -> dict[str, Path]:
    """Items: 1 Linen Cloth, 2 Coarse Thread, 3 Green Robe. One Tailoring recipe (10 linen + 1 thread).

    Vendors sell thread in stacks of 5 (see `vendor_csv`).

    The robe carries tooltip data: a chest (robe) slot, Cloth subclass, BoE, level/skill requirements,
    flavor text and an icon.
    """
    reagent_cols = [f"Reagent_{i}" for i in range(8)] + [f"ReagentCount_{i}" for i in range(8)]
    return {
        "Item": write_csv(
            tmp_path / "Item.csv",
            ["ID", "ClassID", "SubclassID", "IconFileDataID"],
            [
                {"ID": 1, "ClassID": 7, "IconFileDataID": 501},
                {"ID": 2, "ClassID": 7, "IconFileDataID": 999},  # not in the manifest -> no icon
                {"ID": 3, "ClassID": 4, "SubclassID": 1, "IconFileDataID": 500},
            ],
        ),
        "ItemSparse": write_csv(
            tmp_path / "ItemSparse.csv",
            [
                "ID",
                "Display_lang",
                "OverallQualityID",
                "ItemLevel",
                "RequiredLevel",
                "SellPrice",
                "BuyPrice",
                "VendorStackCount",
                "Stackable",
                "Bonding",
                "InventoryType",
                "ItemDelay",
                "ContainerSlots",
                "RequiredSkill",
                "RequiredSkillRank",
                "Description_lang",
            ],
            [
                {
                    "ID": 1,
                    "Display_lang": "Linen Cloth",
                    "OverallQualityID": 1,
                    "Stackable": 20,
                    "SellPrice": 13,
                    "Description_lang": "",
                },
                {
                    "ID": 2,
                    "Display_lang": "Coarse Thread",
                    "OverallQualityID": 1,
                    "SellPrice": 10,
                    "BuyPrice": 51,  # per stack of 5
                    "VendorStackCount": 5,
                    "Description_lang": "",
                },
                {
                    "ID": 3,
                    "Display_lang": "Green Robe",
                    "OverallQualityID": 2,
                    "ItemLevel": 20,
                    "RequiredLevel": 12,
                    "SellPrice": 500,
                    "Bonding": 2,
                    "InventoryType": 20,
                    "RequiredSkill": 197,
                    "RequiredSkillRank": 50,
                    "Description_lang": "Soft and green.",
                },
            ],
        ),
        "ItemSubClass": write_csv(
            tmp_path / "ItemSubClass.csv",
            ["DisplayName_lang", "ID", "ClassID", "SubClassID"],
            [
                {"DisplayName_lang": "Miscellaneous", "ID": 19, "ClassID": 4, "SubClassID": 0},
                {"DisplayName_lang": "Cloth", "ID": 20, "ClassID": 4, "SubClassID": 1},
            ],
        ),
        "ManifestInterfaceData": write_csv(
            tmp_path / "ManifestInterfaceData.csv",
            ["ID", "FilePath", "FileName"],
            [
                {"ID": 500, "FilePath": "Interface\\ICONS\\", "FileName": "INV_Chest_Cloth_39.blp"},
                {"ID": 501, "FilePath": "Interface\\ICONS\\", "FileName": "INV_Fabric_Linen_01.blp"},
                {"ID": 502, "FilePath": "Interface\\AbilitiesFrame\\", "FileName": "UI-Panel.blp"},
            ],
        ),
        "SkillLine": write_csv(
            tmp_path / "SkillLine.csv",
            ["ID", "DisplayName_lang"],
            [{"ID": 197, "DisplayName_lang": "Tailoring"}],
        ),
        "SkillLineAbility": write_csv(
            tmp_path / "SkillLineAbility.csv",
            [
                "ID",
                "SkillLine",
                "Spell",
                "MinSkillLineRank",
                "TrivialSkillLineRankLow",
                "TrivialSkillLineRankHigh",
            ],
            [
                {
                    "ID": 100,
                    "SkillLine": 197,
                    "Spell": 900,
                    "MinSkillLineRank": 25,
                    "TrivialSkillLineRankLow": 30,
                    "TrivialSkillLineRankHigh": 60,
                },
                # no reagents/effect -> must be skipped
                {"ID": 101, "SkillLine": 197, "Spell": 901},
                # not a known skill line -> must be skipped
                {"ID": 102, "SkillLine": 999, "Spell": 900},
            ],
        ),
        "SpellName": write_csv(
            tmp_path / "SpellName.csv", ["ID", "Name_lang"], [{"ID": 900, "Name_lang": "Green Robe"}]
        ),
        "SpellEffect": write_csv(
            tmp_path / "SpellEffect.csv",
            ["ID", "Effect", "EffectItemType", "EffectBasePointsF", "SpellID"],
            [
                {"ID": 1, "Effect": 24, "EffectItemType": 3, "EffectBasePointsF": 1.0, "SpellID": 900},
                {"ID": 2, "Effect": 6, "EffectItemType": 0, "EffectBasePointsF": 0, "SpellID": 901},
            ],
        ),
        # Spell 900 casts in 3 s (index 5; a heroic-difficulty row must not win) at an anvil (focus 1).
        "SpellMisc": write_csv(
            tmp_path / "SpellMisc.csv",
            ["ID", "SpellID", "CastingTimeIndex", "DifficultyID"],
            [
                {"ID": 1, "SpellID": 900, "CastingTimeIndex": 5, "DifficultyID": 0},
                {"ID": 2, "SpellID": 900, "CastingTimeIndex": 1, "DifficultyID": 2},
            ],
        ),
        "SpellCastTimes": write_csv(
            tmp_path / "SpellCastTimes.csv",
            ["ID", "Base", "Minimum"],
            [{"ID": 1, "Base": 0, "Minimum": 0}, {"ID": 5, "Base": 3000, "Minimum": 3000}],
        ),
        "SpellCastingRequirements": write_csv(
            tmp_path / "SpellCastingRequirements.csv",
            ["ID", "SpellID", "RequiresSpellFocus"],
            [{"ID": 1, "SpellID": 900, "RequiresSpellFocus": 1}],
        ),
        "SpellFocusObject": write_csv(
            tmp_path / "SpellFocusObject.csv",
            ["ID", "Name_lang"],
            [
                {"ID": 1, "Name_lang": "Anvil"},
                {"ID": 3, "Name_lang": "Forge"},
                {"ID": 4, "Name_lang": "Cooking Fire"},
            ],
        ),
        "SpellReagents": write_csv(
            tmp_path / "SpellReagents.csv",
            ["ID", "SpellID", *reagent_cols],
            [
                {
                    "ID": 1,
                    "SpellID": 900,
                    "Reagent_0": 1,
                    "Reagent_1": 2,
                    "ReagentCount_0": 10,
                    "ReagentCount_1": 1,
                }
            ],
        ),
    }


@pytest.fixture
def vendor_csv(tmp_path: Path) -> Path:
    """Vendors sell Coarse Thread (item 2), and an item this build doesn't have."""
    return write_csv(
        tmp_path / "vendor_items.csv",
        ["item_id", "name"],
        [{"item_id": 2, "name": "Coarse Thread"}, {"item_id": 99, "name": "Removed Item"}],
    )


def city_preset(name: str, faction: str, vendor_x: float, anvil: bool = False) -> dict[str, object]:
    """A city with its auction house at the hub, a mailbox 35 yd away, a vendor selling Coarse Thread
    (item 2) `vendor_x` yards away and, with `anvil`, an anvil 20 yd away."""
    anvils = [{"id": "anvil:1", "kind": "anvil", "name": "Anvil", "x": 0, "y": 20, "z": 0}] if anvil else []
    return {
        "name": name,
        "faction": faction,
        "map": 1,
        "hub": "ah",
        "zone": {"name": name, "min_x": -1000, "min_y": -1000, "max_x": 1000, "max_y": 1000, "area": 1638},
        "locations": [
            {"id": "ah", "kind": "ah", "name": "Auctioneer", "x": 0, "y": 0, "z": 0},
            {"id": "mailbox:1", "kind": "mailbox", "name": "Mailbox", "x": 35, "y": 0, "z": 0},
            {"id": "vendor:1", "kind": "vendor", "name": "Thread Seller", "x": vendor_x, "y": 0, "z": 0},
            *anvils,
        ],
        "vendors": {"vendor:1": [2]},
    }


@pytest.fixture
def cities(tmp_path: Path) -> Path:
    """Forever's city presets (the `game_versions` data dir): Orgrimmar (Horde, its vendor 700 yd off, no
    anvil), Thunder Bluff (Horde, 14 yd, an anvil), Stormwind (Alliance, an anvil) and Booty Bay (neutral,
    its vendor next door: never offered, its auction house isn't the tracked one)."""
    folder = tmp_path / "cities"
    folder.mkdir()
    for name, faction, x, anvil in [
        ("Orgrimmar", "Horde", 700, False),
        ("Thunder Bluff", "Horde", 14, True),
        ("Booty Bay", "", 1, True),
        ("Stormwind", "Alliance", 70, True),
    ]:
        preset = city_preset(name, faction, x, anvil)
        (folder / f"{name}.json").write_text(json.dumps(preset), encoding="utf-8")
    return folder


@pytest.fixture
def game_versions(tmp_path: Path) -> dict[str, GameVersion]:
    """Both versions: Forever with its data files in tmp_path (see `vendor_csv`), TBC with none."""
    return {
        "forever": replace(VERSIONS["forever"], data_dir=tmp_path),
        "tbc": replace(VERSIONS["tbc"], data_dir=tmp_path / "tbc"),
    }


@pytest.fixture
def wow_root(tmp_path: Path) -> Path:
    """A fake WoW install (tmp_path / "World of Warcraft") holding both addons' SavedVariables.

    Alt Army: Classic Beta PvE (Horde tailor, Alliance enchanter) and Dreamscythe Horde (two characters).
    Auctionator: prices for Classic Beta PvE (one auction house for both factions) and Dreamscythe Horde.
    """
    root = tmp_path / "World of Warcraft"
    sv = root / SV_DIR
    sv.mkdir(parents=True)
    (sv / "AltArmy_TBC.lua").write_bytes(ALTARMY_SV)
    auctions: dict[str, dict[str, object]] = {
        "ClassicBetaPvE": {"1": _entry(20), "2": _entry(100)},
        "Dreamscythe Horde": {"1": _entry(5)},
    }
    (sv / "Auctionator.lua").write_bytes(_saved_variables(auctions))
    return root
