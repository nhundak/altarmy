"""Regenerate data/recipes/<version>/{trainer_skills,quest_spells,item_sources}.csv: recipe facts only the server knows.

Usage: python scripts/build-recipe-server-facts.py [--version tbc|forever|all] [--cmangos <sqlite>] [--vmangos <sqlite>]

The client's DB2 tables (scripts/generate-recipe-data.py) say which profession a recipe belongs to and its
difficulty bands, but not what a trainer requires to teach it or where a recipe item comes from. Those live
in the open-source emulators' world databases: cmangos' tbc-db for TBC, vmangos' (vanilla 1.12) for Forever.
By default this reads the release pinned in the monorepo's site/data/game-data.json, from its .cache/ or
downloaded while it is still the newest (the site's gamedata.py, loaded by its path). Stdlib only. Rerun
generate-recipe-data.py for each version afterwards. The monorepo's game_data.py (and its daily game-data
workflow) runs both with the releases it moves the pins to.

trainer_skills.csv: spell_id,req_skill — the lowest skill any trainer asks before teaching the recipe spell.
  vmangos trainers list a server-side "teach" spell; its learn effect (36) names the recipe spell.
quest_spells.csv: spell_id,req_skill — spells a quest teaches (RewSpell / RewSpellCast, through a learn
  effect when there is one) and the lowest profession skill such a quest asks (0 when none). Every quest
  reward spell is listed; generate-recipe-data.py keeps the recipe ones.
item_sources.csv: item_id,source — every way to get a recipe item (class 9), "|"-joined: vendor (a spawned
  vendor sells it), quest (a quest rewards it), drop (any loot table has it).
"""
import argparse
import csv
import importlib.util
import os
import sqlite3
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT_DIR = os.path.join(ROOT, "data", "recipes")
PINS = os.path.join(ROOT, "..", "site", "data", "game-data.json")

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
EMULATOR = {"tbc": "cmangos", "forever": "vmangos"}


def load_gamedata():
    """The site's stdlib-only gamedata.py (downloads, cache, pins), loaded by its path."""
    path = os.path.join(ROOT, "..", "site", "src", "altarmy_profit", "gamedata.py")
    spec = importlib.util.spec_from_file_location("gamedata", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["gamedata"] = module
    spec.loader.exec_module(module)
    return module


gamedata = load_gamedata()


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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--version", choices=["tbc", "forever", "all"], default="all")
    ap.add_argument("--cmangos", help="cmangos tbc-db sqlite (default: the pinned release)")
    ap.add_argument("--vmangos", help="vmangos world sqlite (default: the pinned release)")
    args = ap.parse_args()

    pins = gamedata.read_pins(Path(PINS))
    for version in ["tbc", "forever"] if args.version == "all" else [args.version]:
        emulator = EMULATOR[version]
        db_path = getattr(args, emulator)
        if not db_path:
            try:
                db_path = str(gamedata.world_db(emulator, gamedata.REPO_CACHE, pins[version].release))
            except (LookupError, ValueError) as e:
                sys.exit(f"{version}: {e}")
        if not os.path.exists(db_path):
            sys.exit(f"{version}: no {emulator} database at {db_path}")
        build(version, db_path)


if __name__ == "__main__":
    main()
