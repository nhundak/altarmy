"""Regenerate data/<version>/cities/*.json, the city presets profit per hour is timed in.

Reads where auctioneers, mailboxes, crafting stations and vendors stand around each city from vmangos' world
database (downloaded once into cache/), naming stations by the version's DB2 SpellFocusObject. Stations new
in WoW: Forever (spinning wheels, looms, ...) are not in vmangos: add them to a preset's `overrides`
("locations"), which regenerating keeps.
Only Forever (vanilla) is supported for now. Usage:
python scripts/build_cities.py [--game-version forever] [--city NAME] [--radius YARDS]
Then restart the app (or POST /api/reload in local mode) to load them.
"""

import argparse
import json
import sqlite3
from dataclasses import replace
from pathlib import Path

from altarmy_profit import cities, ingest, versions, vmangos

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--game-version", choices=["forever"], default="forever")
    p.add_argument("--city", help="only this city (a preset name, e.g. Orgrimmar)")
    p.add_argument("--radius", type=float, help="yards around the city's centre (with --city)")
    args = p.parse_args()
    specs = [s for s in cities.CITY_SPECS if args.city in (None, s.name)]
    if not specs:
        names = ", ".join(s.name for s in cities.CITY_SPECS)
        p.error(f"no city named {args.city!r}; expected one of {names}")
    if args.radius is not None:
        specs = [replace(s, radius=args.radius) for s in specs]
    version = versions.VERSIONS[args.game_version]
    tables = ("SpellFocusObject", "SpellCastingRequirements", "SkillLineAbility")
    focus = ingest.craft_stations(
        {t: ingest.download(t, version.default_build, ROOT / "cache") for t in tables}
    )
    out_dir = ROOT / version.cities_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    world = vmangos.download_world_db(ROOT / "cache")
    conn = sqlite3.connect(world)
    for spec in specs:
        path = out_dir / f"{spec.name}.json"
        existing = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
        m, x, y, z = vmangos.city_centre(conn, spec.tele)
        r = spec.radius
        vendors = vmangos.npcs_near(conn, m, x, y, z, r, vmangos.NPC_VENDOR)
        data = cities.build_city(
            spec,
            m,
            vmangos.npcs_near(conn, m, x, y, z, r, vmangos.NPC_AUCTIONEER),
            vmangos.objects_near(conn, m, x, y, z, r, vmangos.GO_MAILBOX),
            vmangos.objects_near(conn, m, x, y, z, r, vmangos.GO_SPELL_FOCUS),
            vendors,
            vmangos.vendor_stock(conn, [v.entry for v in vendors]),
            focus,
            existing,
            source=f"vmangos {world.parent.name}",
        )
        path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
        counts = ", ".join(f"{v} {k}" for k, v in data["generated"]["counts"].items())
        print(f"{spec.name}: {counts}")
    conn.close()


if __name__ == "__main__":
    main()
