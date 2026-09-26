"""The pure timing model: config parsing, city maps, routes and batch timings."""

import json
from typing import Any

import pytest

from altarmy_profit import timing
from altarmy_profit.timing import DEFAULT_CONFIG, Block, CityMap, TimeConfig

# Distances in yards; with run speed 10 and detour 1 a yard is 0.1 s.
FAST = TimeConfig(run_speed=10.0, detour=1.0)


def city_data(**overrides: Any) -> dict[str, Any]:
    """A line of places along x: hub/AH at 0, mailbox at 50, anvil at 100, far mailbox at 900, vendors at
    200 (sells 1 and 2) and 300 (sells 2 and 3)."""
    return {
        "name": "Testville",
        "faction": "Horde",
        "map": 1,
        "hub": "ah",
        "locations": [
            {"id": "ah", "kind": "ah", "name": "Auctioneer", "x": 0, "y": 0, "z": 0},
            {"id": "mailbox:1", "kind": "mailbox", "name": "Mailbox", "x": 50, "y": 0, "z": 0},
            {"id": "mailbox:2", "kind": "mailbox", "name": "Far Mailbox", "x": 900, "y": 0, "z": 0},
            {"id": "anvil:1", "kind": "anvil", "name": "Anvil", "x": 100, "y": 0, "z": 0},
            {"id": "vendor:1", "kind": "vendor", "name": "Near Vendor", "x": 200, "y": 0, "z": 0},
            {"id": "vendor:2", "kind": "vendor", "name": "Far Vendor", "x": 300, "y": 0, "z": 0},
        ],
        "vendors": {"vendor:1": [1, 2], "vendor:2": [2, 3]},
        "overrides": overrides,
    }


def city(**overrides: Any) -> CityMap:
    return CityMap.from_dict(city_data(**overrides))


# --- config ---------------------------------------------------------------------------------------------
def test_config_round_trips_through_json() -> None:
    cfg = TimeConfig(batch=5, time_value=1_000_000, switch_character=30.0)
    assert timing.config_from_json(json.dumps(timing.config_changes(cfg))) == cfg
    assert timing.config_changes(cfg) == {"batch": 5, "time_value": 1_000_000, "switch_character": 30.0}


def test_config_from_json_keeps_what_it_can() -> None:
    assert timing.config_from_json(None) == DEFAULT_CONFIG
    assert timing.config_from_json("not json") == DEFAULT_CONFIG
    assert timing.config_from_json("[1, 2]") == DEFAULT_CONFIG
    got = timing.config_from_json(json.dumps({"batch": 0, "ah_buy": -1, "mail_send": 3, "nope": 1}))
    assert got == TimeConfig(mail_send=3.0)  # the bad values and the unknown key are dropped


@pytest.mark.parametrize(
    "data",
    [
        {"nope": 1},
        {"batch": 0},
        {"ah_buy": -1},
        {"run_speed": 0},
        {"batch": "x"},
        {"batch": 1.5},
        {"batch": True},
        {"ah_buy": float("inf")},
    ],
)
def test_config_from_dict_rejects_bad_values(data: dict[str, object]) -> None:
    with pytest.raises(ValueError):
        timing.config_from_dict(data)


def test_config_from_dict_takes_ints_for_float_fields() -> None:
    assert timing.config_from_dict({"ah_buy": 3, "batch": 4}) == TimeConfig(ah_buy=3.0, batch=4)


# --- city maps ------------------------------------------------------------------------------------------
def test_seconds_are_distance_over_speed_times_detour_and_symmetric() -> None:
    c = city()
    assert c.seconds("ah", "anvil:1", FAST) == pytest.approx(10.0)
    assert c.seconds("anvil:1", "ah", FAST) == pytest.approx(10.0)
    assert c.seconds("ah", "anvil:1", TimeConfig(run_speed=10.0, detour=2.0)) == pytest.approx(20.0)
    assert c.seconds("ah", "ah", FAST) == 0.0


def test_overrides_win() -> None:
    c = city(travel={"anvil:1|ah": 3.5}, detour=2.0, hub="mailbox:1", drop=["mailbox:2"])
    assert c.seconds("ah", "anvil:1", FAST) == 3.5  # either order of the pair
    assert c.seconds("mailbox:1", "anvil:1", FAST) == pytest.approx(10.0)  # the city's detour: 50 yd x 2
    assert c.hub.id == "mailbox:1"
    assert "mailbox:2" not in {loc.id for loc in c.locations}


def test_override_locations_add_or_replace() -> None:
    extra = {"id": "forge:1", "kind": "forge", "name": "Forge", "x": 10, "y": 0, "z": 0}
    moved = {"id": "anvil:1", "kind": "anvil", "name": "Anvil", "x": 20, "y": 0, "z": 0}
    c = city(locations=[extra, moved])
    assert c.nearest("forge", "ah", FAST) is not None
    assert c.seconds("ah", "anvil:1", FAST) == pytest.approx(2.0)


def test_station_kinds_are_slugs_of_their_names() -> None:
    assert timing.station_kind("Cooking Fire") == "cooking_fire"
    assert timing.station_kind("Anarchist's Workbench") == "anarchists_workbench"
    assert timing.station_kind("Anvil") == "anvil"


def test_any_station_kind_can_be_placed() -> None:
    loom = {"id": "loom:1", "kind": "loom", "name": "Loom", "x": 5, "y": 0, "z": 0}
    found = city(locations=[loom]).nearest("loom", "ah", FAST)
    assert found is not None and found.name == "Loom"


@pytest.mark.parametrize(
    "bad",
    [
        {"name": "X"},  # no locations
        {
            **city_data(),
            "locations": [{"id": "ah", "kind": "Auction House", "name": "", "x": 0, "y": 0, "z": 0}],
        },
        {**city_data(), "hub": "nowhere"},
        {**city_data(), "locations": [{"id": "ah", "kind": "ah"}]},  # no coordinates
        {**city_data(), "vendors": {"vendor:9": [1]}},  # not a location
        {**city_data(), "overrides": {"travel": {"ah": 1}}},  # not a pair
        {**city_data(), "faction": "Pirates"},
    ],
)
def test_bad_maps_raise_value_error(bad: dict[str, Any]) -> None:
    with pytest.raises(ValueError):
        CityMap.from_dict(bad)


def test_nearest_and_vendor_for() -> None:
    c = city()
    near = c.nearest("mailbox", "ah", FAST)
    assert near is not None and near.id == "mailbox:1"
    far = c.nearest("mailbox", "vendor:2", FAST)  # 250 yd back vs 600 on: still the near one
    assert far is not None and far.id == "mailbox:1"
    assert c.nearest("forge", "ah", FAST) is None
    v2 = c.vendor_for(2, "ah", FAST)
    assert v2 is not None and v2.id == "vendor:1"
    v3 = c.vendor_for(3, "ah", FAST)
    assert v3 is not None and v3.id == "vendor:2"
    assert c.vendor_for(99, "ah", FAST) is None


def test_trip_goes_there_and_back_from_the_hub() -> None:
    c = city()
    assert c.trip("anvil", FAST) == pytest.approx(20.0)
    assert c.trip("vendor:2", FAST) == pytest.approx(60.0)
    assert c.trip("forge", FAST) == 0.0  # none here


# --- routes ---------------------------------------------------------------------------------------------
def test_route_visits_everything_in_the_best_order() -> None:
    c = city()
    block = Block("Smith", receives_mail=True, buys_ah=True, vendor_items=frozenset({1}), stations=("anvil",))
    legs = timing.route(c, block, FAST)
    stops = [leg.to_id for leg in legs]
    # gather (mailbox, AH, vendor 1) in the cheapest order from the hub, then the anvil, then home
    assert set(stops[:-2]) == {"mailbox:1", "vendor:1"}  # the hub is the AH: no leg to it
    assert stops[-2:] == ["anvil:1", "ah"]
    assert sum(leg.seconds for leg in legs) == pytest.approx(40.0)  # out to 200 yd and back
    assert all(leg.who == "Smith" for leg in legs)


def test_route_covers_vendor_items_with_few_vendors() -> None:
    c = city()
    block = Block("A", vendor_items=frozenset({2, 3}))
    assert [leg.to_id for leg in timing.route(c, block, FAST)] == ["vendor:2", "ah"]  # one vendor sells both


def test_route_disposes_after_crafting() -> None:
    c = city()
    block = Block("A", buys_ah=True, stations=("anvil",), sends_mail=True, sells_ah=True)
    stops = [leg.to_id for leg in timing.route(c, block, FAST)]
    assert stops == ["anvil:1", "mailbox:1", "ah"]  # AH buy at the hub, craft, mail, sell back at the AH


def test_route_with_many_stops_visits_each_once() -> None:
    locs = [
        {"id": f"vendor:{i}", "kind": "vendor", "name": f"V{i}", "x": i * 10, "y": i % 3, "z": 0}
        for i in range(1, 10)
    ]
    data = {**city_data(), "locations": city_data()["locations"][:1] + locs}
    data["vendors"] = {f"vendor:{i}": [i] for i in range(1, 10)}
    c = CityMap.from_dict(data)
    stops = [leg.to_id for leg in timing.route(c, Block("A", vendor_items=frozenset(range(1, 10))), FAST)]
    assert sorted(stops[:-1]) == sorted(f"vendor:{i}" for i in range(1, 10))
    assert stops[-1] == "ah"


def test_route_notes_items_no_vendor_here_sells() -> None:
    t = timing.time_blocks([Block("A", vendor_items=frozenset({1, 99}))], FAST, city())
    assert t.unsold == frozenset({99})


def test_new_forever_stations_are_deployed_where_the_crafter_stands() -> None:
    loom = {"id": "loom:1", "kind": "loom", "name": "Loom", "x": 500, "y": 0, "z": 0}
    c = city(locations=[loom])  # even a placed one is never walked to
    t = timing.time_blocks([Block("A", stations=("spinning_wheel", "loom", "anvil"))], FAST, c)
    assert (t.missing, t.deployed) == (frozenset(), frozenset({"spinning_wheel", "loom"}))
    assert [leg.to_id for leg in t.legs] == ["anvil:1", "ah"]
    assert c.trip("spinning_wheel", FAST) == c.trip("loom", FAST) == 0.0


def test_timing_notes_stations_the_city_lacks() -> None:
    t = timing.time_blocks([Block("A", stations=("anvil", "forge"))], FAST, city())
    assert t.missing == frozenset({"forge"})
    assert [leg.to_id for leg in t.legs] == ["anvil:1", "ah"]  # the forge is skipped, not timed


# --- timings --------------------------------------------------------------------------------------------
def test_time_blocks_sums_travel_switches_and_actions() -> None:
    cfg = TimeConfig(run_speed=10.0, detour=1.0, switch_character=30.0, batch=10)
    a = Block("A", stations=("anvil",), sends_mail=True, fixed={"ah": 8.0}, per_craft={"craft": 3.0})
    b = Block("B", receives_mail=True, sells_ah=True, per_craft={"mail": 1.0, "ah": 2.0})
    t = timing.time_blocks([a, b], cfg, city())
    assert t.breakdown["switch"] == 30.0
    assert t.breakdown["travel"] == pytest.approx(20.0 + 10.0)  # A: anvil and back by the mailbox; B: mailbox
    assert t.breakdown["craft"] == pytest.approx(30.0)
    assert t.breakdown["ah"] == pytest.approx(8.0 + 20.0)
    assert t.fixed_seconds == pytest.approx(30.0 + 30.0 + 8.0)
    assert t.per_craft_seconds == pytest.approx(6.0)
    assert t.total_seconds == pytest.approx(sum(t.breakdown.values()))
    assert t.total_seconds == pytest.approx(t.fixed_seconds + 10 * t.per_craft_seconds)


def test_per_hour() -> None:
    t = timing.time_blocks([Block("A", per_craft={"craft": 36.0})], TimeConfig(batch=10), city())
    assert t.total_seconds == pytest.approx(360.0)
    assert t.per_hour(1000) == 100_000  # 10 crafts x 1000c in 6 minutes
    empty = timing.time_blocks([], TimeConfig(), city())
    assert empty.total_seconds == 0.0 and empty.per_hour(1000) == 0
