"""Use-cases behind the web API: the shared market cache, search, characters and selection.

No HTTP here. User state is per `user_uid`. Characters come from the Alt Army addon and prices from
Auctionator, both through uploads (`uploads.py`), or from characters made by hand.
"""

from __future__ import annotations

import json
import threading
import time
from collections import OrderedDict
from collections.abc import Callable, Hashable, Iterable, Mapping, Sequence
from dataclasses import dataclass, replace
from pathlib import Path

from sqlalchemy import Connection

from . import altarmy, db, ingest, prices, store, talents, timing, users
from .altarmy import Character
from .engine import (
    AH_CUT,
    ALL_EXITS,
    MAIL_POSTAGE,
    Choices,
    Crafter,
    Filters,
    Market,
    Result,
    TimeModel,
    recipes_for_characters,
)
from .versions import GameVersion

STAMP_TTL = 10.0  # seconds a cached market is trusted before its stamp is checked again


@dataclass
class _Cached:
    market: Market
    stamp: store.MarketStamp
    checked: float  # clock time of the last stamp check


class MarketCache:
    """In-process Markets for one game version, one per auction house, shared by all requests; rebuilt
    from the database lazily after invalidate().

    Other processes (instances, the ingest job) change the database too, so a market is also rebuilt when
    its `store.market_stamp` moved, checked at most every STAMP_TTL seconds.

    Market is read-only once built, so handing the same instance to several threads is safe.
    """

    def __init__(
        self,
        database: db.Database,
        game_version: str,
        *,
        ah_cut: float = AH_CUT,
        mail_postage: int = MAIL_POSTAGE,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.database = database
        self.game_version = game_version
        self.ah_cut = ah_cut
        self.mail_postage = mail_postage
        self._clock = clock
        self._lock = threading.Lock()
        self._markets: dict[int | None, _Cached] = {}

    def get(self, auction_house_id: int | None) -> Market:
        """The version's game data priced by the auction house (None: unpriced)."""
        with self._lock:
            cached = self._markets.get(auction_house_id)
            now = self._clock()
            if cached is not None and now - cached.checked < STAMP_TTL:
                return cached.market
            with self.database.begin() as conn:
                stamp = store.market_stamp(conn, self.game_version, auction_house_id)
                if cached is not None and cached.stamp == stamp:
                    cached.checked = now
                    return cached.market
                market = store.load_market(
                    conn,
                    self.game_version,
                    auction_house_id,
                    ah_cut=self.ah_cut,
                    mail_postage=self.mail_postage,
                )
            self._markets[auction_house_id] = _Cached(market, stamp, now)
            return market

    def invalidate(self, auction_house_ids: Iterable[int] | None = None) -> None:
        """Drop the cached markets of these auction houses (default: all)."""
        with self._lock:
            if auction_house_ids is None:
                self._markets.clear()
            for ah in auction_house_ids or ():
                self._markets.pop(ah, None)


class RankCache:
    """The last `size` full rankings (`search` results), so paging through one ("Show more") and refetching
    it don't rank again. An entry only counts for the very Market it was ranked on: once the MarketCache
    rebuilds a market (new prices, a merge, new game data), its rankings miss. The key must cover
    everything else the ranking depends on (user, characters, unlearned/trivial switches, exits, AH
    blocks); bounds on cost, profit and ROI and the profession filter are applied to a cached ranking."""

    def __init__(self, size: int = 64) -> None:
        self.size = size
        self._lock = threading.Lock()
        self._entries: OrderedDict[Hashable, tuple[Market, list[Result]]] = OrderedDict()

    def get(self, key: Hashable, base: Market) -> list[Result] | None:
        with self._lock:
            found = self._entries.get(key)
            if found is None or found[0] is not base:
                return None
            self._entries.move_to_end(key)
            return found[1]

    def put(self, key: Hashable, base: Market, results: list[Result]) -> None:
        with self._lock:
            self._entries[key] = (base, results)
            self._entries.move_to_end(key)
            while len(self._entries) > self.size:
                self._entries.popitem(last=False)


@dataclass(frozen=True)
class Selection:
    """Whose recipes count: every character of one realm and faction (they share an auction house)."""

    realm: str
    faction: str


def search(
    base: Market,
    chars: Sequence[Character],
    include_unlearned: bool,
    filters: Filters,
    exits: frozenset[str] = ALL_EXITS,
    no_ah: frozenset[int] = frozenset(),
    include_trivial: bool = True,
    time: TimeModel | None = None,
) -> list[Result]:
    """Rank what the characters can craft, selling only via `exits` (never items in `no_ah` on the AH),
    and keep what `filters` accepts. Chains sub-craft through any of their recipes too. Most profitable
    first (see `by_rate` for profit per hour).

    `include_unlearned` widens that to every recipe of the characters' professions. Disenchanting needs
    an enchanter among them, plus postage unless one of the recipe's crafters enchants. Without
    `include_trivial` the final craft is only done by a character it can give a skillup. With a `time`
    model the results are timed, and its time value weighs play time in every plan.
    """
    market = _market(base, chars, include_unlearned, exits, no_ah, include_trivial, time)
    min_profit = filters.min_profit if filters.min_profit is not None else -(10**18)
    return [r for r in market.rank(min_profit=min_profit) if filters.accepts(r)]


def evaluate(
    base: Market,
    chars: Sequence[Character],
    include_unlearned: bool,
    exits: frozenset[str],
    recipe_id: int,
    choices: Choices,
    no_ah: frozenset[int] = frozenset(),
    include_trivial: bool = True,
    time: TimeModel | None = None,
    crafts: int = 1,
) -> Result | None:
    """One recipe as `search` would rank it, but with the user's `choices` of sources and exit, for
    `crafts` crafts at once (see `session_model` for timing them); None if the characters can't make or sell
    it."""
    market = _market(base, chars, include_unlearned, exits, no_ah, include_trivial, time)
    recipe = next((r for r in market.recipes if r.id == recipe_id), None)
    return None if recipe is None else market.evaluate(recipe, choices, crafts=crafts)


def session_model(time: TimeModel, cities: Sequence[timing.CityMap], city: str | None) -> TimeModel:
    """`time` for a session planned as a whole (its crafts are the batch: `batch` 1), in `city` if given
    (one of `cities`, the selection's faction's), else as `time` picks. ValueError for another city."""
    config = replace(time.config, batch=1)
    if city is None:
        return replace(time, config=config)
    found = next((c for c in cities if c.name == city), None)
    if found is None:
        raise ValueError(f"{city} is not a city these characters craft in.")
    return TimeModel(config, found)


def _market(
    base: Market,
    chars: Sequence[Character],
    include_unlearned: bool,
    exits: frozenset[str],
    no_ah: frozenset[int],
    include_trivial: bool,
    time: TimeModel | None = None,
) -> Market:
    """`base` narrowed to what the characters can craft (see `search`), with them as the crafters. Without
    characters every recipe counts, crafted by one unnamed character (so nothing is mailed)."""
    if chars:
        known = frozenset().union(*(c.known_recipes for c in chars))
        professions = {p.name for c in chars for p in c.professions}
        recipes = recipes_for_characters(base.recipes, known, professions, include_unlearned)
    else:
        recipes = list(base.recipes)
    crafters = [
        Crafter(
            c.name,
            tuple((p.name, p.rank, p.max_rank) for p in c.professions),
            c.known_recipes,
            talents.extra_results(c.talents),
            talents.vendor_discount(c.talents),
        )
        for c in chars
    ]
    return Market(
        base.items,
        recipes,
        base.prices,
        base.disenchant,
        base.ah_cut,
        crafters=crafters,
        include_unlearned=include_unlearned,
        exits=exits,
        no_ah=no_ah,
        include_trivial=include_trivial,
        mail_postage=base.mail_postage,
        sell_prices=base.sell_prices,
        time=time,
    )


def by_rate(results: Iterable[Result]) -> list[Result]:
    """`results` by profit per hour, best first (untimed ones last; ties keep their order). Times every
    result, once: they cache their timing."""
    return sorted(results, key=lambda r: -(r.rate if r.rate is not None else -(10**18)))


def favorites_first(results: Iterable[Result], favorites: frozenset[int]) -> list[Result]:
    """`results` with the favorite recipes' first; each part keeps its order."""
    listed = list(results)
    return [r for r in listed if r.recipe.id in favorites] + [
        r for r in listed if r.recipe.id not in favorites
    ]


# --- profit per hour -------------------------------------------------------------------------------
DEFAULT_CITIES = ("Orgrimmar", "Stormwind")  # where a faction's plans are timed unless the user picks


def faction_cities(cities: Mapping[str, timing.CityMap], faction: str) -> list[timing.CityMap]:
    """The cities a character of `faction` crafts in: their faction's, by name; every faction city for
    faction "" (an auction house both factions share). Never a neutral town (Booty Bay, ...): its auction
    house is not the one prices come from."""
    return sorted(
        (c for c in cities.values() if c.faction and (not faction or c.faction == faction)),
        key=lambda c: c.name,
    )


def default_city(cities: Mapping[str, timing.CityMap], faction: str) -> timing.CityMap:
    """The faction's capital, else its first city, else `timing.ANYWHERE` (no presets)."""
    allowed = faction_cities(cities, faction)
    preferred = [c for c in allowed if c.name in DEFAULT_CITIES and (c.faction == faction or not faction)]
    return (preferred or allowed or [timing.ANYWHERE])[0]


def time_model(
    conn: Connection,
    user_uid: str,
    game_version: str,
    cities: Mapping[str, timing.CityMap],
    faction: str,
) -> TimeModel:
    """The user's time settings: their saved city if a `faction` character crafts there, else whichever of
    the faction's cities is fastest for each plan (the default), and their config overrides."""
    saved = users.get_settings(conn, user_uid, game_version)
    config = timing.config_from_json(saved.time_config)
    allowed = faction_cities(cities, faction)
    if saved.time_city in {c.name for c in allowed}:
        return TimeModel(config, cities[saved.time_city])
    return TimeModel(config, default_city(cities, faction), tuple(allowed))


def set_time(
    conn: Connection,
    user_uid: str,
    game_version: str,
    cities: Mapping[str, timing.CityMap],
    city: str | None,
    config: Mapping[str, object],
) -> None:
    """Save the user's city (None: the faction's default) and config overrides (replacing the old ones);
    ValueError for an unknown city or a bad setting."""
    if city is not None and (city not in cities or not cities[city].faction):
        raise ValueError(f"No city preset named {city}.")
    changes = timing.config_changes(timing.config_from_dict(config))
    users.update_settings(
        conn,
        user_uid,
        game_version,
        time_city=city,
        time_config=json.dumps(changes) if changes else None,
    )


# --- realm/faction selection -----------------------------------------------------------------------
def realm_label(realm: str, faction: str) -> str:
    """ "Realm (Faction)", or "Realm (both factions)" for an auction house the factions share."""
    return f"{realm} ({faction or 'both factions'})"


def _known_auction_house(conn: Connection, game_version: str, realm: str, faction: str) -> bool:
    return bool(realm) and prices.find_auction_house(conn, game_version, realm, faction) is not None


def selection(
    conn: Connection, user_uid: str, game_version: str, chars: Sequence[Character]
) -> Selection | None:
    """The saved realm/faction if it still has characters or an auction house, else the group with the
    most characters, else the realm scanned most recently; None if there is none of these."""
    groups = altarmy.groups(chars)
    saved = users.get_settings(conn, user_uid, game_version)
    realm, faction = saved.selected_realm or "", saved.selected_faction or ""
    for g in groups:
        if (g.realm, g.faction) == (realm, faction):
            return Selection(g.realm, g.faction)
    if _known_auction_house(conn, game_version, realm, faction):
        return Selection(realm, faction)
    if groups:
        best = max(groups, key=lambda g: len(g.characters))
        return Selection(best.realm, best.faction)
    freshest = prices.freshest_auction_house(conn, game_version)
    return None if freshest is None else Selection(*freshest)


def select(conn: Connection, user_uid: str, game_version: str, realm: str, faction: str) -> None:
    """Select a realm/faction that has characters or an auction house (faction "" for one both factions
    share); ValueError otherwise."""
    groups = altarmy.groups(store.load_characters(conn, user_uid, game_version))
    has_group = any((g.realm, g.faction) == (realm, faction) for g in groups)
    if not has_group and not _known_auction_house(conn, game_version, realm, faction):
        raise ValueError(f"no characters or prices on {realm_label(realm, faction)}")
    users.update_settings(conn, user_uid, game_version, selected_realm=realm, selected_faction=faction)


def replace_characters(
    conn: Connection, user_uid: str, game_version: str, chars: Sequence[Character]
) -> None:
    """Store an import's characters in place of the user's. A selected realm none of them is on is
    forgotten, so the new characters' biggest group is selected."""
    store.save_characters(conn, user_uid, game_version, chars)
    saved = users.get_settings(conn, user_uid, game_version)
    wanted = (saved.selected_realm, saved.selected_faction)
    if not any((g.realm, g.faction) == wanted for g in altarmy.groups(chars)):
        users.update_settings(conn, user_uid, game_version, selected_realm=None, selected_faction=None)


def delete_character(conn: Connection, user_uid: str, game_version: str, realm: str, name: str) -> None:
    """Delete one of the user's characters; FileNotFoundError if there is no such character."""
    if not store.delete_character(conn, user_uid, game_version, realm, name):
        raise FileNotFoundError(f"No character {name} on {realm}.")
    bump_data_version(conn, user_uid, game_version)


def selected_characters(
    conn: Connection, user_uid: str, game_version: str
) -> tuple[Selection | None, list[Character]]:
    chars = store.load_characters(conn, user_uid, game_version)
    sel = selection(conn, user_uid, game_version, chars)
    if sel is None:
        return None, []
    return sel, [c for c in chars if (c.realm, c.faction) == (sel.realm, sel.faction)]


def auction_house_of(conn: Connection, game_version: str, sel: Selection | None) -> int | None:
    """The auction house that prices a selection (the unnamed one without characters); None if unknown.
    One named after an Auctionator key (its scan came before the characters) is found by that alias."""
    if sel is None:
        return prices.find_auction_house(conn, game_version, "", "")
    found = prices.find_auction_house(conn, game_version, sel.realm, sel.faction)
    if found is None:
        found = prices.find_auction_house_by_alias(conn, game_version, sel.realm, sel.faction)
    return found


def selected_auction_house(conn: Connection, user_uid: str, game_version: str) -> int | None:
    sel, _ = selected_characters(conn, user_uid, game_version)
    return auction_house_of(conn, game_version, sel)


def match_auctionator_realm(realms: Iterable[str], realm: str, faction: str) -> str | None:
    """Auctionator's key for a realm: the realm name without spaces, plus the faction where the auction
    houses are split (e.g. "ClassicBetaPvE", "Dreamscythe Horde")."""
    have = set(realms)
    nospace = realm.replace(" ", "")
    for key in (f"{nospace} {faction}", nospace, f"{realm} {faction}", realm):
        if key in have:
            return key
    return None


# --- user data version ----------------------------------------------------------------------------
def data_version(conn: Connection, user_uid: str, game_version: str) -> int:
    """Bumped whenever the user's characters or prices were re-imported, so the front end refetches."""
    return users.get_settings(conn, user_uid, game_version).data_version


def bump_data_version(conn: Connection, user_uid: str, game_version: str) -> None:
    users.update_settings(
        conn, user_uid, game_version, data_version=data_version(conn, user_uid, game_version) + 1
    )


# --- game data -------------------------------------------------------------------------------------
def update_game_data(
    conn: Connection,
    version: GameVersion,
    cache_dir: Path,
    *,
    only_if_new: bool = False,
) -> tuple[str, bool, dict[str, int]]:
    """Download the version's newest build's DB2 tables and rebuild items/recipes (prices are kept).

    With `only_if_new` (the daily ingest job), skip the rebuild when the database already holds the newest
    build. Without it, always rebuild, since the version's disenchant.csv or vendor_items.csv may have
    changed.
    Returns (build, whether it rebuilt, row counts).
    """
    build = ingest.latest_build(version.wago_product)
    if only_if_new and db.get_build(conn, version.key) == build:
        return build, False, current_counts(conn, version.key)
    stats = ingest.update(conn, version.key, build, cache_dir, version.disenchant_csv, version.vendor_csv)
    return build, True, stats


def current_counts(conn: Connection, game_version: str) -> dict[str, int]:
    """The same counts `ingest.update` reports, read from the database as it stands."""
    return {
        "items": db.count_rows(conn, "items", game_version),
        "recipes": db.count_rows(conn, "recipes", game_version),
        "disenchant_rows": db.count_rows(conn, "disenchant", game_version),
        "vendor_items": db.count_rows(conn, "vendor_items", game_version),
    }
