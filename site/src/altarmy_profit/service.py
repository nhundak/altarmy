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

from . import altarmy, db, ingest, prices, reputation, store, talents, timing, users
from .altarmy import Character
from .engine import (
    AH_CUT,
    ALL_EXITS,
    MAIL_POSTAGE,
    Choices,
    Crafter,
    Filters,
    Learning,
    Market,
    Result,
    TimeModel,
    Unlearned,
    city_prices,
    recipes_for_characters,
    recipes_using,
)
from .versions import GameVersion

STAMP_TTL = 10.0  # seconds a cached market is trusted before its stamp is checked again


@dataclass
class _Cached:
    priced: store.Priced
    stamp: store.MarketStamp
    checked: float  # clock time of the last stamp check


def _older(stamp: store.MarketStamp, price_version: int | None) -> bool:
    """Whether a market with this stamp predates `price_version` of its auction house."""
    return price_version is not None and (stamp[3] or 0) < price_version


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

    def get(self, auction_house_id: int | None, at_least: int | None = None) -> Market:
        """The version's game data priced by the auction house (None: unpriced). `at_least`: a price
        version the caller knows of (a price signal told the front end); a market built on an older one
        is checked now, not after STAMP_TTL."""
        return self.get_priced(auction_house_id, at_least).market

    def get_priced(self, auction_house_id: int | None, at_least: int | None = None) -> store.Priced:
        """`get`'s market with the auction house's listings, built and cached together."""
        with self._lock:
            cached = self._markets.get(auction_house_id)
            now = self._clock()
            if cached is not None and now - cached.checked < STAMP_TTL and not _older(cached.stamp, at_least):
                return cached.priced
            with self.database.begin() as conn:
                stamp = store.market_stamp(conn, self.game_version, auction_house_id)
                if cached is not None and cached.stamp == stamp:
                    cached.checked = now
                    return cached.priced
                priced = store.load_priced(
                    conn,
                    self.game_version,
                    auction_house_id,
                    ah_cut=self.ah_cut,
                    mail_postage=self.mail_postage,
                )
            self._markets[auction_house_id] = _Cached(priced, stamp, now)
            return priced

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
    everything else the ranking depends on (user, characters, unlearned/trivial choices, exits, AH
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


SLOW_DAYS = 2.0  # an AH sale expected to take longer than this is flagged
ARCANE_SALVAGER_SPELL = (
    1263056  # Enchanting: Arcane Salvager (WoW: Forever), the recipe that makes the station
)


@dataclass(frozen=True)
class Selection:
    """Whose recipes count: every character of one realm and faction (they share an auction house)."""

    realm: str
    faction: str


def search(
    base: Market,
    chars: Sequence[Character],
    unlearned: Learning | Unlearned,
    filters: Filters,
    exits: frozenset[str] = ALL_EXITS,
    no_ah: frozenset[int] = frozenset(),
    include_trivial: bool = True,
    time: TimeModel | None = None,
    skill_crafters: frozenset[str] = frozenset(),
    arcane_salvager: bool = False,
) -> list[Result]:
    """Rank what the characters can craft, selling only via `exits` (never items in `no_ah` on the AH),
    and keep what `filters` accepts. Chains sub-craft through any of their recipes too. Most profitable
    first (see `by_rate` for profit per hour).

    `unlearned` adds recipes nobody has learned: those they can train (an `engine.Learning` says from which
    sources and how much skill ahead), or all of their professions' (see `engine.can_learn`).
    Disenchanting needs an enchanter among them, plus postage unless one of the recipe's crafters enchants.
    Without `include_trivial` the final craft is only done by a character it can give a skillup, and with
    `skill_crafters` by the lowest-skilled of those characters (see `Market`). With a `time`
    model each result is a session of its `batch` crafts (as `evaluate` plans one, see `session_model`),
    timed, and its time value weighs play time in every plan; without one, a single craft. Left to pick
    the city (`time.fastest`), each recipe is planned where it pays best per hour (`best_of`): vendors
    charge a character by their reputation, so cities differ in copper too. With `arcane_salvager` every
    disenchant is done at an Arcane Salvager (see `Market`).
    """
    crafts = 1
    if time is not None:
        crafts = time.config.batch
        time = session_model(time, (), None)
    min_profit = filters.min_profit if filters.min_profit is not None else -(10**18)
    models, differ = _models(base, chars, time)
    markets = [
        _market(
            base, chars, unlearned, exits, no_ah, include_trivial, model, skill_crafters, "", arcane_salvager
        )
        for model in models
    ]
    ranked = markets[0].rank(min_profit=min_profit, crafts=crafts)
    if time is not None and len(markets) > 1:
        # Only recipes that can involve an item the cities price differently are planned in the others too.
        affected = recipes_using(markets[0].recipes, differ)
        others = [m.rank(min_profit=min_profit, crafts=crafts, only=affected) for m in markets[1:]]
        ranked = best_of([ranked, *others], time.fastest, affected)
    return [r for r in ranked if filters.accepts(r)]


def evaluate(
    base: Market,
    chars: Sequence[Character],
    unlearned: Learning | Unlearned,
    exits: frozenset[str],
    recipe_id: int,
    choices: Choices,
    no_ah: frozenset[int] = frozenset(),
    include_trivial: bool = True,
    time: TimeModel | None = None,
    crafts: int = 1,
    skill_crafters: frozenset[str] = frozenset(),
    crafter: str = "",
    arcane_salvager: bool = False,
) -> Result | None:
    """One recipe with the user's `choices` of sources and exit, for `crafts` crafts at once (timed by a
    `session_model`: with `time`'s batch as `crafts` and no city, as `search` ranks it); None if the
    characters can't make or sell it. A `crafter` does the final craft (see `Market`'s `final_crafter`)."""
    models, differ = _models(base, chars, time)
    found = []
    same = False  # whether the recipe costs the same in every city: nothing in it is priced differently
    for n, model in enumerate(models):
        market = _market(
            base,
            chars,
            unlearned,
            exits,
            no_ah,
            include_trivial,
            model,
            skill_crafters,
            crafter,
            arcane_salvager,
        )
        recipe = next((r for r in market.recipes if r.id == recipe_id), None)
        if recipe is None:
            return None
        if n == 0:
            same = recipe.id not in recipes_using(market.recipes, differ)
        elif same:
            break  # as `search` ranks it: planned once, with the first model
        result = market.evaluate(recipe, choices, crafts=crafts)
        if result is not None:
            found.append(result)
    if not found:
        return None
    if time is None or len(models) == 1:
        return found[0]
    return _pick_city(found, same or len(found) == len(models), time.fastest)


PriceTerms = frozenset[tuple[int, int, int]]  # `engine.city_prices`: what a city's vendors take off for whom


def _price_groups(
    cities: Sequence[timing.CityMap], crafters: Sequence[Crafter], discounts: Mapping[int, int]
) -> dict[PriceTerms, list[timing.CityMap]]:
    known = [dict(reputation.vendor_discounts(c.reputations, discounts)) for c in crafters]
    groups: dict[PriceTerms, list[timing.CityMap]] = {}
    for city in cities:
        groups.setdefault(city_prices(city, known), []).append(city)
    return groups


def city_groups(
    cities: Sequence[timing.CityMap], crafters: Sequence[Crafter], discounts: Mapping[int, int]
) -> list[tuple[timing.CityMap, ...]]:
    """`cities` grouped by what their vendors charge `crafters` (`discounts`: the version's percent off by
    standing): a plan costs the same in every city of a group. In the cities' order; one group when nobody
    has a standing that counts."""
    return [tuple(g) for g in _price_groups(cities, crafters, discounts).values()]


def _models(
    base: Market, chars: Sequence[Character], time: TimeModel | None
) -> tuple[list[TimeModel | None], frozenset[int]]:
    """`time` as the models to plan with: itself, unless it leaves the city open (`fastest`) and those
    cities charge the characters differently; then one per group of cities charging the same
    (`city_groups`), each guided by `time`'s own city if it has it, that group first. With them, the vendor
    items that cost some character more in one group than in another."""
    if time is None or len(time.fastest) < 2:
        return [time], frozenset()
    groups = _price_groups(time.fastest, as_crafters(chars), base.reputation_discounts)
    if len(groups) == 1:
        return [time], frozenset()
    everywhere = frozenset.intersection(*groups)
    differ = frozenset(item for terms in groups for _, item, _ in terms - everywhere)
    guide = time.city
    models = [replace(time, city=guide if guide in g else g[0], fastest=tuple(g)) for g in groups.values()]
    models.sort(key=lambda m: m.city is not guide)
    return [*models], differ


def city_worth(usable: bool, profit: int, per_hour: int, seconds: float) -> tuple[bool, bool, int, float]:
    """What a recipe is worth in a city, to compare it with the same recipe in another (the greater wins):
    a city with every station the plan needs (`usable`) first, then one where it profits, then the most
    copper per hour (the smallest loss where it doesn't profit), then the quicker."""
    return (usable, profit > 0, per_hour if profit > 0 else profit, -seconds)


def _worth(r: Result) -> tuple[bool, bool, int, float]:
    """`city_worth` of a result in the city it is timed in."""
    t = r.timing
    assert t is not None
    return city_worth(not t.missing, r.profit, t.per_hour(r.profit), t.total_seconds)


def _pick_city(found: Sequence[Result], everywhere: bool, cities: tuple[timing.CityMap, ...]) -> Result:
    """One recipe's results, each planned in a group of cities: if they are one plan `everywhere` (every
    group gave the same, or only the first was asked because nothing in the recipe is priced differently),
    that plan, timed in whichever of all `cities` is quickest once somebody asks; else the one worth most
    (`_worth`; ties keep the first), the others as its `alternatives`."""
    first = found[0]
    if everywhere and all(r == first for r in found[1:]) and first.time_model is not None:
        return replace(first, time_model=replace(first.time_model, fastest=cities))
    if len(found) == 1:
        return first
    best = max(found, key=_worth)
    return replace(best, alternatives=tuple(r for r in found if r is not best))


def best_of(
    rankings: Sequence[Sequence[Result]], cities: tuple[timing.CityMap, ...], affected: frozenset[int]
) -> list[Result]:
    """One ranking from those of each group of `cities` that charges the crafters differently (see
    `_models`): every recipe where it is worth most (`_pick_city`), most profitable first. Only the
    `affected` recipes (ids) were ranked in every group; the rest cost the same everywhere and are in the
    first ranking alone. Only recipes whose plans differ between the groups are timed for it."""
    by_recipe: dict[int, list[Result]] = {}
    for ranking in rankings:
        for r in ranking:
            by_recipe.setdefault(r.recipe.id, []).append(r)
    picked = [
        _pick_city(found, recipe_id not in affected or len(found) == len(rankings), cities)
        for recipe_id, found in by_recipe.items()
    ]
    return sorted(picked, key=lambda r: r.profit, reverse=True)


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
    unlearned: Learning | Unlearned,
    exits: frozenset[str],
    no_ah: frozenset[int],
    include_trivial: bool,
    time: TimeModel | None = None,
    skill_crafters: frozenset[str] = frozenset(),
    crafter: str = "",
    arcane_salvager: bool = False,
) -> Market:
    """`base` narrowed to what the characters can craft (see `search`), with them as the crafters. Without
    characters every recipe counts, crafted by one unnamed character (so nothing is mailed)."""
    crafters = as_crafters(chars)
    recipes = recipes_for_characters(base.recipes, crafters, unlearned) if chars else list(base.recipes)
    return Market(
        base.items,
        recipes,
        base.prices,
        base.disenchant,
        base.ah_cut,
        crafters=crafters,
        unlearned=unlearned,
        exits=exits,
        no_ah=no_ah,
        include_trivial=include_trivial,
        skill_crafters=skill_crafters,
        final_crafter=crafter,
        mail_postage=base.mail_postage,
        sell_prices=base.sell_prices,
        time=time,
        books=base.books,
        reputation_discounts=base.reputation_discounts,
        arcane_salvager=arcane_salvager,
    )


def knows_arcane_salvager(chars: Sequence[Character]) -> bool:
    """Whether any of the characters has learned to craft an Arcane Salvager (the search's default for
    disenchanting at one)."""
    return any(ARCANE_SALVAGER_SPELL in c.known_recipes for c in chars)


def as_crafters(chars: Sequence[Character]) -> list[Crafter]:
    """The characters as the engine's crafters: their professions, recipes, standings and what their
    Legacy talents do."""
    return [
        Crafter(
            c.name,
            tuple((p.name, p.rank, p.max_rank) for p in c.professions),
            c.known_recipes,
            talents.extra_results(c.talents),
            talents.vendor_discount(c.talents),
            c.reputations,
            talents.skill_bonus(c.talents),
        )
        for c in chars
    ]


def thin_market(r: Result, listings: Mapping[int, prices.Listing]) -> bool:
    """Whether the result's sale on the AH rests on a thin market: fewer units listed than
    `prices.THIN_UNITS` or than the plan sells. Informational: the ranking doesn't use it."""
    listing = listings.get(r.recipe.output_item_id)
    if r.best_exit != "ah" or listing is None:
        return False
    return prices.thin_market(listing.quantity, r.recipe.output_count * r.crafts)


def days_to_sell(r: Result, listings: Mapping[int, prices.Listing], sell_price: int | None) -> float | None:
    """How long the result's AH sale may take, in days: the units listed at or under `sell_price`
    (they sell first) plus the plan's own, at the rate the item sold lately. None when it is not sold
    on the AH or nothing says how fast it sells."""
    listing = listings.get(r.recipe.output_item_id)
    if r.best_exit != "ah" or listing is None or sell_price is None or not listing.sale_rate:
        return None
    ahead = sum(lv.quantity for lv in listing.ladder if lv.price <= sell_price)
    return (ahead + r.recipe.output_count * r.crafts) / listing.sale_rate


def slow_to_sell(r: Result, listings: Mapping[int, prices.Listing], sell_price: int | None) -> bool:
    """Whether the result's AH sale may take over SLOW_DAYS (`days_to_sell`), or, where nothing says how
    fast the item sells, rests on a thin market (`thin_market`). Informational: the ranking doesn't use
    it."""
    days = days_to_sell(r, listings, sell_price)
    return thin_market(r, listings) if days is None else days > SLOW_DAYS


def by_rate(results: Iterable[Result]) -> list[Result]:
    """`results` by profit per hour, best first (untimed ones last; ties keep their order). Times every
    result, once: they cache their timing."""
    return sorted(results, key=lambda r: -(r.rate if r.rate is not None else -(10**18)))


def by_skill(results: Iterable[Result]) -> list[Result]:
    """`results` by what an expected skill point costs, cheapest first (so profitable ones lead), those that
    can't give one last; ties go to the surer skill point, then the more profitable."""

    def key(r: Result) -> tuple[bool, float, float, int]:
        ups = r.skill_ups
        return (ups == 0, -r.profit / ups if ups else 0.0, -r.skill_chance, -r.profit)

    return sorted(results, key=key)


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
    """Download the version's pinned build's DB2 tables (`data/game-data.json`, which the game-data workflow
    moves) and rebuild items/recipes (prices are kept).

    With `only_if_new` (the ingest job, daily and after each deploy), skip the rebuild when the database
    already holds the pinned build, loaded by this ingest code from these hand-maintained CSVs
    (`ingest.fingerprint`). Without it, always rebuild.
    Returns (build, whether it rebuilt, row counts).
    """
    build = ingest.pinned_build(version)
    if (
        only_if_new
        and db.get_build(conn, version.key) == build
        and db.get_fingerprint(conn, version.key) == ingest.fingerprint(version)
    ):
        return build, False, current_counts(conn, version.key)
    stats = ingest.update(
        conn,
        version.key,
        build,
        cache_dir,
        version.disenchant_csv,
        version.vendor_csv,
        version.vendor_recipes_csv,
        version.sources_csv,
    )
    return build, True, stats


def current_counts(conn: Connection, game_version: str) -> dict[str, int]:
    """The same counts `ingest.update` reports, read from the database as it stands."""
    return {
        "items": db.count_rows(conn, "items", game_version),
        "recipes": db.count_rows(conn, "recipes", game_version),
        "disenchant_rows": db.count_rows(conn, "disenchant", game_version),
        "vendor_items": db.count_rows(conn, "vendor_items", game_version),
    }
