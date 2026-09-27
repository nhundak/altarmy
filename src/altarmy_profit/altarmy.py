"""Read characters, professions and learned recipes from the Alt Army addon's SavedVariables.

The file is account-wide (WTF/Account/<acct>/SavedVariables/AltArmy_TBC.lua). Characters live in
`AltArmyTBC_Data.Characters[realm][name]`; each profession has `rank`, `maxRank` and
`Recipes[recipeID] = {color, primaryRecipeID?, resultItemID?, name?}`. WoW: Forever characters also have
`legacyTalents.spells[spellID] = rank` (their Legacy talents, addon data version 2).

The addon keys characters by `UnitName("player")`, which on WoW: Forever changed from the full name
("Frell Ofelements") to the first name ("Frell"), so older files hold a renamed character twice. One
character is kept per `guid` (newer addons save it), and without GUIDs a key that is another's first name,
with the same class, race and faction, is the same character: the most recently updated entry wins.
Entries never scanned (no name, faction or class: the addon made one while the name still read
"Unknown") are skipped.

Recipe ids are craft spell ids (they match `recipes.spell_id`). On TBC clients one recipe can be stored
under several alias keys that all share a `primaryRecipeID`; Enchanting rows only carry `color`.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from .luasv import LuaTable, LuaValue, parse_assignments


@dataclass(frozen=True)
class Profession:
    name: str
    rank: int
    max_rank: int
    recipe_ids: frozenset[int]


@dataclass(frozen=True)
class Character:
    realm: str
    name: str
    faction: str  # Horde | Alliance ("" if never scanned)
    class_file: str  # e.g. PALADIN
    level: int
    professions: tuple[Profession, ...]  # sorted by name
    # Legacy talents (WoW: Forever) as (spell id, rank), ranks above 0, sorted by spell id; see `talents`
    talents: tuple[tuple[int, int], ...] = ()

    @property
    def known_recipes(self) -> frozenset[int]:
        return frozenset().union(*(p.recipe_ids for p in self.professions))


@dataclass(frozen=True)
class Group:
    """The characters of one realm and faction: they share an auction house and can mail each other."""

    realm: str
    faction: str
    characters: tuple[Character, ...]


def groups(chars: Iterable[Character]) -> list[Group]:
    """Realm/faction groups sorted by realm then faction. Characters without a faction are left out."""
    by_key: dict[tuple[str, str], list[Character]] = {}
    for c in chars:
        if c.faction:
            by_key.setdefault((c.realm, c.faction), []).append(c)
    return [Group(realm, faction, tuple(cs)) for (realm, faction), cs in sorted(by_key.items())]


def crafters(chars: Iterable[Character]) -> dict[int, list[str]]:
    """Recipe id -> names of the characters who know it."""
    out: dict[int, list[str]] = {}
    for c in chars:
        for rid in sorted(c.known_recipes):
            out.setdefault(rid, []).append(c.name)
    return out


def parse_characters(data: bytes) -> list[Character]:
    """All characters in the file, sorted by realm then name."""
    root = parse_assignments(data).get("AltArmyTBC_Data")
    if not isinstance(root, dict):
        raise ValueError("no AltArmyTBC_Data in file (is this Alt Army's AltArmy_TBC.lua?)")
    chars: list[Character] = []
    for realm, by_name in _table(root.get("Characters")).items():
        entries = {
            str(name): c
            for name, char in _table(by_name).items()
            if (c := _table(char)).get("name") or c.get("faction") or c.get("classFile")
        }
        for name in _without_renamed(entries):
            c = entries[name]
            chars.append(
                Character(
                    realm=str(realm),
                    name=name,
                    faction=_str(c.get("faction")),
                    class_file=_str(c.get("classFile")),
                    level=_int(c.get("level")),
                    professions=tuple(
                        sorted(
                            (_profession(str(n), _table(p)) for n, p in _table(c.get("Professions")).items()),
                            key=lambda p: p.name,
                        )
                    ),
                    talents=_talents(_table(c.get("legacyTalents"))),
                )
            )
    return sorted(chars, key=lambda c: (c.realm, c.name))


def _without_renamed(entries: dict[str, LuaTable]) -> list[str]:
    """The keys of one realm's entries, less those that are an older copy of another (see the module doc)."""

    def same(a: str, b: str) -> bool:
        ca, cb = entries[a], entries[b]
        ga, gb = _str(ca.get("guid")), _str(cb.get("guid"))
        if ga and gb:
            return ga == gb
        short, full = sorted((a, b), key=len)
        return (
            " " not in short
            and full.split(" ", 1)[0] == short
            and all(_str(ca.get(f)) == _str(cb.get(f)) for f in ("classFile", "raceFile", "faction"))
        )

    def newer(a: str, b: str) -> bool:
        return (_int(entries[a].get("lastUpdate")), a) > (_int(entries[b].get("lastUpdate")), b)

    return [a for a in entries if not any(b != a and same(a, b) and newer(b, a) for b in entries)]


def _talents(legacy: LuaTable) -> tuple[tuple[int, int], ...]:
    """`legacyTalents.spells` (spell id -> rank). Data version 1 has no `spells`: it was read from the class
    talent config, so it gives none."""
    got = {}
    for spell_id, rank in _table(legacy.get("spells")).items():
        if isinstance(spell_id, int) and not isinstance(spell_id, bool) and _int(rank) > 0:
            got[spell_id] = _int(rank)
    return tuple(sorted(got.items()))


def _profession(name: str, prof: LuaTable) -> Profession:
    ids = set()
    for key, row in _table(prof.get("Recipes")).items():
        primary = _table(row).get("primaryRecipeID")
        rid = primary if isinstance(primary, int) else key
        if isinstance(rid, int) and not isinstance(rid, bool):
            ids.add(rid)
    return Profession(name, _int(prof.get("rank")), _int(prof.get("maxRank")), frozenset(ids))


def _table(v: LuaValue) -> LuaTable:
    return v if isinstance(v, dict) else {}


def _str(v: LuaValue) -> str:
    return v if isinstance(v, str) else ""


def _int(v: LuaValue) -> int:
    return int(v) if isinstance(v, int | float) and not isinstance(v, bool) else 0
