"""Regenerate AltArmy_TBC/Data/Recipes/RecipeData_<TBC|Forever>.lua: every profession recipe the client has.

Usage: python scripts/generate-recipe-data.py --version tbc|forever [--build pinned|latest|<build>]
                                              [--check] [--summary <markdown file>]

Reads the client's DB2 tables as wago.tools CSV exports (downloaded once per build into .cache/wago/) and
the server-side facts in data/recipes/<version>/ (scripts/build-recipe-server-facts.py). Stdlib only.

A recipe is a SkillLineAbility row on a profession skill line whose spell takes reagents and creates an item
(effect 24) or enchants one (53) — the rule altarmy-profit's ingest uses. Each becomes
    [spellID] = { professionKey, resultItemID, reqSkill, yellow, gray, source, recipeItemID }
with false for an unknown value:
  resultItemID  the item the spell creates; 0 for an enchant
  reqSkill      the lowest skill any way of learning it asks: MinSkillLineRank for a recipe learned with the
                profession, a trainer's or quest's requirement (server data), a recipe item's RequiredSkillRank
  yellow, gray  SkillLineAbility.TrivialSkillLineRankLow / High (green is their floored midpoint)
  source        every way to learn it, "|"-joined in SOURCES order: "starter" (learned with the profession),
                "trainer", "quest" (a quest teaches the spell, or rewards its recipe item), and for recipe
                items "vendor", "reputation" (it needs a faction standing) or "drop" (server data). A recipe
                nothing else teaches is a trainer's.
  recipeItemID  the lowest id of the obtainable items teaching the spell

data/recipes/<version>/overrides.csv (spell_id,req_skill,source,note) is applied last: hand-checked values
for recipes the server data lacks or gets wrong. An empty cell keeps the generated value.

--build: pinned (default) is the build named in the existing data file; latest asks wago.tools. With
latest, a build whose recipes match the file leaves it untouched (no diff to review).
--check writes nothing: it exits 1 when the data file differs from what its pinned build gives.
--summary writes a markdown list of the recipes added, removed and changed (the workflow's PR body).
--status prints the pinned and latest builds (the recipe-data workflow reads them).
"""
import argparse
import csv
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
CACHE_DIR = os.path.join(ROOT, ".cache", "wago")
SERVER_DIR = os.path.join(ROOT, "data", "recipes")
OUT_DIR = os.path.join(ROOT, "AltArmy_TBC", "Data", "Recipes")
LATEST_URL = "https://wago.tools/api/builds/latest"
TABLE_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "altarmy-tbc-recipe-data/1.0"

FOREVER_INTERFACE = 16001
VERSIONS = {
    "tbc": {"label": "TBC", "product": "wow_anniversary", "file": "RecipeData_TBC.lua", "forever": False},
    "forever": {"label": "Forever", "product": "wow_classic_beta", "file": "RecipeData_Forever.lua",
                "forever": True},
}
TABLES = ("SkillLineAbility", "SpellEffect", "SpellReagents", "ItemEffect", "ItemSparse", "SpellName")
OPTIONAL_TABLES = ("ItemXItemEffect",)  # Forever links items to effects through it; TBC's ItemEffect names the item

SKILL_LINES = {
    40: "poisons",
    129: "firstAid",
    164: "blacksmithing",
    165: "leatherworking",
    171: "alchemy",
    185: "cooking",
    186: "mining",
    197: "tailoring",
    202: "engineering",
    333: "enchanting",
    755: "jewelcrafting",
}
EFFECT_CREATE_ITEM = 24
EFFECT_ENCHANT_ITEM = 53
TRIGGER_LEARN = 6
ACQUIRE_ON_SKILL_LEARN = 1
MAX_REAGENTS = 8
FIELDS = ("profession", "resultItemID", "reqSkill", "yellow", "gray", "source", "recipeItemID")
SOURCES = ("starter", "trainer", "quest", "vendor", "reputation", "drop")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def latest_build(product):
    builds = json.loads(fetch(LATEST_URL))
    if product not in builds:
        sys.exit(f"no {product} build in wago.tools' latest builds")
    return str(builds[product]["version"])


def download(table, build, optional=False):
    dest = os.path.join(CACHE_DIR, build, f"{table}.csv")
    if os.path.exists(dest):
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    try:
        data = fetch(TABLE_URL.format(table=table, build=build))
    except urllib.error.HTTPError as e:
        if not optional or not 400 <= e.code < 500:
            raise
        data = b""
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)
    return dest


def rows(path):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def num(value):
    try:
        return int(float(value or 0))
    except ValueError:
        return 0


def read_server_facts(version):
    base = os.path.join(SERVER_DIR, version)
    trainer = {num(r["spell_id"]): num(r["req_skill"]) for r in rows(os.path.join(base, "trainer_skills.csv"))}
    quests = {num(r["spell_id"]): num(r["req_skill"]) for r in rows(os.path.join(base, "quest_spells.csv"))}
    sources = {num(r["item_id"]): r["source"] for r in rows(os.path.join(base, "item_sources.csv"))}
    return trainer, quests, sources


def read_overrides(version):
    """spell -> (req_skill or None, source or None) from data/recipes/<version>/overrides.csv."""
    out = {}
    for r in rows(os.path.join(SERVER_DIR, version, "overrides.csv")):
        source = (r.get("source") or "").strip() or None
        if source and any(s not in SOURCES for s in source.split("|")):
            sys.exit(f"overrides.csv: unknown source {source!r} for spell {r['spell_id']}")
        out[num(r["spell_id"])] = (num(r.get("req_skill")) or None, source)
    return out


def apply_overrides(recipes, overrides):
    for spell, (req, source) in overrides.items():
        if spell not in recipes:
            sys.exit(f"overrides.csv: spell {spell} is not a recipe in this build")
        entry = list(recipes[spell])
        if req:
            entry[FIELDS.index("reqSkill")] = req
        if source:
            entry[FIELDS.index("source")] = source
        recipes[spell] = tuple(entry)
    return recipes


def learn_items(paths):
    """spell -> sorted ids of the items whose learn effect teaches it."""
    by_id = {}
    pairs = []
    for r in rows(paths["ItemEffect"]):
        parent = num(r.get("ParentItemID"))
        if parent > 0:
            pairs.append((parent, r))
        else:
            by_id[num(r["ID"])] = r
    for r in rows(paths.get("ItemXItemEffect")):
        linked = by_id.get(num(r["ItemEffectID"]))
        if linked is not None:
            pairs.append((num(r["ItemID"]), linked))
    out = {}
    for item, r in pairs:
        if num(r["TriggerType"]) == TRIGGER_LEARN:
            out.setdefault(num(r["SpellID"]), set()).add(item)
    return {spell: sorted(items) for spell, items in out.items()}


def build_recipes(paths, trainer, quests, item_sources):
    """spellID -> tuple in FIELDS order (None for unknown)."""
    outputs = {}
    enchants = set()
    for r in rows(paths["SpellEffect"]):
        effect, spell = num(r["Effect"]), num(r["SpellID"])
        if effect == EFFECT_CREATE_ITEM and num(r["EffectItemType"]) > 0:
            outputs.setdefault(spell, num(r["EffectItemType"]))
        elif effect == EFFECT_ENCHANT_ITEM:
            enchants.add(spell)
    reagents = set()
    for r in rows(paths["SpellReagents"]):
        if any(num(r.get(f"Reagent_{i}")) > 0 for i in range(MAX_REAGENTS)):
            reagents.add(num(r["SpellID"]))
    items = {}
    for r in rows(paths["ItemSparse"]):
        items[num(r["ID"])] = (num(r["RequiredSkillRank"]), num(r["MinFactionID"]))
    teaching = learn_items(paths)

    recipes = {}
    for r in rows(paths["SkillLineAbility"]):
        spell, line = num(r["Spell"]), num(r["SkillLine"])
        profession = SKILL_LINES.get(line)
        if not profession or spell in recipes or spell not in reagents:
            continue
        if spell in outputs:
            result = outputs[spell]
        elif spell in enchants:
            result = 0
        else:
            continue
        recipe_items = [i for i in teaching.get(spell, []) if i in items]
        # Several items can teach one spell, some never handed out (old or unused copies): judge by the
        # ones the server data has, else by all of them.
        obtainable = [i for i in recipe_items if i in item_sources] or recipe_items
        kinds, reqs = set(), []
        if num(r["AcquireMethod"]) == ACQUIRE_ON_SKILL_LEARN:
            kinds.add("starter")
            reqs.append(max(1, num(r["MinSkillLineRank"])))
        if spell in trainer:
            kinds.add("trainer")
            reqs.append(trainer[spell])
        if spell in quests:
            kinds.add("quest")
            reqs.append(quests[spell])
        for i in obtainable:
            if items[i][1] > 0:
                kinds.add("reputation")  # sold at a faction standing; the server lists it as a vendor's
            elif i in item_sources:
                kinds.update(item_sources[i].split("|"))
            reqs.append(items[i][0])
        if not kinds and not recipe_items:
            kinds.add("trainer")  # no recipe item, quest or starter grant teaches it: a trainer must
        reqs = [x for x in reqs if x > 0]
        req = min(reqs) if reqs else None
        source = "|".join(k for k in SOURCES if k in kinds) or None
        yellow, gray = num(r["TrivialSkillLineRankLow"]), num(r["TrivialSkillLineRankHigh"])
        if gray <= 1:
            yellow = gray = 0  # placeholder bands (The Mortar: Reloaded has 1/1): no difficulty to show
        recipes[spell] = (
            profession,
            result,
            req if req and req > 0 else None,
            yellow if yellow > 0 else None,
            gray if gray > 0 else None,
            source,
            obtainable[0] if obtainable else None,
        )
    return recipes


def lua_value(v):
    if v is None:
        return "false"
    if isinstance(v, str):
        return '"' + v + '"'
    return str(v)


def render_entries(recipes):
    return "".join(
        "    [%d] = { %s },\n" % (spell, ", ".join(lua_value(v) for v in recipes[spell]))
        for spell in sorted(recipes)
    )


def render(version, build, recipes):
    cfg = VERSIONS[version]
    skip = "~=" if cfg["forever"] else "=="
    return (
        "-- GENERATED by scripts/generate-recipe-data.py from wago.tools DB2 exports and data/recipes/"
        f"{version}/ — do not edit.\n"
        f"-- {cfg['label']} client recipes, false = unknown:\n"
        f"--   [spellID] = {{ {', '.join(FIELDS)} }}\n"
        "-- Loads only on its own client; AltArmy.RecipeInfo reads it (see AltArmy_TBC/Data/DESIGN.md).\n"
        f'local BUILD = "{build}"\n'
        "local interface = GetBuildInfo and select(4, GetBuildInfo())\n"
        f"if interface {skip} {FOREVER_INTERFACE} then return end\n"
        "\n"
        "AltArmy = AltArmy or {}\n"
        "AltArmy.RecipeData = {\n"
        "  build = BUILD,\n"
        f'  client = "{version}",\n'
        "  recipes = {\n"
        + render_entries(recipes)
        + "  },\n}\n"
    )


ENTRY_RE = re.compile(r"^\s*\[(\d+)\] = \{ (.*) \},$", re.M)
BUILD_RE = re.compile(r'^local BUILD = "([^"]+)"$', re.M)


def parse_existing(text):
    entries = {}
    for m in ENTRY_RE.finditer(text):
        vals = []
        for v in m.group(2).split(", "):
            if v == "false":
                vals.append(None)
            elif v.startswith('"'):
                vals.append(v.strip('"'))
            else:
                vals.append(int(v))
        entries[int(m.group(1))] = tuple(vals)
    build = BUILD_RE.search(text)
    return (build.group(1) if build else None), entries


def summarize(version, old_build, new_build, old, new, names):
    def label(spell, entry):
        return f"{names.get(spell, 'Spell %d' % spell)} ({spell}, {entry[0]})"

    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(s for s in set(old) & set(new) if old[s] != new[s])
    lines = [
        f"## {VERSIONS[version]['label']} recipe data: {old_build or 'none'} → {new_build}",
        "",
        f"{len(new)} recipes: **{len(added)} added**, **{len(removed)} removed**, **{len(changed)} changed**.",
    ]
    if added:
        lines += ["", "### Added"] + [f"- {label(s, new[s])}" for s in added]
    if removed:
        lines += ["", "### Removed"] + [f"- {label(s, old[s])}" for s in removed]
    if changed:
        lines += ["", "### Changed"]
        for s in changed:
            diffs = ", ".join(
                f"{f}: {lua_value(a)} → {lua_value(b)}" for f, a, b in zip(FIELDS, old[s], new[s]) if a != b
            )
            lines.append(f"- {label(s, new[s])}: {diffs}")
    lines += ["", "Generated by `scripts/generate-recipe-data.py`; merge to ship it in the next release."]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--version", choices=sorted(VERSIONS), required=True)
    ap.add_argument("--build", default="pinned", help="pinned (default), latest, or a build like 2.5.6.69795")
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 when the file is out of date")
    ap.add_argument("--summary", help="write a markdown change summary here")
    ap.add_argument("--out", help="data file to write (default: AltArmy_TBC/Data/Recipes/<file>)")
    ap.add_argument("--status", action="store_true",
                    help="print label=, pinned= and latest= lines (GitHub step output format) and exit")
    args = ap.parse_args()

    cfg = VERSIONS[args.version]
    out_path = args.out or os.path.join(OUT_DIR, cfg["file"])
    existing = ""
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            existing = f.read()
    old_build, old_entries = parse_existing(existing)

    if args.status:
        print(f"label={cfg['label']}")
        print(f"pinned={old_build or ''}")
        print(f"latest={latest_build(cfg['product'])}")
        return

    if args.build == "pinned":
        if not old_build:
            sys.exit(f"{out_path} has no pinned build; pass --build latest or a build number")
        build = old_build
    elif args.build == "latest":
        build = latest_build(cfg["product"])
    else:
        build = args.build

    paths = {t: download(t, build) for t in TABLES}
    paths.update({t: download(t, build, optional=True) for t in OPTIONAL_TABLES})
    trainer, quests, item_sources = read_server_facts(args.version)
    recipes = apply_overrides(build_recipes(paths, trainer, quests, item_sources), read_overrides(args.version))
    text = render(args.version, build, recipes)

    if args.check:
        if text != existing:
            print(f"{out_path} is out of date for build {build}: run "
                  f"python scripts/generate-recipe-data.py --version {args.version}")
            sys.exit(1)
        print(f"{cfg['file']} is up to date ({len(recipes)} recipes, build {build}).")
        return

    if args.summary:
        names = {num(r["ID"]): r["Name_lang"] for r in rows(paths["SpellName"])}
        with open(args.summary, "w", encoding="utf-8", newline="\n") as f:
            f.write(summarize(args.version, old_build, build, old_entries, recipes, names))

    if args.build == "latest" and old_entries == recipes:
        print(f"{cfg['file']}: build {build} has the same {len(recipes)} recipes as {old_build}; left unchanged.")
        return
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"{cfg['file']}: wrote {len(recipes)} recipes for build {build}.")


if __name__ == "__main__":
    main()
