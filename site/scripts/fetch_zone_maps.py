"""Download the zone map of every city preset (data/<version>/cities/*.json, the zone's `area`) and of every
zone a recipe vendor stands in (data/<version>/recipe_item_sources.csv) from Wowhead's CDN into
frontend/public/maps/<area>.jpg, which the built front end serves itself. Maps already there are kept; pass
--force to fetch them again."""

from __future__ import annotations

import argparse
import csv
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "frontend" / "public" / "maps"
URL = "https://wow.zamimg.com/images/wow/classic/maps/enus/zoom/{area}.jpg"


def preset_areas() -> dict[int, str]:
    """Each preset's zone map area id, with the zone's name."""
    areas: dict[int, str] = {}
    for path in sorted(ROOT.glob("data/*/cities/*.json")):
        zone = json.loads(path.read_text(encoding="utf-8")).get("zone") or {}
        if zone.get("area"):
            areas[int(zone["area"])] = str(zone.get("name", path.stem))
    return areas


def vendor_areas() -> dict[int, str]:
    """The zone map area id of every recipe vendor's zone, with the zone's name."""
    areas: dict[int, str] = {}
    for path in sorted(ROOT.glob("data/*/recipe_item_sources.csv")):
        with open(path, encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                if row["kind"] == "vendor" and int(row.get("area") or 0):
                    areas[int(row["area"])] = row["zone"]
    return areas


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="download maps that are already there")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for area, name in sorted((vendor_areas() | preset_areas()).items()):
        target = OUT / f"{area}.jpg"
        if target.exists() and not args.force:
            print(f"{area} {name}: kept")
            continue
        request = urllib.request.Request(URL.format(area=area), headers={"User-Agent": "altarmy-profit"})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
        if not data.startswith(b"\xff\xd8"):
            raise SystemExit(f"{area} {name}: not a JPEG")
        target.write_bytes(data)
        print(f"{area} {name}: {len(data) // 1024} KB")


if __name__ == "__main__":
    main()
