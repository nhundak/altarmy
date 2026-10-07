"""Which items vendors sell, from cmangos' open-source TBC (2.4.3) world database.

DB2 does not say what vendors sell (that is server-side data), so `scripts/build_vendor_items.py` uses this
to regenerate `data/tbc/vendor_items.csv`, which ingest loads. The price comes from DB2's BuyPrice. The
vanilla counterpart is `vmangos.py`.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from . import gamedata

# Items with unlimited stock, no condition and no token cost (ExtendedCost: honor, badges, ...), sold by a
# vendor that spawns in the world, directly or through a vendor template. A spawn names its creature in
# `creature.id`, or picks one of several from `creature_spawn_entry` (then `id` is 0).
VENDOR_ITEMS_SQL = """
WITH spawned(entry) AS (
    SELECT id FROM creature WHERE id > 0 UNION SELECT entry FROM creature_spawn_entry
),
sold(item) AS (
    SELECT v.item FROM npc_vendor v JOIN spawned s ON s.entry = v.entry
    WHERE v.maxcount = 0 AND v.condition_id = 0 AND v.ExtendedCost = 0
    UNION
    SELECT v.item FROM npc_vendor_template v
    JOIN creature_template ct ON ct.VendorTemplateId = v.entry
    JOIN spawned s ON s.entry = ct.Entry
    WHERE v.maxcount = 0 AND v.condition_id = 0 AND v.ExtendedCost = 0
)
SELECT sold.item, (SELECT name FROM item_template it WHERE it.entry = sold.item)
FROM sold ORDER BY sold.item
"""


def vendor_items(conn: sqlite3.Connection) -> list[tuple[int, str]]:
    """(item id, name) of every item a vendor sells without limit for gold."""
    return [(int(i), str(name or "")) for i, name in conn.execute(VENDOR_ITEMS_SQL)]


def download_world_db(cache_dir: Path, release: str | None = None) -> Path:
    """cmangos' TBC world database: `release` (else the newest), cached (`gamedata.world_db`)."""
    return gamedata.world_db("cmangos", cache_dir, release)
