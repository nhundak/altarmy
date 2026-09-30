import os
from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import Connection

from altarmy_profit import altarmy, book, db, engine, ingest, prices, service, store, talents, timing, users
from altarmy_profit.altarmy import Character, Profession
from altarmy_profit.engine import ALL_EXITS, Filters
from altarmy_profit.service import Selection

from .conftest import FOREVER, ME, scanned, set_prices
from .test_altarmy import ALTARMY_SV


def chars(*names: str) -> list[Character]:
    return [c for c in altarmy.parse_characters(ALTARMY_SV) if not names or c.name in names]


def touch(path: Path) -> None:
    """Move the mtime forward a second (a rewrite within the clock's resolution may not change it)."""
    st = path.stat()
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))


def test_search_ranks_known_recipes_or_whole_professions(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))

    profitable = Filters(min_profit=0)
    (r,) = service.search(base, chars("Tailor Guy"), "none", profitable)
    assert r.profit == 200
    assert service.search(base, chars("Tailor Guy"), "none", Filters(min_profit=201)) == []
    assert service.search(base, chars("Tailor Guy"), "none", Filters(max_cost=299)) == []
    assert service.search(base, chars("Tailor Guy"), "none", profitable, exits=frozenset({"ah"})) == []
    assert service.search(base, chars("Frell", "Ally Alt"), "none", profitable) == []
    (browsed,) = service.search(base, [], "none", profitable)  # no characters: every recipe, nobody named
    assert (browsed.recipe.name, browsed.crafter, browsed.postage) == ("Green Robe", "", 0)

    (tailor,) = chars("Tailor Guy")
    novice = replace(tailor, professions=(Profession("Tailoring", 1, 75, frozenset()),))
    assert service.search(base, [novice], "none", profitable) == []
    unlearned = service.search(base, [novice], "all", profitable)
    assert [r.recipe.name for r in unlearned] == ["Green Robe"]


def test_search_and_evaluate_without_trivial_recipes(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))
    (tailor,) = chars("Tailor Guy")  # Tailoring 50: the robe turns grey at 60
    (robe,) = base.recipes
    profitable = Filters(min_profit=0)
    assert len(service.search(base, [tailor], "none", profitable, include_trivial=False)) == 1

    (p,) = [p for p in tailor.professions if p.name == "Tailoring"]
    veteran = replace(tailor, professions=(replace(p, rank=60, max_rank=150),))
    assert len(service.search(base, [veteran], "none", profitable)) == 1
    assert service.search(base, [veteran], "none", profitable, include_trivial=False) == []
    assert service.evaluate(base, [veteran], "none", ALL_EXITS, robe.id, {}, include_trivial=False) is None


def test_evaluate_applies_choices(db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))  # vendors sell thread for 11c
    best = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {})
    assert best is not None
    assert (best.cost, best.tree.inputs[1].source) == (211, "vendor")
    chosen = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {"r.1": "ah"})
    assert chosen is not None
    assert (chosen.cost, chosen.tree.inputs[1].source) == (300, "ah")
    assert service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 999, {}) is None
    assert service.evaluate(base, chars("Frell"), "none", ALL_EXITS, 100, {}) is None


def test_legacy_talents_reach_the_engine(
    db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))  # vendors sell thread for 11c
    (tailor,) = chars("Tailor Guy")
    barterer = replace(tailor, talents=((talents.BARTERING, 2),))
    got = service.evaluate(base, [barterer], "none", ALL_EXITS, 100, {})
    assert got is not None
    assert (got.cost, got.tree.inputs[1].discount) == (200 + 10, 10)  # 11c less 10%, rounded up


def test_search_and_evaluate_never_sell_blocked_items_on_the_ah(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the robe: 950 on the AH beats 500 at a vendor
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100, 3: 1000}))
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters())
    assert r.best_exit == "ah"
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters(), no_ah=frozenset({3}))
    assert (r.best_exit, [e.kind for e in r.exits]) == ("vendor", ["vendor"])
    got = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {}, no_ah=frozenset({3}))
    assert got is not None
    assert got.best_exit == "vendor"


def test_search_without_min_profit_keeps_losses(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 100, 2: 100}))  # 10 linen > the robe
    assert service.search(base, chars("Tailor Guy"), "none", Filters(min_profit=0)) == []
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters())
    assert r.profit < 0


@pytest.mark.parametrize(
    ("realms", "realm", "faction", "key"),
    [
        (["ClassicBetaPvE", "ClassicBetaPvP2"], "Classic Beta PvE", "Horde", "ClassicBetaPvE"),
        (["ClassicBetaPvE", "ClassicBetaPvP2"], "Classic Beta PvP 2", "Alliance", "ClassicBetaPvP2"),
        (["Dreamscythe Alliance", "Dreamscythe Horde"], "Dreamscythe", "Horde", "Dreamscythe Horde"),
        (["Defias Pillager Alliance"], "Defias Pillager", "Alliance", "Defias Pillager Alliance"),
        (["Atiesh"], "Dreamscythe", "Horde", None),
    ],
)
def test_match_auctionator_realm(realms: list[str], realm: str, faction: str, key: str | None) -> None:
    assert service.match_auctionator_realm(realms, realm, faction) == key


def test_selection_defaults_to_biggest_group_then_remembers(conn: Connection) -> None:
    assert service.selection(conn, ME, FOREVER, []) is None
    assert service.selected_characters(conn, ME, FOREVER) == (None, [])
    store.save_characters(conn, ME, FOREVER, chars())
    assert service.selection(conn, ME, FOREVER, chars()) == Selection("Dreamscythe", "Horde")

    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")
    sel, selected = service.selected_characters(conn, ME, FOREVER)
    assert sel == Selection("Classic Beta PvE", "Horde")
    assert [c.name for c in selected] == ["Tailor Guy"]
    with pytest.raises(ValueError, match="Nowhere"):
        service.select(conn, ME, FOREVER, "Nowhere", "Horde")

    store.save_characters(conn, ME, FOREVER, chars("Frell"))  # the selected realm is gone from the file
    assert service.selection(conn, ME, FOREVER, chars("Frell")) == Selection("Dreamscythe", "Horde")


def current(conn: Connection) -> dict[int, int]:
    """The selected realm/faction's current prices."""
    return prices.load_current(conn, service.selected_auction_house(conn, ME, FOREVER))


def test_market_cache_reloads_only_after_invalidate(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {})
    cache = service.MarketCache(database, FOREVER)
    first = cache.get(ah)
    assert cache.get(ah) is first
    assert cache.get(None) is not first  # one market per auction house
    prices.set_price(conn, ah, 1, 5)
    assert cache.get(ah).prices == {}
    cache.invalidate()
    assert cache.get(ah).prices == {1: 5}
    assert len(cache.get(ah).recipes) == 1


def test_market_cache_sees_other_processes_changes_after_its_ttl(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    """Another instance (or an ingest job) changed prices or game data: the stamp check reloads."""
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    now = [0.0]
    cache = service.MarketCache(database, FOREVER, clock=lambda: now[0])
    first = cache.get(ah)
    prices.set_price(conn, ah, 1, 7)  # as another instance's upload would
    now[0] += service.STAMP_TTL / 2
    assert cache.get(ah) is first  # checked at most every STAMP_TTL seconds
    now[0] += service.STAMP_TTL
    assert cache.get(ah).prices == {1: 7}
    second = cache.get(ah)
    now[0] += service.STAMP_TTL * 2
    assert cache.get(ah) is second  # nothing changed: kept
    db.set_build(conn, FOREVER, "1.60.2.1")  # a game data update
    now[0] += service.STAMP_TTL * 2
    assert cache.get(ah) is not second


def test_market_cache_checks_at_once_for_a_newer_price_version(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    """The front end heard of new prices (a price signal): its request must not get the old market, even
    within STAMP_TTL of the last check."""
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    now = [0.0]
    cache = service.MarketCache(database, FOREVER, clock=lambda: now[0])
    first = cache.get(ah)
    known = prices.price_version(conn, ah)
    assert known is not None
    assert cache.get(ah, at_least=known) is first  # the version it has: no check
    prices.set_price(conn, ah, 1, 7)  # as another instance's upload would
    assert cache.get(ah) is first  # within the TTL
    assert cache.get(ah, at_least=known + 1).prices == {1: 7}


def test_market_cache_keeps_the_listings_with_its_market(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    now = db.utcnow()
    ah = scanned(conn, {1: [(20, 3)]}, now)
    cache = service.MarketCache(database, FOREVER)
    priced = cache.get_priced(ah)
    assert priced.market is cache.get(ah)  # the one rankings are cached on
    assert priced.listings == {1: prices.Listing(20, 3, (book.Level(20, 3, 1),))}
    later = now + timedelta(minutes=1)
    scanned(conn, {1: [(20, 7)]}, later)
    cache.invalidate()
    assert cache.get_priced(ah).listings == {1: prices.Listing(20, 7, (book.Level(20, 7, 1, age=1),))}
    assert cache.get_priced(None).listings == {}


def test_a_thin_market_is_an_ah_sale_resting_on_few_listed_units() -> None:
    recipe = engine.Recipe(1, "Green Robe", 3, output_count=1)
    tree = engine.Node(3, "Green Robe", 1, 100)
    sale = engine.Result(recipe, 100, 500, "ah", tree, crafts=1)
    assert service.thin_market(sale, {3: prices.Listing(900, 2)})
    assert not service.thin_market(sale, {3: prices.Listing(900, 50)})
    assert service.thin_market(
        replace(sale, crafts=60), {3: prices.Listing(900, 50)}
    )  # sells more than listed
    assert not service.thin_market(sale, {3: prices.Listing(900, None)})  # unknown
    assert not service.thin_market(sale, {})  # nobody lists it: no market to rest on
    assert not service.thin_market(replace(sale, best_exit="vendor"), {3: prices.Listing(900, 2)})


def test_a_sale_is_slow_when_what_is_listed_ahead_outlasts_two_days() -> None:
    recipe = engine.Recipe(1, "Green Robe", 3, output_count=1)
    sale = engine.Result(recipe, 100, 500, "ah", engine.Node(3, "Green Robe", 1, 100), crafts=10)
    ladder = (book.Level(800, 20, 2), book.Level(900, 30, 3), book.Level(2000, 500, 9))

    def listed(rate: float | None) -> dict[int, prices.Listing]:
        return {3: prices.Listing(800, 550, ladder, rate)}

    # 50 listed at or under 900 sell first, then the plan's 10: at 40 a day, a day and a half
    assert service.days_to_sell(sale, listed(40.0), 900) == 1.5
    assert not service.slow_to_sell(sale, listed(40.0), 900)
    assert service.days_to_sell(sale, listed(20.0), 900) == 3.0
    assert service.slow_to_sell(sale, listed(20.0), 900)
    assert service.days_to_sell(sale, listed(20.0), 799) == 0.5  # undercutting everyone
    # nothing known of its sales: the thin market rule
    assert service.days_to_sell(sale, listed(None), 900) is None
    assert not service.slow_to_sell(sale, listed(None), 900)
    assert service.slow_to_sell(sale, {3: prices.Listing(800, 2)}, 900)
    vendored = replace(sale, best_exit="vendor")
    assert service.days_to_sell(vendored, listed(1.0), 900) is None
    assert not service.slow_to_sell(vendored, listed(1.0), 900)


def test_selection_falls_back_to_the_freshest_scanned_realm(conn: Connection) -> None:
    assert service.selection(conn, ME, FOREVER, []) is None
    set_prices(conn, {1: 20}, realm="Dreamscythe", faction="Horde")
    set_prices(conn, {1: 30})  # Classic Beta PvE Horde, later
    set_prices(conn, {1: 40}, realm="", faction="")  # the unnamed auction house never counts
    assert service.selection(conn, ME, FOREVER, []) == Selection("Classic Beta PvE", "Horde")

    service.select(conn, ME, FOREVER, "Dreamscythe", "Horde")  # a realm with prices but no characters
    assert service.selected_characters(conn, ME, FOREVER) == (Selection("Dreamscythe", "Horde"), [])
    with pytest.raises(ValueError, match=r"Nowhere \(both factions\)"):
        service.select(conn, ME, FOREVER, "Nowhere", "")
    with pytest.raises(ValueError):
        service.select(conn, ME, FOREVER, "", "")


def test_an_import_forgets_a_selected_realm_it_has_no_characters_on(conn: Connection) -> None:
    set_prices(conn, {1: 20}, realm="Elsewhere")
    service.select(conn, ME, FOREVER, "Elsewhere", "Horde")
    service.replace_characters(conn, ME, FOREVER, chars())
    assert service.selected_characters(conn, ME, FOREVER)[0] == Selection("Dreamscythe", "Horde")

    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")
    service.replace_characters(conn, ME, FOREVER, chars())  # still there: kept
    assert service.selected_characters(conn, ME, FOREVER)[0] == Selection("Classic Beta PvE", "Horde")


def test_delete_characters(conn: Connection) -> None:
    service.replace_characters(conn, ME, FOREVER, chars())
    service.delete_character(conn, ME, FOREVER, "Classic Beta PvE", "Tailor Guy")
    assert "Tailor Guy" not in [c.name for c in store.load_characters(conn, ME, FOREVER)]
    with pytest.raises(FileNotFoundError):
        service.delete_character(conn, ME, FOREVER, "Classic Beta PvE", "Tailor Guy")


# --- profit per hour ----------------------------------------------------------------------------------
def test_time_model_follows_the_users_settings(conn: Connection, cities: Path) -> None:
    maps = store.load_cities(cities)
    assert [c.name for c in service.faction_cities(maps, "Horde")] == ["Orgrimmar", "Thunder Bluff"]
    assert [c.name for c in service.faction_cities(maps, "")] == ["Orgrimmar", "Stormwind", "Thunder Bluff"]
    model = service.time_model(conn, ME, FOREVER, maps, "Horde")
    assert (model.city.name, model.config) == ("Orgrimmar", timing.DEFAULT_CONFIG)  # the estimate's city
    assert [c.name for c in model.fastest] == ["Orgrimmar", "Thunder Bluff"]  # timed in whichever is fastest
    assert service.time_model(conn, ME, FOREVER, maps, "Alliance").city.name == "Stormwind"
    users.update_settings(conn, ME, FOREVER, time_city="Thunder Bluff", time_config='{"batch": 5}')
    model = service.time_model(conn, ME, FOREVER, maps, "Horde")
    assert (model.city.name, model.config.batch) == ("Thunder Bluff", 5)
    users.update_settings(conn, ME, FOREVER, time_city="Booty Bay")  # neutral: never used
    assert service.time_model(conn, ME, FOREVER, maps, "Horde").city.name == "Orgrimmar"
    with pytest.raises(ValueError, match="Booty Bay"):
        service.set_time(conn, ME, FOREVER, maps, "Booty Bay", {})
    users.update_settings(conn, ME, FOREVER, time_city="Stormwind")
    assert service.time_model(conn, ME, FOREVER, maps, "Horde").city.name == "Orgrimmar"  # not a Horde city
    assert service.time_model(conn, ME, FOREVER, {}, "Horde").city is timing.ANYWHERE  # no presets


def test_by_rate_puts_the_best_per_hour_first() -> None:
    fast = engine.Recipe(1, "Fast", 3, 1, ((1, 1),), "Tailoring")
    slow = engine.Recipe(2, "Slow", 4, 1, ((1, 1),), "Tailoring", cast_time_ms=60_000)
    items = {
        1: engine.Item(1, "Cloth"),
        3: engine.Item(3, "Fast Thing", sell_price=100),
        4: engine.Item(4, "Slow Thing", sell_price=200),
    }
    model = engine.TimeModel(timing.DEFAULT_CONFIG, timing.ANYWHERE)
    market = engine.Market(items, [fast, slow], {1: 10}, time=model)
    by_profit = service.search(market, [], "none", engine.Filters(), time=model)
    assert [r.recipe.name for r in by_profit] == ["Slow", "Fast"]
    assert [r.recipe.name for r in service.by_rate(by_profit)] == ["Fast", "Slow"]


def test_by_skill_puts_the_cheapest_skill_point_first() -> None:
    def recipe(i: int, name: str, low: int, high: int, cloth: int = 1) -> engine.Recipe:
        return engine.Recipe(
            i, name, 10 + i, 1, ((1, cloth),), "Tailoring", spell_id=i, trivial_low=low, trivial_high=high
        )

    recipes = [
        recipe(1, "Orange", 55, 70),  # +5, a sure skill point
        recipe(2, "Yellow", 50, 60),  # -7, a sure one: 7c a point
        recipe(3, "Green", 40, 60),  # -5 at half a chance: 10c a point
        recipe(4, "Grey", 20, 50),  # -1, but no skill point
        recipe(5, "Sure", 0, 0, cloth=2),  # -10, thresholds unknown: a sure point, as dear as Green's
    ]
    sells = {1: 15, 2: 3, 3: 5, 4: 9, 5: 10}
    items = {1: engine.Item(1, "Cloth")} | {
        10 + i: engine.Item(10 + i, r.name, sell_price=sells[i]) for i, r in enumerate(recipes, 1)
    }
    tailor = engine.Crafter("Tailor", (("Tailoring", 50, 75),), frozenset({1, 2, 3, 4, 5}))
    market = engine.Market(items, recipes, {1: 10}, crafters=[tailor], exits=frozenset({"vendor"}))
    ranked = market.rank(min_profit=-(10**18))
    assert [r.recipe.name for r in service.by_skill(ranked)] == ["Orange", "Yellow", "Sure", "Green", "Grey"]


def test_favorites_first_keeps_each_part_in_order() -> None:
    recipes = [engine.Recipe(i, f"R{i}", 10 + i, 1, ((1, 1),), "Tailoring") for i in range(1, 5)]
    items = {1: engine.Item(1, "Cloth")} | {
        10 + i: engine.Item(10 + i, f"T{i}", sell_price=100 * i) for i in range(1, 5)
    }
    ranked = service.search(engine.Market(items, recipes, {1: 10}), [], "none", engine.Filters())
    assert [r.recipe.id for r in ranked] == [4, 3, 2, 1]
    assert [r.recipe.id for r in service.favorites_first(ranked, frozenset({1, 3}))] == [3, 1, 4, 2]
    assert service.favorites_first(ranked, frozenset()) == ranked


# --- reputation: the city a plan pays best in -----------------------------------------------------------
ORGRIMMAR, THUNDER_BLUFF = 76, 81
HONORED_UP = {6: 10, 7: 10, 8: 10}
CLOTH, THREAD, ROBE_ITEM = 1, 2, 3
ROBE = engine.Recipe(10, "Robe", ROBE_ITEM, 1, ((CLOTH, 10), (THREAD, 1)), "Tailoring", spell_id=900)
WALK = timing.TimeConfig(run_speed=7.0, detour=1.0)  # 7 yd is a second


def rep_city(name: str, vendor_x: float, faction: int, anvil: bool = True) -> timing.CityMap:
    """A Horde city: the auction house, a mailbox 5 s away, an anvil there too, and `faction`'s thread
    seller `vendor_x` yards out."""
    places = [
        timing.Location("ah", "ah", "Auctioneer", 0, 0, 0),
        timing.Location("mailbox:1", "mailbox", "Mailbox", 35, 0, 0),
        timing.Location("vendor:1", "vendor", "Thread Seller", vendor_x, 0, 0),
    ]
    if anvil:
        places.append(timing.Location("anvil:1", "anvil", "Anvil", 35, 0, 0))
    return timing.CityMap(
        name,
        "Horde",
        places,
        "ah",
        {"vendor:1": frozenset({THREAD})},
        vendor_reputations={"vendor:1": faction},
    )


def tailor(*standings: tuple[int, int]) -> Character:
    tailoring = Profession("Tailoring", 300, 300, frozenset({900}))
    return Character("R", "Tailor", "Horde", "MAGE", 60, (tailoring,), reputations=standings)


def rep_base(thread: int, robe: int = 500, recipe: engine.Recipe = ROBE) -> engine.Market:
    """Cloth at 20c on the AH, thread at a vendor, the robe sold to a vendor."""
    items = {
        CLOTH: engine.Item(CLOTH, "Cloth", stack_size=20),
        THREAD: engine.Item(THREAD, "Thread", vendor_price=thread, stack_size=20),
        ROBE_ITEM: engine.Item(ROBE_ITEM, "Robe", sell_price=robe),
    }
    return engine.Market(items, [recipe], {CLOTH: 20}, reputation_discounts=HONORED_UP)


def best_plan(
    base: engine.Market, who: Character, near: timing.CityMap, far: timing.CityMap
) -> engine.Result:
    """The robe as the search ranks it for `who`, left to pick between the two cities."""
    model = engine.TimeModel(WALK, near, (near, far))
    (r,) = service.search(base, [who], "none", Filters(), time=model)
    return r


def test_cities_are_grouped_by_what_their_vendors_charge() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)

    def groups(*standings: tuple[int, int]) -> list[list[str]]:
        crafters = [engine.Crafter("Tailor", (), frozenset(), reputations=standings)]
        return [[c.name for c in g] for g in service.city_groups([org, tb], crafters, HONORED_UP)]

    assert groups() == [["Orgrimmar", "Thunder Bluff"]]
    assert groups((THUNDER_BLUFF, 5)) == [["Orgrimmar", "Thunder Bluff"]]  # Friendly: nothing off
    assert groups((THUNDER_BLUFF, 6)) == [["Orgrimmar"], ["Thunder Bluff"]]
    assert groups((THUNDER_BLUFF, 6), (ORGRIMMAR, 8)) == [["Orgrimmar", "Thunder Bluff"]]  # 10% in both
    assert service.city_groups([org, tb], [], HONORED_UP) == [(org, tb)]  # browsing: nobody's standing


def test_a_small_saving_is_not_worth_a_long_run() -> None:
    # Honored in Thunder Bluff, where the thread seller is 1000 s out: 10c off a thread doesn't pay for it.
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=100), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.cost, r.tree.inputs[1].rep_discount) == ("Orgrimmar", 10 * (200 + 100), 0)
    (other,) = r.alternatives  # the same session in Thunder Bluff: cheaper, and far slower
    assert other.timing is not None
    assert (other.timing.city, other.cost) == ("Thunder Bluff", 10 * (200 + 90))
    assert r.rate is not None and other.rate is not None and r.rate > other.rate


def test_the_cheaper_city_wins_when_it_pays_more_per_hour() -> None:
    # The robe barely profits at list price (10c a craft); 29c off the thread nearly quadruples that, for
    # ten seconds more of running.
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=290), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * (500 - 200 - 261))
    assert [a.profit for a in r.alternatives] == [10 * 10]


def test_a_plan_that_loses_everywhere_goes_where_it_loses_least() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=400), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * (500 - 200 - 360))  # -60 a craft, not -100


def test_a_plan_that_profits_in_one_city_only_goes_there() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=310), tailor((THUNDER_BLUFF, 6)), org, tb)  # -10 a craft, or +21
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * 21)


def test_a_city_without_the_plans_station_is_passed_over() -> None:
    forged = replace(ROBE, station="anvil")
    org = rep_city("Orgrimmar", 70, ORGRIMMAR)
    tb = rep_city("Thunder Bluff", 140, THUNDER_BLUFF, anvil=False)
    r = best_plan(rep_base(thread=290, recipe=forged), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.timing.missing) == ("Orgrimmar", frozenset())


def test_the_same_plan_everywhere_is_timed_in_the_quickest_city_lazily() -> None:
    # Thread is cheaper still on the AH: no vendor buy, so the cities differ in nothing but the running.
    org, tb = rep_city("Orgrimmar", 700, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)
    base = rep_base(thread=100)
    base.prices[THREAD] = 50
    r = best_plan(base, tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.alternatives == () and "timing" not in vars(r)  # nothing timed to rank it
    assert r.time_model is not None
    assert [c.name for c in r.time_model.fastest] == ["Orgrimmar", "Thunder Bluff"]
    assert r.timing is not None and r.timing.city == "Thunder Bluff"  # the robe sells at the nearer vendor


def test_a_recipe_the_cities_price_alike_is_planned_once(monkeypatch: pytest.MonkeyPatch) -> None:
    # The sash takes no thread: what it costs has nothing to do with whose vendor sells thread for less.
    sash = engine.Recipe(11, "Sash", 4, 1, ((CLOTH, 5),), "Tailoring", spell_id=901)
    base = rep_base(thread=290)
    base.items[4] = engine.Item(4, "Sash", sell_price=300)
    base.recipes.append(sash)
    who = replace(
        tailor((THUNDER_BLUFF, 6)), professions=(Profession("Tailoring", 300, 300, frozenset({900, 901})),)
    )
    org, tb = rep_city("Orgrimmar", 700, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)
    model = engine.TimeModel(WALK, org, (org, tb))
    planned: list[int] = []
    evaluate = engine.Market.evaluate

    def counted(
        self: engine.Market, recipe: engine.Recipe, *args: Any, **kwargs: Any
    ) -> engine.Result | None:
        planned.append(recipe.id)
        return evaluate(self, recipe, *args, **kwargs)

    monkeypatch.setattr(engine.Market, "evaluate", counted)
    by_id = {r.recipe.id: r for r in service.search(base, [who], "none", Filters(), time=model)}
    assert sorted(planned) == [10, 10, 11]  # the robe in both cities, the sash once
    got = by_id[11]
    assert got.alternatives == () and "timing" not in vars(got)
    assert got.time_model is not None and [c.name for c in got.time_model.fastest] == [
        "Orgrimmar",
        "Thunder Bluff",
    ]
    assert got.timing is not None and got.timing.city == "Thunder Bluff"  # the nearer vendor to sell it to
    assert by_id[10].timing is not None and by_id[10].timing.city == "Thunder Bluff"
    planned.clear()
    session = service.session_model(model, [org, tb], None)
    again = service.evaluate(base, [who], "none", ALL_EXITS, 11, {}, time=session, crafts=WALK.batch)
    assert again == got and planned == [11]
    assert again is not None and again.timing is not None and again.timing.city == "Thunder Bluff"


def test_without_standings_the_ranking_is_the_plain_one() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=290), tailor(), org, tb)
    assert r.time_model is not None and r.time_model.city is org
    assert (r.alternatives, "timing" in vars(r), r.profit) == ((), False, 100)


def test_evaluate_gives_the_ranked_result() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    base, who = rep_base(thread=290), tailor((THUNDER_BLUFF, 6))
    model = engine.TimeModel(WALK, org, (org, tb))
    (r,) = service.search(base, [who], "none", Filters(), time=model)
    session = service.session_model(model, [org, tb], None)
    got = service.evaluate(base, [who], "none", ALL_EXITS, ROBE.id, {}, time=session, crafts=WALK.batch)
    assert got is not None and got == r
    assert got.timing is not None and got.timing.city == "Thunder Bluff"
    assert [a.profit for a in got.alternatives] == [a.profit for a in r.alternatives]
    # asked for a city, it is planned and priced there alone
    there = service.session_model(model, [org, tb], "Orgrimmar")
    got = service.evaluate(base, [who], "none", ALL_EXITS, ROBE.id, {}, time=there, crafts=WALK.batch)
    assert got is not None and got.timing is not None
    assert (got.timing.city, got.profit, got.alternatives) == ("Orgrimmar", 100, ())


def test_a_saved_city_prices_the_plan_there() -> None:
    tb = rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    (r,) = service.search(
        rep_base(thread=290), [tailor((THUNDER_BLUFF, 6))], "none", Filters(), time=engine.TimeModel(WALK, tb)
    )
    assert (r.profit, r.alternatives) == (10 * 39, ())
