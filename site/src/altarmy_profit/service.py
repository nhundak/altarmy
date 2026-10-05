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
from typing import Literal

from sqlalchemy import Connection

from . import altarmy, db, ingest, prices, reputation, store, talents, timing, users
from .altarmy import Character
from .engine import (
    AH_CUT,
    ALL_EXITS,
    MAIL_POSTAGE,
    MAX_LOOK_AHEAD,
    Candidate,
    Choices,
    Crafter,
    Filters,
    Learning,
    Market,
    Memo,
    Recipe,
    Result,
    SkillRun,
    SkillRuns,
    TimeModel,
    Unlearned,
    ah_net,
    can_learn,
    city_prices,
    recipes_for_characters,
    recipes_using,
    useful_crafts,
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
    skill_name: str | None = None,
    skill_run: SkillRuns | None = None,
    gathered: Mapping[int, int] | None = None,
    learn_costs: Mapping[int, float | None] | None = None,
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
    disenchant is done at an Arcane Salvager (see `Market`). With `skill_name`, only that profession's
    recipes are ranked. With a `skill_run`, each recipe is ranked as the final crafter's run of it, not as a
    batch: the first run of the cheapest climb up the profession that starts with it (`engine.Climb`, over
    the recipes they can craft now and those they can learn on the way: `later_recipes`; `learn_costs` is
    what learning each costs the climber, by recipe id). `gathered` items (with what a unit is worth:
    `gather_values`) may be gathered instead of bought.
    """
    crafts = 1
    if time is not None:
        crafts = time.config.batch
        time = session_model(time, (), None)
    min_profit = filters.min_profit if filters.min_profit is not None else -(10**18)
    models, differ = _models(base, chars, time)
    later = later_recipes(
        base,
        chars,
        unlearned,
        exits,
        no_ah,
        skill_crafters,
        arcane_salvager,
        skill_name,
        skill_run,
        gathered,
        models[0],
    )
    markets = [
        _market(
            base,
            chars,
            unlearned,
            exits,
            no_ah,
            include_trivial,
            model,
            skill_crafters,
            "",
            arcane_salvager,
            gathered,
            later,
            learn_costs,
        )
        for model in models
    ]
    ranked = markets[0].rank(min_profit=min_profit, crafts=crafts, skill_name=skill_name, skill_run=skill_run)
    if time is not None and len(markets) > 1:
        # Only recipes that can involve an item the cities price differently are planned in the others too.
        affected = recipes_using(markets[0].recipes, differ)
        others = [
            m.rank(
                min_profit=min_profit,
                crafts=crafts,
                skill_name=skill_name,
                only=affected,
                skill_run=skill_run,
            )
            for m in markets[1:]
        ]
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
    skill_run: SkillRuns | None = None,
    gathered: Mapping[int, int] | None = None,
    learn_costs: Mapping[int, float | None] | None = None,
    stretch: SkillRun | None = None,
) -> Result | None:
    """One recipe with the user's `choices` of sources and exit, for `crafts` crafts at once (timed by a
    `session_model`: with `time`'s batch as `crafts` and no city, as `search` ranks it), or as a useful run
    (`skill_run` and `learn_costs`, as `search` ranks it then; or the `stretch` of a climb given, planned
    from where it starts); None if the characters can't make or sell it. A `crafter` does the final craft
    (see `Market`'s `final_crafter`)."""
    models, differ = _models(base, chars, time)
    recipe_skill = next((r.skill_name for r in base.recipes if r.id == recipe_id), None)
    later = (
        later_recipes(
            base,
            chars,
            unlearned,
            exits,
            no_ah,
            skill_crafters,
            arcane_salvager,
            recipe_skill,
            skill_run,
            gathered,
            models[0],
        )
        if stretch is None
        else []
    )
    markets = [
        _market(
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
            gathered,
            later,
            learn_costs,
        )
        for model in models
    ]
    return _evaluate_in(markets, differ, time, recipe_id, choices, crafts, skill_run, stretch)


def _evaluate_in(
    markets: Sequence[Market],
    differ: frozenset[int],
    time: TimeModel | None,
    recipe_id: int,
    choices: Choices,
    crafts: int,
    skill_run: SkillRuns | None,
    stretch: SkillRun | None = None,
) -> Result | None:
    """`evaluate` on its markets, one per group of cities that charge the characters differently
    (`_models`, `differ` the items priced differently): the recipe where it is worth most."""
    found = []
    same = False  # whether the recipe costs the same in every city: nothing in it is priced differently
    for n, market in enumerate(markets):
        recipe = next((r for r in market.recipes if r.id == recipe_id), None)
        if recipe is None:
            return None
        if n == 0:
            same = recipe.id not in recipes_using(market.recipes, differ)
        elif same:
            break  # as `search` ranks it: planned once, with the first model
        result = market.evaluate(recipe, choices, crafts=crafts, skill_run=skill_run, stretch=stretch)
        if result is not None:
            found.append(result)
    if not found:
        return None
    if time is None or len(markets) == 1:
        return found[0]
    return _pick_city(found, same or len(found) == len(markets), time.fastest)


def climb_options(
    base: Market,
    chars: Sequence[Character],
    unlearned: Learning | Unlearned,
    exits: frozenset[str],
    no_ah: frozenset[int],
    include_trivial: bool,
    time: TimeModel | None,
    skill_crafters: frozenset[str],
    arcane_salvager: bool,
    skill_run: SkillRuns,
    ranked: Sequence[Result],
    gathered: Mapping[int, int] | None = None,
    learn_costs: Mapping[int, float | None] | None = None,
) -> list[Result]:
    """The skill workspace's options side by side: `ranked`, the first few runs of a `search` with
    `skill_run`, each planned again as the first run of the cheapest climb that never crafts the options
    before it (`SkillRuns.banned`): someone looking past the best option doesn't want it, so the second
    option's climb never comes back to the first, the third's to either. The first stays as it is; one
    that no longer gives a point is left out, and those after it may craft it (only the options shown are
    passed over). Planned on one set of markets, as `evaluate` plans a run."""
    if not ranked:
        return []
    out = [ranked[0]]
    if len(ranked) == 1:
        return out
    if time is not None:
        time = session_model(time, (), None)
    skill_name = ranked[0].recipe.skill_name
    models, differ = _models(base, chars, time)
    later = later_recipes(
        base,
        chars,
        unlearned,
        exits,
        no_ah,
        skill_crafters,
        arcane_salvager,
        skill_name,
        skill_run,
        gathered,
        models[0],
    )
    markets = [
        _market(
            base,
            chars,
            unlearned,
            exits,
            no_ah,
            include_trivial,
            model,
            skill_crafters,
            "",
            arcane_salvager,
            gathered,
            later,
            learn_costs,
        )
        for model in models
    ]
    for r in ranked[1:]:
        banned = skill_run.banned | {p.recipe.id for p in out}
        found = _evaluate_in(
            markets, differ, time, r.recipe.id, {}, r.crafts, replace(skill_run, banned=frozenset(banned))
        )
        if found is not None and found.skill_ups:
            out.append(found)
    return out


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
    gathered: Mapping[int, int] | None = None,
    later: Sequence[Candidate] = (),
    learn_costs: Mapping[int, float | None] | None = None,
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
        gathered=gathered,
        later_recipes=later,
        learn_costs=learn_costs,
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


def price_confidence(
    r: Result, listings: Mapping[int, prices.Listing], watched: float
) -> prices.Confidence | None:
    """How far the result's AH sell price can be trusted (`prices.confidence`); None when it is not sold
    on the AH or nothing is known of the item there."""
    listing = listings.get(r.recipe.output_item_id)
    if r.best_exit != "ah" or listing is None:
        return None
    return prices.confidence(listing, r.recipe.output_count * r.crafts, watched)


CONFIDENCE_RANK: dict[prices.ConfidenceLevel, int] = {"low": 0, "medium": 1, "high": 2}


def confident(
    r: Result, listings: Mapping[int, prices.Listing], watched: float, least: prices.ConfidenceLevel
) -> bool:
    """Whether the result's sell price is trusted at least `least`. A sale off the AH always is."""
    c = price_confidence(r, listings, watched)
    return c is None or CONFIDENCE_RANK[c.level] >= CONFIDENCE_RANK[least]


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
    """Whether the result's AH sale may take over SLOW_DAYS (`days_to_sell`). Informational: the ranking
    doesn't use it. Where nothing says how fast it sells, `price_confidence` says what is known."""
    days = days_to_sell(r, listings, sell_price)
    return days is not None and days > SLOW_DAYS


@dataclass(frozen=True)
class Likely:
    """What a result is likely to make: its profit with the AH units beyond what the market has shown it
    takes (`depth_units`) counted at the best other exit (`excess_units` of them), and the exit that then
    pays best (`exit`)."""

    profit: int
    exit: str
    depth_units: int
    excess_units: int


def likely(r: Result, listings: Mapping[int, prices.Listing], sell_price: int | None) -> Likely:
    """`r`'s likely profit (see `Likely`). An AH sale of an item from Alt Army's scans counts on as many
    units as the market has shown it takes: the more of those seen sold over the last week and those listed
    at or under `sell_price` (a crude depth, until a model of what sells replaces it). The units beyond go
    to the best other exit (or are worth nothing), and when that exit outright pays better, it is the
    likely one. Any other sale, or a price from another source, is what it is."""
    listing = listings.get(r.recipe.output_item_id)
    ah = next((e for e in r.exits if e.kind == "ah"), None)
    if r.best_exit != "ah" or ah is None or listing is None or listing.source != prices.ALTARMY:
        return Likely(r.profit, r.best_exit, 0, 0)
    units = r.recipe.output_count * r.crafts
    sold = round((listing.sale_rate or 0.0) * prices.SALES_DAYS)
    ahead = sum(lv.quantity for lv in listing.ladder if sell_price is not None and lv.price <= sell_price)
    depth = max(sold, ahead)
    excess = max(0, units - depth)
    fallback = max((e.value - e.postage for e in r.exits if e.kind != "ah"), default=0)
    capped = r.profit - excess * (ah.value - fallback)
    other = max((o for o in r.sell_options if o.kind != "ah"), key=lambda o: o.profit, default=None)
    if other is not None and other.profit >= capped:
        return Likely(other.profit, other.kind, depth, excess)
    return Likely(capped, "ah", depth, excess)


def by_likely(
    results: Iterable[Result], listings: Mapping[int, prices.Listing], market: Market
) -> list[Result]:
    """`results` by likely profit (`likely`), best first; ties keep their order."""
    worth = {
        id(r): likely(r, listings, market.sell_prices.get(r.recipe.output_item_id)).profit for r in results
    }
    return sorted(results, key=lambda r: -worth[id(r)])


VerdictLevel = Literal["steady", "likely", "unproven"]
VERDICT_RANK: dict[VerdictLevel, int] = {"unproven": 0, "likely": 1, "steady": 2}
_TIER: dict[prices.ConfidenceLevel, VerdictLevel] = {"high": "steady", "medium": "likely", "low": "unproven"}
_WEAKER: dict[VerdictLevel, VerdictLevel] = {"steady": "likely", "likely": "unproven", "unproven": "unproven"}
MATERIAL_SHARE = 0.25  # a disenchant's verdict weighs the materials carrying at least this share of its value


@dataclass(frozen=True)
class Verdict:
    """Whether a result's sale will sell, in a word: `steady` (a vendor, or sales seen that cover it),
    `likely`, `unproven`. `reasons` say why it is no surer, most actionable first (`prices.ConfidenceFlag`s,
    `unsold`, `few_sold`, `unknown` when nothing is known of the item on the AH, `disenchant_unchecked`);
    `buy_flags` what about buying the reagents makes it one less sure (`short`: more than is listed;
    `just_listed`: the cheapest listing of an AH reagent is new since the scan before)."""

    level: VerdictLevel
    reasons: tuple[str, ...] = ()
    buy_flags: tuple[str, ...] = ()


def _sure(listing: prices.Listing | None, units: int, watched: float) -> tuple[VerdictLevel, tuple[str, ...]]:
    """How sure an AH sale of `units` is, and why: from the price's confidence."""
    if listing is None:
        return "unproven", ("unknown",)
    sure = prices.confidence(listing, units, watched)
    told = (sure.reason,) if sure.reason in ("unsold", "few_sold") else ()
    return _TIER[sure.level], (*told, *(f for f in sure.flags if f not in told))


def verdict(
    r: Result,
    listings: Mapping[int, prices.Listing],
    watched: float,
    market: Market,
    disenchant_verified: bool,
) -> Verdict:
    """Whether `r`'s sale will sell (see `Verdict`). A vendor pays, so it is steady (and so is what is
    never sold). An AH sale is as sure as its price (`prices.confidence`: high steady, medium likely, low
    unproven). A disenchant is as sure as the least sure of the materials carrying at least
    `MATERIAL_SHARE` of its value, and while the disenchant table is unchecked (`disenchant_verified`) never
    more than likely. Buying more than is listed, or from a listing new since the scan before, makes it one
    less sure."""
    if r.best_exit == "ah":
        level, reasons = _sure(
            listings.get(r.recipe.output_item_id), r.recipe.output_count * r.crafts, watched
        )
    elif r.best_exit == "disenchant":
        level, reasons = _disenchant_sure(r, listings, watched, disenchant_verified)
    else:
        level, reasons = "steady", ()
    flags = (*(("short",) if r.short > 0 else ()), *(("just_listed",) if _fresh_buy(r, market) else ()))
    if flags:
        level = _WEAKER[level]
    return Verdict(level, reasons, flags)


def _disenchant_sure(
    r: Result, listings: Mapping[int, prices.Listing], watched: float, verified: bool
) -> tuple[VerdictLevel, tuple[str, ...]]:
    exit = next((e for e in r.exits if e.kind == "disenchant"), None)
    materials = exit.materials if exit is not None else ()
    total = sum(m.value or 0 for m in materials)
    weighed = [
        m for m in materials if m.value is None or (total and (m.value or 0) >= MATERIAL_SHARE * total)
    ]
    level: VerdictLevel = "steady"
    reasons: list[str] = []
    for m in weighed:
        sure, why = (
            _sure(listings.get(m.item_id), 1, watched) if m.value is not None else ("unproven", ("unknown",))
        )
        if VERDICT_RANK[sure] < VERDICT_RANK[level]:
            level = sure
        reasons += [w for w in why if w not in reasons]
    if not verified and level == "steady":
        level, reasons = "likely", [*reasons, "disenchant_unchecked"]
    return level, tuple(reasons)


def _fresh_buy(r: Result, market: Market) -> bool:
    """Whether the plan buys a reagent on the AH whose cheapest listing counted on is new since the scan
    before."""
    for s in r.steps:
        if s.action == "buy" and s.via == "ah":
            ladder = market.books.get(s.item_id)
            if ladder and ladder[0].age == 0:
                return True
    return False


PICK_FLOOR = (
    10_000  # copper a session must likely make for the coach to pick it (a guess, tuned by the replay)
)
CoachNoneReason = Literal["nothing", "below_floor", "all_thin", "no_watched_sales", "none_sure"]


@dataclass(frozen=True)
class CoachNone:
    """Why the coach picked nothing: nothing ranked; the surest craft (`best`) makes under the floor; every AH
    sale rests on a thin market; nobody watched the house's sales; nothing else was sure enough."""

    reason: CoachNoneReason
    best: Result | None = None


def coach_pick(
    results: Sequence[Result],
    listings: Mapping[int, prices.Listing],
    watched: float,
    market: Market,
    disenchant_verified: bool,
    floor: int = PICK_FLOOR,
) -> tuple[Result | None, CoachNone | None]:
    """The one craft to recommend next, or why there is none: the first by likely profit whose sale is at
    least likely (`verdict`) with nothing about buying it in doubt, that counts on no units beyond what the
    market takes (`likely`), that for an AH sale rests on at least `prices.THIN_UNITS` listed, and that likely
    makes `floor`. A guarded pick: it never recommends what the numbers can't carry."""
    if not results:
        return None, CoachNone("nothing")
    ordered = by_likely(results, listings, market)
    surest: Result | None = None
    for r in ordered:
        judged = verdict(r, listings, watched, market, disenchant_verified)
        made = likely(r, listings, market.sell_prices.get(r.recipe.output_item_id))
        if not at_least_verdict("likely", judged.level) or judged.buy_flags or made.excess_units:
            continue
        if r.best_exit == "ah":
            listing = listings.get(r.recipe.output_item_id)
            if listing is None or (listing.quantity or 0) < prices.THIN_UNITS:
                continue
        if made.profit >= floor:
            return r, None
        surest = surest or r
    if surest is not None:
        return None, CoachNone("below_floor", surest)
    doubts = [
        verdict(r, listings, watched, market, disenchant_verified).reasons
        for r in ordered
        if r.best_exit == "ah"
    ]
    if doubts and all("thin" in d or "lone" in d for d in doubts):
        return None, CoachNone("all_thin")
    if watched < prices.WATCHED_ENOUGH_HOURS:
        return None, CoachNone("no_watched_sales")
    return None, CoachNone("none_sure")


def at_least_verdict(least: VerdictLevel, level: VerdictLevel) -> bool:
    """Whether `level` is at least as sure as `least`."""
    return VERDICT_RANK[level] >= VERDICT_RANK[least]


def by_roi(results: Iterable[Result]) -> list[Result]:
    """`results` by ROI, best first."""
    return sorted(results, key=lambda r: -r.roi)


def by_spend(results: Iterable[Result]) -> list[Result]:
    """`results` by what they spend, least first."""
    return sorted(results, key=lambda r: r.cost)


def by_profit_each(results: Iterable[Result]) -> list[Result]:
    """`results` by profit per unit made, best first."""
    return sorted(results, key=lambda r: -r.profit / max(1, r.recipe.output_count * r.crafts))


def by_rate(results: Iterable[Result]) -> list[Result]:
    """`results` by profit per hour, best first (untimed ones last; ties keep their order). Times every
    result, once: they cache their timing."""
    return sorted(results, key=lambda r: -(r.rate if r.rate is not None else -(10**18)))


def by_skill(
    results: Iterable[Result], learn_cost: Callable[[Result], int | None] | None = None
) -> list[Result]:
    """`results` by what an expected skill point costs, cheapest first (so profitable ones lead), those that
    can't give one last; ties go to the surer skill point, then the more profitable. With `learn_cost`,
    what learning the recipe costs (`learn_cost`) counts too, and a recipe whose cost is unknown comes after
    every one whose cost is known. Runs that start a climb (`Result.climb_cost`) go by the whole climb
    instead, its patterns included, before the rest: the one starting the cheapest climb first, those
    buying fewer patterns of unknown price before the others."""

    def key(r: Result) -> tuple[bool, bool, int, float, float, int]:
        ups = r.skill_ups
        if r.climb_cost is not None:
            return (ups == 0, False, r.climb_unknown, r.climb_cost, -r.skill_chance, -r.profit)
        learn = learn_cost(r) if learn_cost is not None else 0
        spent = -r.profit + (learn or 0)
        return (ups == 0, True, int(learn is None), spent / ups if ups else 0.0, -r.skill_chance, -r.profit)

    return sorted(results, key=key)


def later_recipes(
    base: Market,
    chars: Sequence[Character],
    unlearned: Learning | Unlearned,
    exits: frozenset[str],
    no_ah: frozenset[int],
    skill_crafters: frozenset[str],
    arcane_salvager: bool,
    skill_name: str | None,
    skill_run: SkillRuns | None,
    gathered: Mapping[int, int] | None,
    time: TimeModel | None = None,
) -> list[Candidate]:
    """The recipes of `skill_name`'s profession (every profession's, without one) the one character skilled up
    can't learn yet but can on the way to their cap (taught by `unlearned`'s sources), each with the skill
    they can learn it from and what a craft of it comes to then: planned as the climb's run of it will be,
    with the climber at that skill and everything else as it is (`unlearned` for every other recipe and
    character, the `time` model), for its `useful_crafts`. A climb may take them up there (`engine.Climb`).
    None without runs or one character, or with `unlearned` "none" (the recipes they know only)."""
    learning = Learning.of(unlearned)
    if skill_run is None or len(skill_crafters) != 1 or learning.unlearned == "none":
        return []
    (name,) = skill_crafters
    climber = next((c for c in chars if c.name == name), None)
    held = {
        p.name.lower(): p
        for p in (climber.professions if climber else ())
        if skill_name is None or p.name.lower() == skill_name.lower()
    }
    if climber is None or not held:
        return []
    # what they can learn on the way: a look-ahead to the cap, for the climber's climbed professions alone
    ahead = Learning(
        "train", max(MAX_LOOK_AHEAD, *(p.max_rank - p.rank for p in held.values())), learning.sources
    )
    (crafter,) = as_crafters([climber])
    later: dict[tuple[str, int], list[Recipe]] = {}
    for r in base.recipes:
        p = held.get(r.skill_name.lower())
        if r.anyone or p is None or r.required_skill <= p.rank or r.spell_id in climber.known_recipes:
            continue
        if can_learn(r, crafter, ahead):
            later.setdefault((r.skill_name, r.required_skill), []).append(r)
    out = []
    for (profession, level), recipes in sorted(later.items()):
        there = at_skill(chars, name, profession, level)
        market = _market(
            base, there, unlearned, exits, no_ah, False, time, skill_crafters, "", arcane_salvager, gathered
        )
        (raised,) = (c for c in market.crafters if c.name == name)
        memo: Memo = {}
        for r in recipes:
            n = useful_crafts(r, raised)
            one = market.evaluate(r, memo=memo, crafts=n)
            if one is not None and one.crafter == name:
                out.append(Candidate(r, -one.profit / n, level))
    return out


def gather_values(base: Market, item_ids: Iterable[int]) -> dict[int, int]:
    """What a unit of each item the user gathers is worth to them: what selling it would make (on the AH,
    after the cut, else to a vendor), never less than a copper, so gathering is never free."""
    out = {}
    for i in item_ids:
        if i in base.sell_prices:
            worth = ah_net(base.sell_prices[i], base.ah_cut)
        else:
            item = base.items.get(i)
            worth = item.sell_price if item is not None else 0
        out[i] = max(1, worth)
    return out


def at_skill(chars: Sequence[Character], name: str, skill_name: str, level: int) -> list[Character]:
    """`chars` with `name`'s `skill_name` at `level` (never lowered)."""
    wanted = skill_name.lower()

    def raised(c: Character) -> Character:
        if c.name != name:
            return c
        return replace(
            c,
            professions=tuple(
                replace(p, rank=max(p.rank, level)) if p.name.lower() == wanted else p for p in c.professions
            ),
        )

    return [raised(c) for c in chars]


def trained_up(chars: Sequence[Character], name: str, skill_name: str | None, cap: int) -> list[Character]:
    """`chars` with `name`'s `skill_name` (every profession, without one) capped at `cap` (never lowered): a
    climb assumes the one skilled up trains each profession rank as they come to it."""
    wanted = skill_name.lower() if skill_name else None

    def raised(c: Character) -> Character:
        if c.name != name:
            return c
        return replace(
            c,
            professions=tuple(
                replace(p, max_rank=max(p.max_rank, cap)) if wanted in (None, p.name.lower()) else p
                for p in c.professions
            ),
        )

    return [raised(c) for c in chars]


def skill_chain(
    base: Market,
    chars: Sequence[Character],
    unlearned: Learning | Unlearned,
    exits: frozenset[str],
    no_ah: frozenset[int],
    include_trivial: bool,
    time: TimeModel | None,
    skill_crafters: frozenset[str],
    arcane_salvager: bool,
    skill_run: SkillRuns,
    *,
    first: Result,
    steps: int,
    gathered: Mapping[int, int] | None = None,
    done: Sequence[Result] = (),
) -> list[Result]:
    """The runs of `first`'s climb after it (`Result.climb_after`), up to `steps` of them, each planned for
    its own crafts with the climber at the skill it starts from (as `search` plans a run: timed by a
    `session_model`). Fewer when the climb ends sooner (at the cap, or where nothing gives a point). `done`:
    the first runs, already planned (a shorter `skill_chain` of the same `first`), kept rather than planned
    again."""
    out: list[Result] = list(done[:steps])
    if time is not None:
        time = session_model(time, (), None)
    for stretch in first.climb_after[len(out) : steps]:
        if stretch.recipe is None:
            break
        there = at_skill(chars, first.crafter, stretch.recipe.skill_name, stretch.start_skill)
        r = evaluate(
            base,
            there,
            unlearned,
            exits,
            stretch.recipe.id,
            {},
            no_ah,
            include_trivial,
            time,
            stretch.crafts,
            skill_crafters,
            "",
            arcane_salvager,
            skill_run=skill_run,
            gathered=gathered,
            stretch=stretch,
        )
        if r is None:
            break
        out.append(r)
    return out


def pattern_price(
    items: Sequence[store.RecipeItem], ah_prices: Mapping[int, int], faction: str
) -> int | None:
    """The least any of `items` (those teaching one recipe) costs: from a vendor serving `faction`, or on
    the AH; None if nothing says."""
    other = {"horde": "alliance", "alliance": "horde"}.get(faction.lower(), "")
    found = []
    for i in items:
        if i.buy_price is not None and any(p.kind == "vendor" and p.side != other for p in i.places):
            found.append(i.buy_price)
        if i.item_id in ah_prices:
            found.append(ah_prices[i.item_id])
    return min(found, default=None)


def learn_cost(
    r: Result,
    chars: Sequence[Character],
    taught: Mapping[int, Sequence[store.RecipeItem]],
    ah_prices: Mapping[int, int],
    faction: str,
) -> int | None:
    """What the result's crafter must spend to learn its recipe (`recipe_learn_cost`)."""
    who = next((c for c in chars if c.name == r.crafter), None)
    return recipe_learn_cost(r.recipe, who, taught, ah_prices, faction)


def recipe_learn_cost(
    recipe: Recipe,
    who: Character | None,
    taught: Mapping[int, Sequence[store.RecipeItem]],
    ah_prices: Mapping[int, int],
    faction: str,
) -> int | None:
    """What `who` must spend to learn `recipe`: 0 when they know it (or it needs no learning, or a trainer
    teaches it: fees are not known yet), else what its pattern costs (`pattern_price`; `taught` by spell
    id), None when nothing says."""
    if who is None or recipe.anyone or recipe.spell_id in who.known_recipes or recipe.source == "trainer":
        return 0
    return pattern_price(taught.get(recipe.spell_id, ()), ah_prices, faction)


def needs_pattern(recipe: Recipe, who: Character | None) -> bool:
    """Whether what learning `recipe` costs `who` is a pattern's price (`recipe_learn_cost`)."""
    return recipe_learn_cost(recipe, who, {}, {}, "") is None


def climb_learn_costs(
    base: Market,
    who: Character,
    skill_name: str | None,
    taught: Mapping[int, Sequence[store.RecipeItem]],
    faction: str,
) -> dict[int, float | None]:
    """What learning each recipe of `skill_name`'s profession (every profession's, without one) costs `who`
    (`recipe_learn_cost`), by recipe id, for a climb (`search`'s `learn_costs`); those that cost nothing left
    out. `taught`: the patterns of the recipes that `needs_pattern`, by spell id."""
    wanted = skill_name.lower() if skill_name else None
    out: dict[int, float | None] = {}
    for r in base.recipes:
        if wanted is not None and r.skill_name.lower() != wanted:
            continue
        cost = recipe_learn_cost(r, who, taught, base.prices, faction)
        if cost != 0:
            out[r.id] = cost
    return out


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
