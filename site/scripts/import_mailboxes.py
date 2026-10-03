"""Add the mailboxes the frellscout addon found in game to the city presets (data/forever/cities/*.json).

Reads frellscout's SavedVariables (every account's under the Forever install, or --file) and adds each
mailbox no preset has yet to its city's `overrides` ("locations"), which regenerating the presets keeps.
Mailboxes vmangos already has (Classic's) and ones imported before are skipped, so re-running is safe.
Usage: python scripts/import_mailboxes.py [--file frellscout.lua] [--dry-run]
Then restart the API (`npm run dev`, or a deploy) to load them.
"""

import argparse
import json
from pathlib import Path

from altarmy_profit import cities, versions, wowfiles

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--file", type=Path, action="append", help="frellscout.lua to read (repeatable)")
    p.add_argument("--dry-run", action="store_true", help="report, but write nothing")
    args = p.parse_args()
    version = versions.VERSIONS["forever"]
    files = args.file or wowfiles.find_saved_variables("frellscout.lua", flavors=version.flavor_folders)
    if not files:
        p.error("no frellscout.lua found under the Forever install; pass --file")
    found = []
    for path in files:
        print(f"Reading {path}")
        found += cities.scouted_mailboxes(path.read_bytes())
    out_dir = ROOT / version.cities_dir
    paths = {}
    presets = {}
    for path in sorted(out_dir.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        paths[data["name"]] = path
        presets[data["name"]] = data
    changed, report = cities.add_scouted_mailboxes(presets, found)
    for line in report:
        print(line)
    for name, data in sorted(changed.items()):
        added = sum(f": added to {name} as " in line for line in report)
        if not args.dry_run:
            paths[name].write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
        print(f"{name}: {added} mailbox(es) {'would be ' if args.dry_run else ''}added")
    if not changed:
        print("No new mailboxes.")


if __name__ == "__main__":
    main()
