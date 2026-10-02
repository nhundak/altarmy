"""Regenerate data/<version>/vendor_items.csv (and Forever's vendor_recipes.csv and recipe_item_sources.csv)
from an open-source world database.

Forever (vanilla-based) reads vmangos' database, TBC reads cmangos' tbc-db; each is downloaded once into
cache/. Usage: python scripts/build_vendor_items.py [--game-version forever|tbc]
Then run that version's game data update (or `altarmy-profit --game-version <v> ingest`) to load it.
"""

import argparse
import sqlite3
from pathlib import Path

from altarmy_profit import cmangos, ingest, versions, vmangos

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--game-version", choices=list(versions.VERSIONS), default=versions.DEFAULT_VERSION)
    args = p.parse_args()
    version = versions.VERSIONS[args.game_version]
    source = cmangos if args.game_version == "tbc" else vmangos
    out = ROOT / version.vendor_csv
    world = source.download_world_db(ROOT / "cache")
    conn = sqlite3.connect(world)
    rows = source.vendor_items(conn)
    # Forever binds most recipes on pickup, so ingest needs to know which of them a vendor sells
    recipes = vmangos.vendor_recipes(conn) if source is vmangos else None
    # where recipe items come from, placed in the client's zone maps
    sources = None
    if source is vmangos:
        ui = {
            t: ingest.download(t, version.default_build, ROOT / "cache") for t in ("UiMapAssignment", "UiMap")
        }
        sources = vmangos.recipe_item_sources(conn, ingest.zone_boxes(ui["UiMapAssignment"], ui["UiMap"]))
    conn.close()
    out.parent.mkdir(parents=True, exist_ok=True)
    vmangos.write_csv(rows, out)
    print(f"wrote {len(rows)} vendor items to {out}")
    if recipes is not None:
        recipes_out = ROOT / version.vendor_recipes_csv
        vmangos.write_csv(recipes, recipes_out)
        print(f"wrote {len(recipes)} vendor recipes to {recipes_out}")
    if sources is not None:
        sources_out = ROOT / version.sources_csv
        vmangos.write_sources_csv(sources, sources_out)
        print(f"wrote {len(sources)} recipe item sources to {sources_out}")


if __name__ == "__main__":
    main()
