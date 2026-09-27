"""Load database rows into the engine's plain dataclasses, store each user's characters and AH blocks, and
search an auction house's prices."""

from __future__ import annotations

import json
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, fields
from pathlib import Path

from sqlalchemy import Connection, delete, func, select

from . import db, itemstats, prices, schema, timing
from .altarmy import Character, Profession
from .engine import AH_CUT, MAIL_POSTAGE, DisenchantRow, Item, Market, Recipe

CACHE_DIR = Path("cache")
IN_CHUNK = 900  # ids per IN (...) query, under SQLite's bound-parameter limit


@dataclass(frozen=True)
class ItemDetails:
    """What an item tooltip shows. Not needed by the engine, so it is not part of engine.Item."""

    id: int
    name: str
    quality: int
    class_id: int
    subclass_name: str | None
    inventory_type: int
    bonding: int
    item_delay: int  # ms
    container_slots: int
    required_level: int
    required_skill: str | None
    required_skill_rank: int
    description: str | None
    sell_price: int
    icon: str | None
    armor: int
    dmg_min: int
    dmg_max: int
    dps: float
    stats: tuple[str, ...]  # white tooltip lines ("+18 Strength")
    effects: tuple[itemstats.Effect, ...]  # green lines (Equip, Use, Chance on hit)


def _json_list(text: str) -> list[object]:
    try:
        value = json.loads(text)
    except ValueError:
        return []
    return list(value) if isinstance(value, list) else []


def _stat_lines(text: str) -> tuple[str, ...]:
    return tuple(s for s in _json_list(text) if isinstance(s, str))


def _effect_lines(text: str) -> tuple[itemstats.Effect, ...]:
    return tuple(
        itemstats.Effect(str(e["trigger"]), str(e["text"]))
        for e in _json_list(text)
        if isinstance(e, dict) and "trigger" in e and "text" in e
    )


MarketStamp = tuple[str | None, int | None, int | None]


def market_stamp(conn: Connection, game_version: str, auction_house_id: int | None) -> MarketStamp:
    """What a cached market was built from: the version's game data build, the auction house's newest
    snapshot (every price write adds one) and its price version (every merge that changed something bumps
    it). If any moved, the market is stale."""
    if auction_house_id is None:
        return db.get_build(conn, game_version), None, None
    snap = schema.price_snapshots
    newest = conn.execute(
        select(func.max(snap.c.id)).where(snap.c.auction_house_id == auction_house_id)
    ).scalar_one_or_none()
    return db.get_build(conn, game_version), newest, prices.price_version(conn, auction_house_id)


def load_market(
    conn: Connection,
    game_version: str,
    auction_house_id: int | None,
    *,
    ah_cut: float = AH_CUT,
    mail_postage: int = MAIL_POSTAGE,
) -> Market:
    """One version's game data priced by an auction house's current prices (None: no prices), with the
    version's AH cut and postage per attachment."""
    i, v = schema.items, schema.vendor_items
    sold = (
        select(v.c.item_id)
        .where(v.c.game_version == game_version, v.c.item_id == i.c.id)
        .exists()
        .label("sold")
    )
    items = {
        r.id: Item(
            r.id,
            r.name,
            r.quality,
            r.item_level,
            r.class_id,
            r.sell_price,
            -(-r.buy_price // r.buy_count) if r.sold and r.buy_price > 0 else None,
            r.stack_size,
            tradable=r.bonding not in (1, 4),  # bind on pickup, quest item
        )
        for r in conn.execute(select(i, sold).where(i.c.game_version == game_version))
    }
    rr = schema.recipe_reagents
    reagents: dict[int, list[tuple[int, int]]] = {}
    for recipe_id, item_id, count in conn.execute(
        select(rr.c.recipe_id, rr.c.item_id, rr.c.count)
        .where(rr.c.game_version == game_version)
        .order_by(rr.c.recipe_id, rr.c.slot)
    ):
        reagents.setdefault(recipe_id, []).append((item_id, count))
    rt = schema.recipes
    recipes = [
        Recipe(
            r.id,
            r.name,
            r.output_item_id,
            r.output_count,
            tuple(reagents.get(r.id, ())),
            r.skill_name,
            r.min_skill,
            r.spell_id,
            r.trivial_low,
            r.trivial_high,
            cast_time_ms=r.cast_time_ms,
            station=r.station,
        )
        for r in conn.execute(select(rt).where(rt.c.game_version == game_version).order_by(rt.c.id))
    ]
    d = schema.disenchant
    de = [
        DisenchantRow(
            r.item_class,
            r.quality,
            r.min_ilvl,
            r.max_ilvl,
            r.result_item_id,
            r.chance,
            r.min_count,
            r.max_count,
        )
        for r in conn.execute(select(d).where(d.c.game_version == game_version).order_by(d.c.id))
    ]
    buy, sell = prices.load_buy_and_sell(conn, auction_house_id)
    return Market(items, recipes, buy, de, ah_cut, mail_postage=mail_postage, sell_prices=sell)


def load_cities(folder: Path) -> dict[str, timing.CityMap]:
    """The city presets in `folder` (a version's `cities_dir`) by name, sorted; none if it is missing.
    ValueError naming the file if one is malformed."""
    out: dict[str, timing.CityMap] = {}
    for path in sorted(folder.glob("*.json")) if folder.is_dir() else ():
        try:
            city = timing.CityMap.from_dict(json.loads(path.read_text(encoding="utf-8")))
        except (ValueError, TypeError) as e:
            raise ValueError(f"bad city preset {path.name}: {e}") from e
        out[city.name] = city
    return dict(sorted(out.items()))


def load_item_details(conn: Connection, game_version: str, ids: Iterable[int]) -> dict[int, ItemDetails]:
    """Tooltip details for the given item ids; unknown ids are left out."""
    wanted = sorted(set(ids))
    t = schema.items
    columns = [t.c[f.name] for f in fields(ItemDetails)]
    out: dict[int, ItemDetails] = {}
    for start in range(0, len(wanted), IN_CHUNK):
        chunk = wanted[start : start + IN_CHUNK]
        query = select(*columns).where(t.c.game_version == game_version, t.c.id.in_(chunk))
        for r in conn.execute(query):
            d = dict(r._mapping)
            d["stats"] = _stat_lines(d["stats"])
            d["effects"] = _effect_lines(d["effects"])
            out[r.id] = ItemDetails(**d)
    return out


def save_characters(conn: Connection, user_uid: str, game_version: str, chars: Sequence[Character]) -> None:
    """Replace the user's characters of the version with `chars` (Alt Army's file is the source of truth)."""
    c = schema.characters
    # professions and recipes cascade
    conn.execute(delete(c).where(c.c.user_uid == user_uid, c.c.game_version == game_version))
    for ch in chars:
        _insert_character(conn, user_uid, game_version, ch)


def delete_character(conn: Connection, user_uid: str, game_version: str, realm: str, name: str) -> bool:
    """Delete the user's character of that realm and name (its professions and recipes cascade); False if
    there was none."""
    c = schema.characters
    done = conn.execute(
        delete(c).where(
            c.c.user_uid == user_uid, c.c.game_version == game_version, c.c.realm == realm, c.c.name == name
        )
    )
    return bool(done.rowcount)


def _insert_character(conn: Connection, user_uid: str, game_version: str, ch: Character) -> None:
    c = schema.characters
    char_id: int = conn.execute(
        c.insert()
        .values(
            user_uid=user_uid,
            game_version=game_version,
            realm=ch.realm,
            name=ch.name,
            faction=ch.faction,
            class_file=ch.class_file,
            level=ch.level,
        )
        .returning(c.c.id)
    ).scalar_one()
    for p in ch.professions:
        conn.execute(
            schema.character_professions.insert().values(
                character_id=char_id, skill_name=p.name, rank=p.rank, max_rank=p.max_rank
            )
        )
        if p.recipe_ids:
            conn.execute(
                schema.character_recipes.insert(),
                [
                    {"character_id": char_id, "skill_name": p.name, "spell_id": spell}
                    for spell in sorted(p.recipe_ids)
                ],
            )
    if ch.talents:
        conn.execute(
            schema.character_talents.insert(),
            [{"character_id": char_id, "spell_id": spell, "rank": rank} for spell, rank in ch.talents],
        )


def load_characters(conn: Connection, user_uid: str, game_version: str) -> list[Character]:
    """The user's characters of the version sorted by realm then name, professions sorted by name."""
    c, cp, cr = schema.characters, schema.character_professions, schema.character_recipes
    owned = (c.c.user_uid == user_uid, c.c.game_version == game_version)
    mine = select(c.c.id).where(*owned)
    recipes: dict[tuple[int, str], set[int]] = {}
    for r in conn.execute(select(cr).where(cr.c.character_id.in_(mine))):
        recipes.setdefault((r.character_id, r.skill_name), set()).add(r.spell_id)
    profs: dict[int, list[Profession]] = {}
    for r in conn.execute(select(cp).where(cp.c.character_id.in_(mine)).order_by(cp.c.skill_name)):
        key = (r.character_id, r.skill_name)
        profs.setdefault(r.character_id, []).append(
            Profession(r.skill_name, r.rank, r.max_rank, frozenset(recipes.get(key, ())))
        )
    ct = schema.character_talents
    talents: dict[int, list[tuple[int, int]]] = {}
    for r in conn.execute(select(ct).where(ct.c.character_id.in_(mine)).order_by(ct.c.spell_id)):
        talents.setdefault(r.character_id, []).append((r.spell_id, r.rank))
    return [
        Character(
            r.realm,
            r.name,
            r.faction,
            r.class_file,
            r.level,
            tuple(profs.get(r.id, ())),
            tuple(talents.get(r.id, ())),
        )
        for r in conn.execute(select(c).where(*owned).order_by(c.c.realm, c.c.name))
    ]


# Skill lines with recipes in DB2 that aren't professions a player picks (class skills, a test line).
HIDDEN_PROFESSIONS = frozenset({"Comprehension", "Demonology", "Poisons", "Test Profession [DNT]"})


def profession_names(conn: Connection, game_version: str) -> list[str]:
    """Every profession the version's recipes belong to, by name, but `HIDDEN_PROFESSIONS`."""
    r = schema.recipes
    query = (
        select(r.c.skill_name)
        .where(r.c.game_version == game_version, r.c.skill_name.not_in(HIDDEN_PROFESSIONS))
        .distinct()
        .order_by(r.c.skill_name)
    )
    names: list[str] = list(conn.execute(query).scalars().all())
    return names


def count_characters(conn: Connection, user_uid: str, game_version: str) -> int:
    c = schema.characters
    query = select(func.count()).where(c.c.user_uid == user_uid, c.c.game_version == game_version)
    return int(conn.execute(query).scalar_one())


def load_favorites(conn: Connection, user_uid: str, game_version: str) -> list[tuple[int, str]]:
    """The user's favorite recipes as (recipe id, when added as UTC text), newest first."""
    t = schema.favorite_recipes
    rows = conn.execute(
        select(t.c.recipe_id, t.c.added_at)
        .where(t.c.user_uid == user_uid, t.c.game_version == game_version)
        .order_by(t.c.added_at.desc(), t.c.recipe_id)
    )
    return [(r.recipe_id, db.timestamp_text(r.added_at) or "") for r in rows]


def set_favorite(conn: Connection, user_uid: str, game_version: str, recipe_id: int, favorite: bool) -> None:
    """Mark `recipe_id` as a favorite, or not."""
    t = schema.favorite_recipes
    if favorite:
        row = {
            "user_uid": user_uid,
            "game_version": game_version,
            "recipe_id": recipe_id,
            "added_at": db.utcnow(),
        }
        db.upsert(conn, t, [row], ["user_uid", "game_version", "recipe_id"], update=[])
    else:
        conn.execute(
            delete(t).where(
                t.c.user_uid == user_uid, t.c.game_version == game_version, t.c.recipe_id == recipe_id
            )
        )


def load_ah_blocked(conn: Connection, user_uid: str, game_version: str) -> list[tuple[int, str]]:
    """Items the user never sells on the AH as (item id, when added as UTC text), newest first."""
    t = schema.ah_blocked
    rows = conn.execute(
        select(t.c.item_id, t.c.added_at)
        .where(t.c.user_uid == user_uid, t.c.game_version == game_version)
        .order_by(t.c.added_at.desc(), t.c.item_id)
    )
    return [(r.item_id, db.timestamp_text(r.added_at) or "") for r in rows]


def set_ah_blocked(conn: Connection, user_uid: str, game_version: str, item_id: int, blocked: bool) -> None:
    """Never sell `item_id` on the AH, or allow it again."""
    t = schema.ah_blocked
    if blocked:
        row = {
            "user_uid": user_uid,
            "game_version": game_version,
            "item_id": item_id,
            "added_at": db.utcnow(),
        }
        db.upsert(conn, t, [row], ["user_uid", "game_version", "item_id"], update=[])
    else:
        conn.execute(
            delete(t).where(
                t.c.user_uid == user_uid, t.c.game_version == game_version, t.c.item_id == item_id
            )
        )
