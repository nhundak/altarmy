"""Which items vendors sell, and where things stand in the cities, from vmangos' open-source vanilla (1.12)
world database.

DB2 does not say what vendors sell (that is server-side data), so `scripts/build_vendor_items.py` uses
this to regenerate `data/forever/vendor_items.csv`, which ingest loads. The price comes from DB2's BuyPrice.
`scripts/build_cities.py` reads the spawns of auctioneers, vendors, mailboxes and crafting stations around
each city (see `cities`). Coordinates are always bound as parameters: a negative one pasted into SQL
after a minus sign would start a comment.
"""

from __future__ import annotations

import csv
import json
import sqlite3
import zipfile
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from .ingest import _fetch

RELEASE_URL = "https://api.github.com/repos/vmangos/core/releases/tags/db_latest"
WORLD_DB = "mangos.sqlite"

# Items with unlimited stock and no condition (reputation, event, ...), sold by a vendor that spawns in
# the world, either directly or through a vendor template. A creature spawn can pick from up to five ids.
VENDOR_ITEMS_SQL = """
WITH spawned(entry) AS (
    SELECT id FROM creature UNION SELECT id2 FROM creature UNION SELECT id3 FROM creature
    UNION SELECT id4 FROM creature UNION SELECT id5 FROM creature
),
sold(item) AS (
    SELECT v.item FROM npc_vendor v JOIN spawned s ON s.entry = v.entry
    WHERE v.maxcount = 0 AND v.condition_id = 0
    UNION
    SELECT v.item FROM npc_vendor_template v
    JOIN creature_template ct ON ct.vendor_id = v.entry
    JOIN spawned s ON s.entry = ct.entry
    WHERE v.maxcount = 0 AND v.condition_id = 0
)
SELECT sold.item,
       (SELECT name FROM item_template it WHERE it.entry = sold.item ORDER BY patch DESC LIMIT 1)
FROM sold ORDER BY sold.item
"""


LATEST_PATCH = 10  # vmangos' content patches run 0 (1.2) to 10 (1.12); rows are kept per patch
NPC_VENDOR = 0x4  # creature_template.npc_flags
NPC_AUCTIONEER = 0x1000
MOVE_WAYPOINTS = 2  # creature.movement_type: 0 stands, 1 wanders nearby, 2 walks a waypoint route
GO_SPELL_FOCUS = 8  # gameobject_template.type; data0 is the SpellFocusObject id
GO_MAILBOX = 19


@dataclass(frozen=True)
class Spawn:
    """A creature or game object standing in the world."""

    guid: int
    entry: int
    name: str
    x: float
    y: float
    z: float
    data0: int = 0  # game objects: a spell focus's kind (1 anvil, 3 forge, 4 cooking fire, ...)


def city_centre(conn: sqlite3.Connection, tele: str) -> tuple[int, float, float, float]:
    """(map, x, y, z) of a `game_tele` point (e.g. "Orgrimmar"); ValueError if there is none."""
    row = conn.execute(
        "SELECT map, position_x, position_y, position_z FROM game_tele WHERE name = ?", (tele,)
    ).fetchone()
    if row is None:
        raise ValueError(f"no game_tele point named {tele!r}")
    return int(row[0]), float(row[1]), float(row[2]), float(row[3])


_NEAR = """
(({t}.position_x - ?) * ({t}.position_x - ?) + ({t}.position_y - ?) * ({t}.position_y - ?)
 + ({t}.position_z - ?) * ({t}.position_z - ?)) <= ?
"""


def _near(t: str, x: float, y: float, z: float, radius: float) -> tuple[str, tuple[float, ...]]:
    return _NEAR.format(t=t), (x, x, y, y, z, z, radius * radius)


def _unique(spawns: Iterable[Spawn]) -> list[Spawn]:
    """One spawn per entry and spot: vmangos repeats some for different patch ranges."""
    seen: dict[tuple[int, int, int, int], Spawn] = {}
    for s in spawns:
        seen.setdefault((s.entry, round(s.x), round(s.y), round(s.z)), s)
    return sorted(seen.values(), key=lambda s: s.guid)


def npcs_near(
    conn: sqlite3.Connection, map_id: int, x: float, y: float, z: float, radius: float, flag: int
) -> list[Spawn]:
    """Creatures spawned within `radius` yards (in 3D) whose newest template has the `npc_flags` bit
    `flag`, leaving out those that walk a waypoint route (a patrolling vendor has no spot to run to)."""
    near, args = _near("c", x, y, z, radius)
    rows = conn.execute(
        f"""
        SELECT c.guid, t.entry, t.name, c.position_x, c.position_y, c.position_z
        FROM creature c JOIN creature_template t ON t.entry = c.id
        WHERE t.patch = (
            SELECT MAX(patch) FROM creature_template n WHERE n.entry = t.entry AND n.patch <= ?
        )
          AND c.map = ? AND c.patch_min <= ? AND c.patch_max >= ? AND (t.npc_flags & ?) != 0
          AND c.movement_type != ? AND {near}
        """,
        (LATEST_PATCH, map_id, LATEST_PATCH, LATEST_PATCH, flag, MOVE_WAYPOINTS, *args),
    )
    return _unique(
        Spawn(int(g), int(e), str(n), float(px), float(py), float(pz)) for g, e, n, px, py, pz in rows
    )


def objects_near(
    conn: sqlite3.Connection, map_id: int, x: float, y: float, z: float, radius: float, go_type: int
) -> list[Spawn]:
    """Game objects of `go_type` spawned within `radius` yards (in 3D), with their newest template."""
    near, args = _near("o", x, y, z, radius)
    rows = conn.execute(
        f"""
        SELECT o.guid, t.entry, t.name, o.position_x, o.position_y, o.position_z, t.data0
        FROM gameobject o JOIN gameobject_template t ON t.entry = o.id
        WHERE t.patch = (
            SELECT MAX(patch) FROM gameobject_template n WHERE n.entry = t.entry AND n.patch <= ?
        )
          AND o.map = ? AND o.patch_min <= ? AND o.patch_max >= ? AND t.type = ? AND {near}
        """,
        (LATEST_PATCH, map_id, LATEST_PATCH, LATEST_PATCH, go_type, *args),
    )
    return _unique(
        Spawn(int(g), int(e), str(n), float(px), float(py), float(pz), int(d0))
        for g, e, n, px, py, pz, d0 in rows
    )


def vendor_stock(conn: sqlite3.Connection, entries: Iterable[int]) -> dict[int, list[int]]:
    """What each vendor (creature entry) sells without limit or condition, directly or through its vendor
    template; vendors selling nothing so are left out."""
    wanted = sorted(set(entries))
    if not wanted:
        return {}
    marks = ",".join("?" * len(wanted))
    rows = conn.execute(
        f"""
        SELECT v.entry, v.item FROM npc_vendor v
        WHERE v.entry IN ({marks}) AND v.maxcount = 0 AND v.condition_id = 0
        UNION
        SELECT t.entry, v.item FROM npc_vendor_template v
        JOIN creature_template t ON t.vendor_id = v.entry
        WHERE t.entry IN ({marks}) AND v.maxcount = 0 AND v.condition_id = 0
        ORDER BY 1, 2
        """,
        (*wanted, *wanted),
    )
    out: dict[int, list[int]] = {}
    for entry, item in rows:
        out.setdefault(int(entry), []).append(int(item))
    return out


def vendor_items(conn: sqlite3.Connection) -> list[tuple[int, str]]:
    """(item id, name) of every item a vendor sells without limit."""
    return [(int(i), str(name or "")) for i, name in conn.execute(VENDOR_ITEMS_SQL)]


def world_db_url(release: bytes) -> tuple[str, str]:
    """(file name, download URL) of the SQLite dump in vmangos' db_latest release JSON."""
    for asset in json.loads(release)["assets"]:
        if asset["name"].startswith("db-sqlite-") and asset["name"].endswith(".zip"):
            return str(asset["name"]), str(asset["browser_download_url"])
    raise ValueError("no db-sqlite-*.zip asset in vmangos' db_latest release")


def download_world_db(cache_dir: Path) -> Path:
    """Download (cached per release file) and extract vmangos' world database; returns its path."""
    name, url = world_db_url(_fetch(RELEASE_URL))
    dest = cache_dir / "vmangos" / name.removesuffix(".zip")
    world = dest / WORLD_DB
    if not world.exists():
        dest.mkdir(parents=True, exist_ok=True)
        archive = dest / name
        archive.write_bytes(_fetch(url))
        with zipfile.ZipFile(archive) as z:
            member = next(m for m in z.namelist() if m.endswith("/" + WORLD_DB))
            world.write_bytes(z.read(member))
        archive.unlink()
    return world


def write_csv(rows: list[tuple[int, str]], path: Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["item_id", "name"])
        w.writerows(rows)
