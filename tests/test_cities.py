"""City presets: reading spawns from a vmangos-shaped world database, and building a preset from them."""

import sqlite3
from collections.abc import Iterator
from pathlib import Path

import pytest

from altarmy_profit import cities, timing, vmangos
from altarmy_profit.cities import CitySpec
from altarmy_profit.vmangos import Spawn

SCHEMA = """
CREATE TABLE game_tele (id INTEGER, position_x REAL, position_y REAL, position_z REAL, orientation REAL,
    map INTEGER, name TEXT);
CREATE TABLE creature (guid INTEGER, id INTEGER, map INTEGER, position_x REAL, position_y REAL,
    position_z REAL, patch_min INTEGER, patch_max INTEGER);
CREATE TABLE creature_template (entry INTEGER, patch INTEGER, name TEXT, npc_flags INTEGER,
    vendor_id INTEGER);
CREATE TABLE npc_vendor (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER);
CREATE TABLE npc_vendor_template (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER);
CREATE TABLE gameobject (guid INTEGER, id INTEGER, map INTEGER, position_x REAL, position_y REAL,
    position_z REAL, patch_min INTEGER, patch_max INTEGER);
CREATE TABLE gameobject_template (entry INTEGER, patch INTEGER, type INTEGER, name TEXT, data0 INTEGER);
"""
FOCUS = {1: "Anvil", 3: "Forge", 4: "Cooking Fire"}  # DB2 SpellFocusObject names (226, a quest well, is not)
# A town around (1000, -4000, 20) on map 1: negative coordinates, so a pasted "- -4000" would be a comment.
X, Y, Z = 1000.0, -4000.0, 20.0


@pytest.fixture
def town(tmp_path: Path) -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(tmp_path / "mangos.sqlite")
    conn.executescript(SCHEMA)
    conn.execute("INSERT INTO game_tele VALUES (1, ?, ?, ?, 0, 1, 'Town')", (X, Y, Z))
    conn.executemany(
        "INSERT INTO creature_template VALUES (?,?,?,?,?)",
        [
            (10, 0, "Auctioneer Old", 4096, 0),
            (10, 5, "Auctioneer Ann", 4096, 0),  # the newest patch's name wins
            (11, 0, "Auctioneer Bob", 4096, 0),
            (12, 0, "Auctioneer Cid", 4096, 0),
            (20, 0, "Thread Seller", 4 | 1, 0),
            (21, 0, "Template Seller", 4, 70),
            (22, 0, "Rep Seller", 4, 0),  # sells only behind a condition: dropped
            (30, 0, "Guard", 1, 0),
        ],
    )
    conn.executemany(
        "INSERT INTO creature VALUES (?,?,?,?,?,?,?,?)",
        [
            (1, 10, 1, X + 10, Y, Z, 0, 10),
            (2, 10, 1, X + 10, Y, Z, 5, 10),  # the same auctioneer again for later patches
            (3, 11, 1, X + 30, Y, Z, 0, 10),
            (4, 12, 1, X - 10, Y, Z, 0, 10),
            (5, 20, 1, X, Y - 50, Z, 0, 10),
            (6, 21, 1, X, Y + 50, Z, 0, 10),
            (7, 22, 1, X, Y + 60, Z, 0, 10),
            (8, 30, 1, X, Y, Z, 0, 10),
            (9, 11, 1, X + 900, Y, Z, 0, 10),  # too far
            (10, 11, 0, X, Y, Z, 0, 10),  # another continent
            (11, 11, 1, X + 5, Y, Z, 0, 3),  # gone by patch 1.12
            (12, 11, 1, X + 5, Y, Z + 500, 0, 10),  # far above (a flying ship, say)
        ],
    )
    conn.executemany(
        "INSERT INTO npc_vendor VALUES (?,?,?,?)",
        [(20, 2, 0, 0), (20, 3, 0, 0), (20, 4, 5, 0), (22, 5, 0, 9)],
    )
    conn.executemany("INSERT INTO npc_vendor_template VALUES (?,?,?,?)", [(70, 6, 0, 0), (70, 2, 0, 0)])
    conn.executemany(
        "INSERT INTO gameobject_template VALUES (?,?,?,?,?)",
        [
            (100, 0, 19, "Mailbox", 0),
            (101, 0, 8, "Anvil", 1),
            (102, 0, 8, "Forge", 3),
            (103, 0, 8, "Well", 226),
        ],
    )
    conn.executemany(
        "INSERT INTO gameobject VALUES (?,?,?,?,?,?,?,?)",
        [
            (50, 100, 1, X + 20, Y + 5, Z, 0, 10),
            (51, 101, 1, X - 40, Y, Z, 0, 10),
            (52, 102, 1, X - 42, Y, Z, 0, 10),
            (53, 103, 1, X, Y - 20, Z, 0, 10),
            (54, 100, 1, X + 2000, Y, Z, 0, 10),
        ],
    )
    yield conn
    conn.close()


def test_city_centre_reads_game_tele(town: sqlite3.Connection) -> None:
    assert vmangos.city_centre(town, "Town") == (1, X, Y, Z)
    with pytest.raises(ValueError, match="Atlantis"):
        vmangos.city_centre(town, "Atlantis")


def test_npcs_near_takes_current_spawns_once_with_their_newest_template(town: sqlite3.Connection) -> None:
    got = vmangos.npcs_near(town, 1, X, Y, Z, 100, vmangos.NPC_AUCTIONEER)
    assert [(s.guid, s.name) for s in got] == [
        (1, "Auctioneer Ann"),
        (3, "Auctioneer Bob"),
        (4, "Auctioneer Cid"),
    ]
    assert (got[0].x, got[0].y) == (X + 10, Y)
    vendors = vmangos.npcs_near(town, 1, X, Y, Z, 100, vmangos.NPC_VENDOR)
    assert [s.entry for s in vendors] == [20, 21, 22]


def test_objects_near_finds_mailboxes_and_stations(town: sqlite3.Connection) -> None:
    mail = vmangos.objects_near(town, 1, X, Y, Z, 100, vmangos.GO_MAILBOX)
    assert [s.guid for s in mail] == [50]
    focus = vmangos.objects_near(town, 1, X, Y, Z, 100, vmangos.GO_SPELL_FOCUS)
    assert [(s.name, s.data0) for s in focus] == [("Anvil", 1), ("Forge", 3), ("Well", 226)]


def test_vendor_stock_is_unlimited_and_unconditional(town: sqlite3.Connection) -> None:
    assert vmangos.vendor_stock(town, [20, 21, 22, 30]) == {20: [2, 3], 21: [2, 6]}
    assert vmangos.vendor_stock(town, []) == {}


def build(town: sqlite3.Connection, existing: dict[str, object] | None = None) -> dict[str, object]:
    spec = CitySpec("Town", "Town", "Horde", 100)
    m, x, y, z = vmangos.city_centre(town, "Town")
    vendors = vmangos.npcs_near(town, m, x, y, z, 100, vmangos.NPC_VENDOR)
    return cities.build_city(
        spec,
        m,
        vmangos.npcs_near(town, m, x, y, z, 100, vmangos.NPC_AUCTIONEER),
        vmangos.objects_near(town, m, x, y, z, 100, vmangos.GO_MAILBOX),
        vmangos.objects_near(town, m, x, y, z, 100, vmangos.GO_SPELL_FOCUS),
        vendors,
        vmangos.vendor_stock(town, [v.entry for v in vendors]),
        FOCUS,
        existing,
    )


def test_build_city_makes_a_preset_the_timing_model_reads(town: sqlite3.Connection) -> None:
    data = build(town)
    city = timing.CityMap.from_dict(data)
    assert (city.name, city.faction, city.hub.id, city.hub.name) == ("Town", "Horde", "ah", "Auctioneer Ann")
    assert sorted(loc.id for loc in city.locations) == [
        "ah",
        "anvil:51",
        "forge:52",
        "mailbox:50",
        "vendor:20",
        "vendor:21",
    ]
    assert city.vendor_items == {"vendor:20": frozenset({2, 3}), "vendor:21": frozenset({2, 6})}
    assert data["generated"] == {
        "source": "vmangos",
        "tele": "Town",
        "radius": 100,
        "counts": {
            "auctioneers": 3,
            "mailboxes": 1,
            "anvil": 1,
            "forge": 1,
            "vendors": 2,
            "items": 3,
        },
    }


def test_build_city_keeps_the_hand_tuned_overrides(town: sqlite3.Connection) -> None:
    overrides = {"detour": 1.8, "travel": {"ah|mailbox:50": 4.0}}
    data = build(town, {"name": "Town", "overrides": overrides})
    assert data["overrides"] == overrides
    assert timing.CityMap.from_dict(data).seconds("ah", "mailbox:50", timing.DEFAULT_CONFIG) == 4.0


def test_build_city_needs_somewhere_to_start() -> None:
    with pytest.raises(ValueError, match="no auctioneer or mailbox"):
        cities.build_city(CitySpec("Nowhere", "X", "", 10), 0, [], [], [], [], {}, FOCUS)


def test_build_city_starts_at_a_mailbox_without_an_auction_house() -> None:
    box = Spawn(7, 100, "Mailbox", 1.0, -2.0, 3.0)
    data = cities.build_city(CitySpec("Hamlet", "X", "", 10), 0, [], [box], [], [], {}, FOCUS)
    assert data["hub"] == "mailbox:7"
    assert timing.CityMap.from_dict(data).hub.id == "mailbox:7"
