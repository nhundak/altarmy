"""City presets: reading spawns from a vmangos-shaped world database, and building a preset from them."""

import sqlite3
from collections.abc import Iterator, Sequence
from pathlib import Path
from typing import Any

import pytest

from altarmy_profit import cities, ingest, timing, vmangos
from altarmy_profit.cities import CitySpec
from altarmy_profit.vmangos import Spawn

SCHEMA = """
CREATE TABLE game_tele (id INTEGER, position_x REAL, position_y REAL, position_z REAL, orientation REAL,
    map INTEGER, name TEXT);
CREATE TABLE creature (guid INTEGER, id INTEGER, map INTEGER, position_x REAL, position_y REAL,
    position_z REAL, patch_min INTEGER, patch_max INTEGER, movement_type INTEGER DEFAULT 0);
CREATE TABLE creature_template (entry INTEGER, patch INTEGER, name TEXT, npc_flags INTEGER,
    vendor_id INTEGER, faction INTEGER);
CREATE TABLE faction_template (id INTEGER, build INTEGER, faction_id INTEGER);
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
        "INSERT INTO creature_template VALUES (?,?,?,?,?,?)",
        [
            (10, 0, "Auctioneer Old", 4096, 0, 12),
            (10, 5, "Auctioneer Ann", 4096, 0, 12),  # the newest patch's name wins
            (11, 0, "Auctioneer Bob", 4096, 0, 12),
            (12, 0, "Auctioneer Cid", 4096, 0, 12),
            (20, 0, "Thread Seller", 4 | 1, 0, 35),
            (20, 2, "Thread Seller", 4 | 1, 0, 12),  # the newest patch's faction too
            (21, 0, "Template Seller", 4, 70, 35),
            (22, 0, "Rep Seller", 4, 0, 875),  # sells only behind a condition: dropped
            (30, 0, "Guard", 1, 0, 0),
        ],
    )
    conn.executemany(  # faction templates: Stormwind's (renumbered in a later build), the gnomes', and one
        "INSERT INTO faction_template VALUES (?,?,?)",  # of a faction nobody has a reputation with
        [(12, 4222, 11), (12, 5875, 72), (875, 5875, 54), (35, 5875, 31)],
    )
    conn.executemany(
        "INSERT INTO creature (guid, id, map, position_x, position_y, position_z, patch_min, patch_max)"
        " VALUES (?,?,?,?,?,?,?,?)",
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
    conn.execute("INSERT INTO creature_template VALUES (23, 0, 'Wandering Seller', 4, 0, 12)")
    conn.execute(  # walks a waypoint route: nowhere to run to
        "INSERT INTO creature (guid, id, map, position_x, position_y, position_z, patch_min, patch_max,"
        " movement_type) VALUES (13, 23, 1, ?, ?, ?, 0, 10, 2)",
        (X, Y + 5, Z),
    )
    conn.executemany(
        "INSERT INTO npc_vendor VALUES (?,?,?,?)",
        [(20, 2, 0, 0), (20, 3, 0, 0), (20, 4, 5, 0), (22, 5, 0, 9), (23, 7, 0, 0)],
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
    assert [s.entry for s in vendors] == [20, 21, 22]  # not 23, who patrols


def test_objects_near_finds_mailboxes_and_stations(town: sqlite3.Connection) -> None:
    mail = vmangos.objects_near(town, 1, X, Y, Z, 100, vmangos.GO_MAILBOX)
    assert [s.guid for s in mail] == [50]
    focus = vmangos.objects_near(town, 1, X, Y, Z, 100, vmangos.GO_SPELL_FOCUS)
    assert [(s.name, s.data0) for s in focus] == [("Anvil", 1), ("Forge", 3), ("Well", 226)]


def test_vendor_stock_is_unlimited_and_unconditional(town: sqlite3.Connection) -> None:
    assert vmangos.vendor_stock(town, [20, 21, 22, 30]) == {20: [2, 3], 21: [2, 6]}
    assert vmangos.vendor_stock(town, []) == {}


def test_vendor_factions_come_from_the_newest_templates(town: sqlite3.Connection) -> None:
    # the guard (30) has no faction template
    assert vmangos.vendor_factions(town, [20, 21, 22, 30]) == {20: 72, 21: 31, 22: 54}
    assert vmangos.vendor_factions(town, []) == {}


def build(
    town: sqlite3.Connection,
    existing: dict[str, object] | None = None,
    zones: Sequence[ingest.ZoneBox] = (),
) -> dict[str, Any]:
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
        zones=zones,
        factions=vmangos.vendor_factions(town, [v.entry for v in vendors]),
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
    # only a city faction's vendors: nobody has a reputation with the Template Seller's faction
    assert data["vendor_reputations"] == {"vendor:20": 72}
    assert (city.reputation_of("vendor:20"), city.reputation_of("vendor:21")) == (72, 0)
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


def test_build_city_names_the_smallest_zone_map_around_the_hub(town: sqlite3.Connection) -> None:
    zones = [
        (1, "Kalimdor", -9000.0, -9000.0, 9000.0, 9000.0, 0),
        (1, "Town", X - 500, Y - 500, X + 500, Y + 500, 1637),
        (1, "Elsewhere", X + 1000, Y, X + 2000, Y + 500, 2),  # not around the hub
        (0, "Other Continent", X - 100, Y - 100, X + 100, Y + 100, 3),
    ]
    data = build(town, zones=zones)
    assert data["zone"] == {
        "name": "Town",
        "min_x": X - 500,
        "min_y": Y - 500,
        "max_x": X + 500,
        "max_y": Y + 500,
        "area": 1637,
    }
    assert timing.CityMap.from_dict(data).map_coords("ah") == (50.0, 49.0)  # Ann stands 10 yd north of centre
    assert "zone" not in build(town)


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


# --- frellscout mailboxes ---------------------------------------------------------------------------------
SCOUT_SV = b"""
FrellscoutDB = {
\t["nextId"] = 5,
\t["mailboxes"] = {
\t\t{ ["id"] = 1, ["instance"] = 1, ["x"] = 1000, ["y"] = -4050, ["z"] = 20, ["zone"] = "Town" },
\t\t{ ["id"] = 2, ["instance"] = 1, ["x"] = 1006, ["y"] = -4050, ["z"] = 0, ["zone"] = "Town" },
\t\t{ ["id"] = 3, ["instance"] = 1, ["x"] = 1040, ["y"] = -4000, ["z"] = 0, ["zone"] = "Town" },
\t\t{ ["id"] = 4, ["instance"] = 0, ["x"] = 1040, ["y"] = -4000, ["z"] = 5, ["zone"] = "Far" },
\t},
}
"""


def town_preset() -> dict[str, Any]:
    return {
        "name": "Town",
        "faction": "Horde",
        "map": 1,
        "hub": "ah",
        "locations": [
            {"id": "ah", "kind": "ah", "name": "Ann", "x": 1000.0, "y": -4010.0, "z": 20.0},
            {"id": "mailbox:50", "kind": "mailbox", "name": "Mailbox", "x": 1000.0, "y": -4050.0, "z": 20.0},
            {"id": "vendor:20", "kind": "vendor", "name": "Vic", "x": 1045.0, "y": -4000.0, "z": 31.0},
        ],
        "vendors": {"vendor:20": [2]},
        "generated": {"source": "vmangos", "tele": "Town", "radius": 100, "counts": {}},
        "overrides": {},
    }


def test_scouted_mailboxes_reads_frellscout_saved_variables() -> None:
    found = cities.scouted_mailboxes(SCOUT_SV)
    assert [(m.id, m.map_id, m.x, m.y, m.z) for m in found] == [
        (1, 1, 1000.0, -4050.0, 20.0),
        (2, 1, 1006.0, -4050.0, 0.0),
        (3, 1, 1040.0, -4000.0, 0.0),
        (4, 0, 1040.0, -4000.0, 5.0),
    ]
    assert cities.scouted_mailboxes(b"Other = {}") == []


@pytest.mark.parametrize(
    "text", [b"FrellscoutDB = 3", b'FrellscoutDB = {["mailboxes"] = {{["id"] = 1, ["x"] = "a"}}}']
)
def test_scouted_mailboxes_rejects_a_malformed_file(text: bytes) -> None:
    with pytest.raises(ValueError):
        cities.scouted_mailboxes(text)


def test_add_scouted_mailboxes_skips_classic_ones_and_places_new_ones() -> None:
    presets = {"Town": town_preset()}
    changed, report = cities.add_scouted_mailboxes(presets, cities.scouted_mailboxes(SCOUT_SV))
    added = changed["Town"]["overrides"]["locations"]
    # 1 stands on vmangos' mailbox and 2 is 6 yd off it: both Classic. 3 is new; its height comes from the
    # nearest location (the vendor, 5 yd away). 4 is on another continent: no city.
    assert added == [
        {
            "id": "mailbox:scout:1040:-4000",
            "kind": "mailbox",
            "name": "Mailbox",
            "x": 1040.0,
            "y": -4000.0,
            "z": 31.0,
        }
    ]
    assert [line.split(":")[0] for line in report] == ["#1", "#2", "#3", "#4"]
    assert "mailbox:50" in report[0] and "mailbox:50" in report[1]
    assert "Town" in report[2] and "no city" in report[3]
    assert presets["Town"]["overrides"] == {}  # the input is left alone
    city = timing.CityMap.from_dict(changed["Town"])
    assert city.location("mailbox:scout:1040:-4000").kind == "mailbox"


def test_add_scouted_mailboxes_twice_changes_nothing() -> None:
    found = cities.scouted_mailboxes(SCOUT_SV)
    once, _ = cities.add_scouted_mailboxes({"Town": town_preset()}, found)
    twice, report = cities.add_scouted_mailboxes(once, found)
    assert twice == {}
    assert "mailbox:scout:1040:-4000" in report[2]
