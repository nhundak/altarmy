import os
from dataclasses import replace
from datetime import timedelta
from pathlib import Path

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
