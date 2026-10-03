"""Compare the tooltip lines we compute with Wowhead's Classic Era tooltips (development only: network).

    python scripts/spotcheck_tooltips.py [--game-version forever] [--build 1.60.1.69913] [item ids...]

Downloads the build's tables into `cache/` (once), computes every item's lines as `altarmy-profit ingest`
would (no database), fetches each item's tooltip from nether.wowhead.com and prints, per item, `ok` or
the lines we have that Wowhead lacks (`missing`) and the stat, armor, damage and green lines it has that
we lack (`unmatched`). WoW: Forever reworked some items, so a difference is not always our mistake.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

from altarmy_profit import gamedata, ingest, itemstats, versions

# Gear, a weapon and consumables whose Classic tooltips match the Forever data (Forever changed many
# weapons' speeds and some elixirs' durations; their DPS still agrees, so those are not our mistake).
DEFAULT_IDS = [12640, 12618, 10021, 7930, 16979, 17182, 13446, 13513]
TOOLTIP_URL = "https://nether.wowhead.com/tooltip/item/{id}?dataEnv=4&locale=0"
INTERESTING = re.compile(
    r"^(\+\d|.* Armor$|.* Damage$|\(.* damage per second\)$|(Equip|Use|Chance on hit): )"
)
DPS = re.compile(r"\((\d+(?:\.\d+)?) damage per second\)")


def wowhead_lines(item_id: int) -> list[str]:
    req = urllib.request.Request(TOOLTIP_URL.format(id=item_id), headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read())
    text = re.sub(r"<br\s*/?>|</(?:td|tr|div|table)>", "\n", str(payload.get("tooltip", "")))
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    return [_normal(line) for line in text.splitlines() if line.strip()]


def _normal(line: str) -> str:
    line = re.sub(r"\s+", " ", line).strip()
    return DPS.sub(lambda m: f"({float(m[1]):.1f} damage per second)", line)


def our_lines(tip: itemstats.Computed, delay_ms: int) -> list[str]:
    out = []
    if tip.dmg_max > 0:
        out += [f"{tip.dmg_min} - {tip.dmg_max} Damage", f"Speed {delay_ms / 1000:.2f}"]
        out.append(f"({tip.dps:.1f} damage per second)")
    if tip.armor > 0:
        out.append(f"{tip.armor} Armor")
    out += list(tip.stats)
    out += [f"{e.trigger}: {e.text}" for e in tip.effects]
    return [_normal(line) for line in out]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--game-version", default="forever")
    parser.add_argument("--build", default=None, help="the wago.tools build (default: the pinned one)")
    parser.add_argument("--cache", default=gamedata.REPO_CACHE, type=Path)
    parser.add_argument("ids", nargs="*", type=int, default=DEFAULT_IDS)
    args = parser.parse_args(argv)
    version = versions.get(args.game_version)
    build = args.build or ingest.pinned_build(version)
    paths = ingest.download_all(build, args.cache)
    tips = ingest.item_tooltips(paths, version.max_level)
    delays = {ingest._int(r["ID"]): ingest._int(r["ItemDelay"]) for r in ingest._rows(paths["ItemSparse"])}
    names = {ingest._int(r["ID"]): r["Display_lang"] for r in ingest._rows(paths["ItemSparse"])}

    ok = 0
    for item_id in args.ids:
        if item_id not in tips:
            print(f"{item_id}: not in build {build}")
            continue
        ours = our_lines(tips[item_id], delays.get(item_id, 0))
        theirs = wowhead_lines(item_id)
        missing = [line for line in ours if line not in theirs]
        unmatched = [line for line in theirs if INTERESTING.match(line) and line not in ours]
        if not missing and not unmatched:
            ok += 1
            print(f"{item_id} {names[item_id]}: ok")
            continue
        print(f"{item_id} {names[item_id]}:")
        for line in missing:
            print(f"  missing on Wowhead: {line}")
        for line in unmatched:
            print(f"  unmatched by us:    {line}")
    print(f"{ok}/{len(args.ids)} items match")
    return 0 if ok == len(args.ids) else 1


if __name__ == "__main__":
    sys.exit(main())
