"""Regenerate data/recipes/<version>/{trainer_skills,quest_spells,item_sources}.csv: recipe facts only the server knows.

Usage: python scripts/build-recipe-server-facts.py [--version tbc|forever|all] [--download]
                                                    [--cmangos <sqlite>] [--vmangos <sqlite>]
       python scripts/build-recipe-server-facts.py --status [--summary <markdown file>]

The client's DB2 tables (scripts/generate-recipe-data.py) say which profession a recipe belongs to and its
difficulty bands, but not what a trainer requires to teach it or where a recipe item comes from. Those live
in the open-source emulators' world databases: cmangos' tbc-db for TBC, vmangos' (vanilla 1.12) for Forever.
By default this reads the newest copies altarmy-profit has cached (the wow-profit checkout next to this repo);
--download fetches each emulator's latest release itself into .cache/emulators/ instead. Stdlib only. Rerun
generate-recipe-data.py for each version afterwards. The recipe-data workflow does all of this daily when an
emulator has a newer release than server_meta.json records, and opens a PR.

trainer_skills.csv: spell_id,req_skill — the lowest skill any trainer asks before teaching the recipe spell.
  vmangos trainers list a server-side "teach" spell; its learn effect (36) names the recipe spell.
quest_spells.csv: spell_id,req_skill — spells a quest teaches (RewSpell / RewSpellCast, through a learn
  effect when there is one) and the lowest profession skill such a quest asks (0 when none). Every quest
  reward spell is listed; generate-recipe-data.py keeps the recipe ones.
item_sources.csv: item_id,source — every way to get a recipe item (class 9), "|"-joined: vendor (a spawned
  vendor sells it), quest (a quest rewards it), drop (any loot table has it).
server_meta.json: which emulator release each version's CSVs came from (the workflow compares it with the
  emulators' latest releases).

--status prints stale=true|false (GitHub step output format): whether any emulator has a newer release than
server_meta.json records, then tbc= and forever= with each emulator's latest release. With --summary it also
writes a markdown list of the moved releases (the PR body).
"""
import argparse
import csv
import glob
import json
import os
import shutil
import sqlite3
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT_DIR = os.path.join(ROOT, "data", "recipes")
PROFIT_CACHE = os.path.join(ROOT, "..", "wow-profit", "cache")
DOWNLOAD_DIR = os.path.join(ROOT, ".cache", "emulators")
USER_AGENT = "altarmy-tbc-recipe-data/1.0"

ITEM_CLASS_RECIPE = 9
EFFECT_LEARN_SPELL = 36
# Profession skill lines with recipes (SkillLine ids; Poisons 40 has trainers only in TBC).
PROFESSION_SKILL_LINES = (40, 129, 164, 165, 171, 185, 186, 197, 202, 333, 755)
LOOT_TABLES = (
    "creature_loot_template",
    "gameobject_loot_template",
    "item_loot_template",
    "reference_loot_template",
    "fishing_loot_template",
    "pickpocketing_loot_template",
    "skinning_loot_template",
    "disenchant_loot_template",
)
SOURCE_ORDER = ("vendor", "quest", "drop")

# version -> where its emulator publishes its world database. A release is identified as altarmy-profit's
# cache folders name it: cmangos by its SQLite asset's date, vmangos by its db-sqlite-<commit> asset name.
EMULATORS = {
    "tbc": {
        "emulator": "cmangos",
        "title": "cmangos tbc-db",
        "release_url": "https://api.github.com/repos/cmangos/tbc-db/releases/tags/latest",
        "world_db": "tbcmangos.sqlite",
        "profit_cache": os.path.join("cmangos", "*", "tbcmangos.sqlite"),
    },
    "forever": {
        "emulator": "vmangos",
        "title": "vmangos",
        "release_url": "https://api.github.com/repos/vmangos/core/releases/tags/db_latest",
        "world_db": "mangos.sqlite",
        "profit_cache": os.path.join("vmangos", "db-sqlite-*", "mangos.sqlite"),
    },
}
LABELS = {"tbc": "TBC", "forever": "Forever"}


def open_url(url):
    headers = {"User-Agent": USER_AGENT}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"  # Actions runners share IPs; anonymous calls get rate-limited
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300)


def latest_release(version, release_json):
    """(release id, download URL) of the SQLite world database in an emulator's release JSON."""
    for asset in json.loads(release_json)["assets"]:
        name = asset["name"]
        if version == "tbc" and name == "tbc-sqlite-db.zip":
            return str(asset["updated_at"])[:10], str(asset["browser_download_url"])
        if version == "forever" and name.startswith("db-sqlite-") and name.endswith(".zip"):
            return name[: -len(".zip")], str(asset["browser_download_url"])
    sys.exit(f"{version}: no SQLite database in {EMULATORS[version]['title']}'s latest release")


def fetch_latest(version, opener=open_url):
    with opener(EMULATORS[version]["release_url"]) as resp:
        return latest_release(version, resp.read())


def download(version, cache_dir=DOWNLOAD_DIR, opener=open_url):
    """Download (once per release) and extract an emulator's latest world database; returns its path."""
    cfg = EMULATORS[version]
    release, url = fetch_latest(version, opener)
    dest = os.path.join(cache_dir, cfg["emulator"], release)
    world = os.path.join(dest, cfg["world_db"])
    if os.path.exists(world):
        return world
    os.makedirs(dest, exist_ok=True)
    archive = os.path.join(dest, "download.zip")
    with opener(url) as resp, open(archive, "wb") as f:
        shutil.copyfileobj(resp, f)
    with zipfile.ZipFile(archive) as z:
        member = next((m for m in z.namelist() if m == cfg["world_db"] or m.endswith("/" + cfg["world_db"])), None)
        if member is None:
            sys.exit(f"{version}: no {cfg['world_db']} in {url}")
        with z.open(member) as src, open(world + ".part", "wb") as out:
            shutil.copyfileobj(src, out)
    os.replace(world + ".part", world)
    os.remove(archive)
    return world


def stale(meta, latest):
    """[(version, recorded release or None, latest release)] for each version whose emulator has moved on."""
    out = []
    for version in sorted(latest):
        recorded = (meta.get(version) or {}).get("release")
        if recorded != latest[version]:
            out.append((version, recorded, latest[version]))
    return out


def status_lines(meta, latest):
    """GitHub step output: stale=, then each version's latest release (the workflow's cache key)."""
    lines = [f"stale={'true' if stale(meta, latest) else 'false'}"]
    return lines + [f"{version}={latest[version]}" for version in sorted(latest)]


def summary(moved):
    lines = ["## Emulator databases", ""]
    for version, recorded, latest in moved:
        lines.append(f"- {LABELS[version]} ({EMULATORS[version]['title']}): `{recorded or 'none'}` → `{latest}`")
    lines += ["", "Trainer skills, quest spells and recipe item sources were rebuilt from these releases by "
              "`scripts/build-recipe-server-facts.py`. Check `data/recipes/*/overrides.csv` against the "
              "recipe changes below before merging."]
    return "\n".join(lines) + "\n"


def newest_cached(pattern):
    paths = [p for p in glob.glob(os.path.join(PROFIT_CACHE, pattern)) if os.path.getsize(p) > 0]
    return max(paths, key=os.path.getmtime) if paths else None


def columns(conn, table):
    return {row[1].lower(): row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def has_table(conn, table):
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone()


def learned_spells(conn):
    """Server-side teach spell -> the spell its learn effect teaches (vmangos trainers list teach spells)."""
    if not has_table(conn, "spell_template"):
        return {}
    cols = columns(conn, "spell_template")
    key = cols.get("entry") or cols.get("id")
    out = {}
    for i in (1, 2, 3):
        effect, trigger = cols.get(f"effect{i}"), cols.get(f"effecttriggerspell{i}")
        if not effect or not trigger:
            continue
        sql = f"SELECT {key}, {trigger} FROM spell_template WHERE {effect} = ? AND {trigger} > 0"
        for spell, taught in conn.execute(sql, (EFFECT_LEARN_SPELL,)):
            out.setdefault(int(spell), int(taught))
    return out


def trainer_skills(conn):
    teaches = learned_spells(conn)
    marks = ",".join("?" * len(PROFESSION_SKILL_LINES))
    out = {}
    for table in ("npc_trainer", "npc_trainer_template"):
        if not has_table(conn, table):
            continue
        sql = f"SELECT spell, reqskillvalue FROM {table} WHERE reqskill IN ({marks})"
        for spell, req in conn.execute(sql, PROFESSION_SKILL_LINES):
            spell = teaches.get(int(spell), int(spell))
            req = int(req or 0)
            out[spell] = min(req, out.get(spell, req))
    return out


def quest_spells(conn):
    """Recipe spell -> the lowest profession skill a quest teaching it asks (0 when it asks none)."""
    teaches = learned_spells(conn)
    out = {}
    sql = "SELECT RewSpell, RewSpellCast, RequiredSkill, RequiredSkillValue FROM quest_template"
    for rew, cast, skill, value in conn.execute(sql):
        req = int(value or 0) if int(skill or 0) in PROFESSION_SKILL_LINES else 0
        for spell in {int(rew or 0), int(cast or 0)} - {0}:
            spell = teaches.get(spell, spell)
            out[spell] = min(req, out.get(spell, req))
    return out


def spawned_creatures(conn):
    cols = columns(conn, "creature")
    ids = [cols[c] for c in ("id", "id2", "id3", "id4", "id5") if c in cols]
    out = set()
    for col in ids:
        out.update(int(r[0]) for r in conn.execute(f"SELECT DISTINCT {col} FROM creature WHERE {col} > 0"))
    if has_table(conn, "creature_spawn_entry"):
        out.update(int(r[0]) for r in conn.execute("SELECT DISTINCT entry FROM creature_spawn_entry"))
    return out


def vendor_items(conn):
    spawned = spawned_creatures(conn)
    out = set()
    for entry, item in conn.execute("SELECT entry, item FROM npc_vendor"):
        if int(entry) in spawned:
            out.add(int(item))
    ct = columns(conn, "creature_template")
    ct_entry = ct.get("entry")
    template = ct.get("vendortemplateid") or ct.get("vendor_id")
    if template and has_table(conn, "npc_vendor_template"):
        sql = (
            f"SELECT ct.{ct_entry}, v.item FROM npc_vendor_template v "
            f"JOIN creature_template ct ON ct.{template} = v.entry"
        )
        for entry, item in conn.execute(sql):
            if int(entry) in spawned:
                out.add(int(item))
    return out


def quest_items(conn):
    cols = columns(conn, "quest_template")
    rewards = [v for k, v in cols.items() if k.startswith(("rewitemid", "rewchoiceitemid"))]
    out = set()
    for row in conn.execute(f"SELECT {', '.join(rewards)} FROM quest_template"):
        out.update(int(i) for i in row if i and int(i) > 0)
    return out


def loot_items(conn):
    out = set()
    for table in LOOT_TABLES:
        if has_table(conn, table):
            # mincountOrRef < 0 rows point at a reference table instead of naming an item
            out.update(int(r[0]) for r in conn.execute(f"SELECT DISTINCT item FROM {table} WHERE mincountOrRef >= 0"))
    return out


def item_sources(conn):
    recipes = {int(r[0]) for r in conn.execute("SELECT DISTINCT entry FROM item_template WHERE class = ?",
                                                (ITEM_CLASS_RECIPE,))}
    found = {"vendor": vendor_items(conn), "quest": quest_items(conn), "drop": loot_items(conn)}
    out = {}
    for item in sorted(recipes):
        sources = [source for source in SOURCE_ORDER if item in found[source]]
        if sources:
            out[item] = "|".join(sources)
    return out


def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def build(version, db_path):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    skills = trainer_skills(conn)
    quests = quest_spells(conn)
    sources = item_sources(conn)
    out = os.path.join(OUT_DIR, version)
    write_csv(os.path.join(out, "trainer_skills.csv"), ["spell_id", "req_skill"], sorted(skills.items()))
    write_csv(os.path.join(out, "quest_spells.csv"), ["spell_id", "req_skill"], sorted(quests.items()))
    write_csv(os.path.join(out, "item_sources.csv"), ["item_id", "source"], sorted(sources.items()))
    print(f"{version}: {len(skills)} trainer spells, {len(quests)} quest spells, {len(sources)} recipe items "
          f"from {db_path}")


def release_id(db_path):
    """The emulator release a cached database came from: its cache folder (cmangos: release date,
    vmangos: db-sqlite-<commit>)."""
    return os.path.basename(os.path.dirname(os.path.abspath(db_path)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--version", choices=["tbc", "forever", "all"], default="all")
    ap.add_argument("--download", action="store_true",
                    help="fetch each emulator's latest release into .cache/emulators/ instead of the wow-profit cache")
    ap.add_argument("--cmangos", help="cmangos tbc-db sqlite (default: newest in the wow-profit cache)")
    ap.add_argument("--vmangos", help="vmangos world sqlite (default: newest in the wow-profit cache)")
    ap.add_argument("--status", action="store_true", help="print stale=true|false (GitHub step output) and exit")
    ap.add_argument("--summary", help="with --status: write a markdown list of the moved releases here")
    args = ap.parse_args()

    meta_path = os.path.join(OUT_DIR, "server_meta.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    versions = ["tbc", "forever"] if args.version == "all" else [args.version]

    if args.status:
        latest = {v: fetch_latest(v)[0] for v in versions}
        print("\n".join(status_lines(meta, latest)))
        if args.summary:
            with open(args.summary, "w", encoding="utf-8", newline="\n") as f:
                f.write(summary(stale(meta, latest)))
        return

    for version in versions:
        cfg = EMULATORS[version]
        emulator = cfg["emulator"]
        db_path = getattr(args, emulator)
        if not db_path:
            db_path = download(version) if args.download else newest_cached(cfg["profit_cache"])
        if not db_path or not os.path.exists(db_path):
            sys.exit(f"{version}: no {emulator} database; pass --download, run altarmy-profit's ingest, "
                     f"or pass --{emulator}")
        build(version, db_path)
        meta[version] = {"emulator": emulator, "release": release_id(db_path)}

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(meta_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
