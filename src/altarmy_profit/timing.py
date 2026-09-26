"""Pure timing model: how long a crafting plan keeps a player busy, in a city whose layout is known.

No I/O, and no engine import (the engine imports this). A `TimeConfig` holds the seconds each action takes,
how many crafts a session makes (`batch`) and what an hour of play is worth; a `CityMap` holds where the
auction house, mailboxes, crafting stations and vendors stand (generated from vmangos by
scripts/build_cities.py, hand-tunable through its `overrides`). The engine turns a plan into one `Block`
per stretch a character is logged in; `time_blocks` routes each through the city and adds it all up.

A session is one batch: travel, character switches and AH searches are paid once per batch, the rest per
craft. Every character starts and ends at the city's hub (usually the auction house).
"""

from __future__ import annotations

import itertools
import json
import math
import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import asdict, dataclass, field, fields, replace
from typing import Any

PLACES = frozenset({"ah", "mailbox", "vendor"})  # location kinds besides crafting stations
# Crafting stations new in WoW: Forever (not in vmangos' vanilla world). Until we know how they work, they
# count as deployable: set down where the crafter stands, so always there and never a trip.
DEPLOYABLE = frozenset(
    {
        "anarchists_workbench",
        "arcane_forge",
        "crusaders_loom",
        "crusaders_tanning_rack",
        "fermenter",
        "iron_oven",
        "library",
        "loom",
        "master_forge",
        "molten_foundry",
        "radiant_forge",
        "sewing_machine",
        "spinning_wheel",
        "tanning_rack",
    }
)
_KIND = re.compile(r"[a-z0-9]+(?:_[a-z0-9]+)*")


def station_kind(name: str) -> str:
    """A crafting station's location kind from its SpellFocusObject name: "Cooking Fire" -> "cooking_fire",
    "Anarchist's Workbench" -> "anarchists_workbench"."""
    return "_".join(re.findall(r"[a-z0-9]+", name.lower().replace("'", "")))


FACTIONS = frozenset({"Horde", "Alliance", ""})  # "" for a neutral town
BREAKDOWN = ("travel", "switch", "ah", "vendor", "mail", "craft", "disenchant")
MAX_PERMUTED = 7  # stops per group tried in every order; beyond, nearest first


@dataclass(frozen=True)
class TimeConfig:
    """Seconds per action, the batch size, what an hour is worth and how fast the player runs."""

    ah_search: float = 8.0  # per distinct item searched on the AH, once per batch
    ah_buy: float = 4.0  # per stack bought on the AH
    ah_post: float = 6.0  # per stack posted on the AH
    vendor_buy: float = 2.0  # per stack bought from a vendor
    vendor_sell: float = 1.5  # per stack sold to a vendor
    mail_send: float = 8.0  # per mail sent (up to `mail_attachments` stacks each)
    mail_attach: float = 2.0  # per stack attached
    mail_open: float = 3.0  # per mail taken from the mailbox
    mail_attachments: int = 12  # stacks per mail
    switch_character: float = 45.0  # logging out and in as another character
    disenchant: float = 3.5  # per item: the cast and the loot
    craft_overhead: float = 0.5  # per craft on top of its cast time
    batch: int = 20  # crafts per session: travel and switches are shared by them
    time_value: int = 0  # copper an hour of play is worth; 0: time only reports, it never picks a plan
    run_speed: float = 7.0  # yards per second (7 on foot, 14 on a 100% mount)
    detour: float = 1.3  # walking distance over straight-line distance


DEFAULT_CONFIG = TimeConfig()
_INT_FIELDS = frozenset({"mail_attachments", "batch", "time_value"})
_AT_LEAST_ONE = frozenset({"mail_attachments", "batch", "detour"})
_POSITIVE = frozenset({"run_speed"})
_FIELDS = {f.name for f in fields(TimeConfig)}


def _config_value(name: str, value: object) -> float | int:
    """`value` checked for field `name`; ValueError if it is unknown, not a number or out of range."""
    if name not in _FIELDS:
        raise ValueError(f"unknown time setting {name!r}")
    if isinstance(value, bool) or not isinstance(value, int | float) or not math.isfinite(value):
        raise ValueError(f"{name} must be a number")
    if name in _INT_FIELDS:
        if value != int(value):
            raise ValueError(f"{name} must be a whole number")
        out: float | int = int(value)
    else:
        out = float(value)
    if out < 0 or (name in _AT_LEAST_ONE and out < 1) or (name in _POSITIVE and out <= 0):
        raise ValueError(f"{name} is out of range: {value}")
    return out


def config_from_dict(data: Mapping[str, object], base: TimeConfig = DEFAULT_CONFIG) -> TimeConfig:
    """`base` with `data`'s settings; ValueError on an unknown setting or a bad value."""
    changes: dict[str, Any] = {k: _config_value(k, v) for k, v in data.items()}
    return replace(base, **changes)


def config_from_json(text: str | None) -> TimeConfig:
    """A stored config: every valid setting in the JSON object applied to the defaults, the rest ignored."""
    try:
        data = json.loads(text) if text else {}
    except ValueError:
        return DEFAULT_CONFIG
    if not isinstance(data, dict):
        return DEFAULT_CONFIG
    good: dict[str, Any] = {}
    for k, v in data.items():
        try:
            good[k] = _config_value(k, v)
        except ValueError:
            continue
    return replace(DEFAULT_CONFIG, **good)


def config_changes(config: TimeConfig) -> dict[str, float | int]:
    """The settings that differ from the defaults: what is stored."""
    default = asdict(DEFAULT_CONFIG)
    return {k: v for k, v in asdict(config).items() if v != default[k]}


# --- city maps ------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Location:
    id: str  # "ah", "mailbox:<guid>", "anvil:<guid>", "vendor:<npc entry>", ...
    kind: str  # ah | mailbox | vendor, or a crafting station (`station_kind`: anvil, spinning_wheel, ...)
    name: str
    x: float
    y: float
    z: float


def _str(data: Mapping[str, Any], key: str, default: str | None = None) -> str:
    value = data.get(key, default)
    if not isinstance(value, str):
        raise ValueError(f"{key} must be a string")
    return value


def _num(data: Mapping[str, Any], key: str) -> float:
    value = data.get(key)
    if isinstance(value, bool) or not isinstance(value, int | float) or not math.isfinite(value):
        raise ValueError(f"{key} must be a number")
    return float(value)


def _mapping(value: object, what: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{what} must be an object")
    return value


def _list(value: object, what: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{what} must be a list")
    return value


def _location(data: object) -> Location:
    d = _mapping(data, "a location")
    kind = _str(d, "kind")
    if not _KIND.fullmatch(kind):
        raise ValueError(f"bad location kind {kind!r}: ah, mailbox, vendor or a station such as anvil")
    return Location(_str(d, "id"), kind, _str(d, "name", ""), _num(d, "x"), _num(d, "y"), _num(d, "z"))


def _pair(a: str, b: str) -> tuple[str, str]:
    return (a, b) if a <= b else (b, a)


class CityMap:
    """Where things stand in one city, and how long it takes to run between them. Immutable once built,
    so one instance serves every request; distances are kept in yards, so every user's run speed and
    detour apply to the same map."""

    def __init__(
        self,
        name: str,
        faction: str,
        locations: Iterable[Location],
        hub: str,
        vendor_items: Mapping[str, frozenset[int]],
        *,
        map_id: int = 0,
        detour: float | None = None,
        travel: Mapping[tuple[str, str], float] | None = None,
    ) -> None:
        if faction not in FACTIONS:
            raise ValueError(f"unknown faction {faction!r}")
        self.name = name
        self.faction = faction
        self.map_id = map_id
        self.locations: tuple[Location, ...] = tuple(locations)
        self._by_id = {loc.id: loc for loc in self.locations}
        if hub not in self._by_id:
            raise ValueError(f"{name}: the hub {hub!r} is not one of its locations")
        self.hub = self._by_id[hub]
        for loc_id in vendor_items:
            if loc_id not in self._by_id:
                raise ValueError(f"{name}: vendor {loc_id!r} is not one of its locations")
        self.vendor_items = dict(vendor_items)
        self.detour = detour  # the city's own detour factor (e.g. Undercity's levels); None: the config's
        self._travel = {_pair(a, b): s for (a, b), s in (travel or {}).items()}  # hand-measured seconds
        self._sellers: dict[int, list[str]] = {}
        for loc_id, items in sorted(self.vendor_items.items()):
            for i in items:
                self._sellers.setdefault(i, []).append(loc_id)
        self._trips: dict[tuple[str, TimeConfig], float] = {}  # memo for `trip`: pure, safe to share
        self._nearest: dict[tuple[str, str, TimeConfig], Location | None] = {}  # memo for `nearest`

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> CityMap:
        """A map from its JSON form (see scripts/build_cities.py), with its `overrides` applied: `detour`,
        `hub`, `drop` (location ids), `locations` (added, or replacing one with the same id) and `travel`
        ({"a|b": seconds}). ValueError if it is malformed."""
        overrides = _mapping(data.get("overrides") or {}, "overrides")
        dropped = {str(i) for i in _list(overrides.get("drop", []), "drop")}
        locs = {loc.id: loc for loc in map(_location, _list(data.get("locations"), "locations"))}
        locs.update(
            (loc.id, loc) for loc in map(_location, _list(overrides.get("locations", []), "locations"))
        )
        for loc_id in dropped:
            locs.pop(loc_id, None)
        vendors = {
            str(loc_id): frozenset(int(i) for i in _list(items, "vendor items"))
            for loc_id, items in _mapping(data.get("vendors") or {}, "vendors").items()
            if loc_id not in dropped
        }
        travel: dict[tuple[str, str], float] = {}
        for key, seconds in _mapping(overrides.get("travel") or {}, "travel").items():
            a, sep, b = str(key).partition("|")
            if not sep or not a or not b:
                raise ValueError(f"travel override {key!r} must name two locations as 'a|b'")
            travel[a, b] = _num({"seconds": seconds}, "seconds")
        detour = _num(overrides, "detour") if "detour" in overrides else None
        hub = _str(overrides, "hub") if "hub" in overrides else _str(data, "hub", "ah")
        return cls(
            _str(data, "name"),
            _str(data, "faction", ""),
            locs.values(),
            hub,
            vendors,
            map_id=int(_num(data, "map")) if "map" in data else 0,
            detour=detour,
            travel=travel,
        )

    def location(self, loc_id: str) -> Location:
        return self._by_id[loc_id]

    def seconds(self, a: str, b: str, config: TimeConfig) -> float:
        """Running time between two locations: a hand-measured time if there is one, else straight-line
        distance times the detour factor over the run speed."""
        if a == b:
            return 0.0
        measured = self._travel.get(_pair(a, b))
        if measured is not None:
            return measured
        p, q = self._by_id[a], self._by_id[b]
        yards = math.dist((p.x, p.y, p.z), (q.x, q.y, q.z))
        return yards * (self.detour if self.detour is not None else config.detour) / config.run_speed

    def nearest(self, kind: str, from_id: str, config: TimeConfig) -> Location | None:
        """The location of `kind` quickest to reach from `from_id`; None if the city has none."""
        key = (kind, from_id, config)
        if key not in self._nearest:
            found = [loc for loc in self.locations if loc.kind == kind]
            self._nearest[key] = min(
                found, key=lambda loc: (self.seconds(from_id, loc.id, config), loc.id), default=None
            )
        return self._nearest[key]

    def vendor_for(self, item_id: int, from_id: str, config: TimeConfig) -> Location | None:
        """The vendor selling `item_id` quickest to reach from `from_id`; None if nobody here sells it."""
        sellers = self._sellers.get(item_id, [])
        best = min(sellers, key=lambda v: (self.seconds(from_id, v, config), v), default=None)
        return None if best is None else self._by_id[best]

    def _resolve(self, target: str, from_id: str, config: TimeConfig) -> Location | None:
        """A location id, or a kind (the nearest one from `from_id`)."""
        if target in self._by_id:
            return self._by_id[target]
        return self.nearest(target, from_id, config)

    def trip(self, target: str, config: TimeConfig) -> float:
        """Seconds from the hub to `target` (a location id or kind, the nearest one) and back; 0 if the
        city has no such place."""
        if target in DEPLOYABLE:
            return 0.0
        key = (target, config)
        got = self._trips.get(key)
        if got is None:
            loc = self._resolve(target, self.hub.id, config)
            got = 0.0 if loc is None else 2 * self.seconds(self.hub.id, loc.id, config)
            self._trips[key] = got
        return got


# Where plans are timed when a game version has no city presets: everything at one spot, so only the
# actions and character switches take time.
ANYWHERE = CityMap("Anywhere", "", [Location("ah", "ah", "Auction house", 0.0, 0.0, 0.0)], "ah", {})


# --- routes ---------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Block:
    """One stretch a character is logged in: where they must go and what they do there. They gather
    (mail, AH and vendor buys, any order), craft at `stations` (in order), then dispose (mail, AH, vendor,
    any order), and go back to the hub. `fixed` and `per_craft` hold their action seconds by
    `BREAKDOWN` kind, once per batch and per craft."""

    who: str
    receives_mail: bool = False
    buys_ah: bool = False
    vendor_items: frozenset[int] = frozenset()  # items bought from vendors
    stations: tuple[str, ...] = ()  # station kinds crafted at (see `station_kind`)
    sends_mail: bool = False
    sells_ah: bool = False
    sells_vendor: bool = False
    fixed: Mapping[str, float] = field(default_factory=dict)
    per_craft: Mapping[str, float] = field(default_factory=dict)


@dataclass(frozen=True)
class Leg:
    who: str
    from_id: str
    to_id: str
    seconds: float


def _vendors_for(
    city: CityMap, items: frozenset[int], config: TimeConfig
) -> tuple[list[str], frozenset[int]]:
    """Vendors covering `items` (greedy: the item with the fewest sellers first, reusing a chosen vendor
    when it sells the item, else the nearest to the hub) and the items no vendor here sells."""
    chosen: list[str] = []
    unsold = set()
    by_choice = sorted(items, key=lambda i: (len(city._sellers.get(i, [])), i))
    for item in by_choice:
        sellers = city._sellers.get(item, [])
        if not sellers:
            unsold.add(item)
        elif not any(v in chosen for v in sellers):
            loc = city.vendor_for(item, city.hub.id, config)
            assert loc is not None
            chosen.append(loc.id)
    if unsold:  # timed at the nearest vendor of any kind
        nearest = city.nearest("vendor", city.hub.id, config)
        if nearest is not None and nearest.id not in chosen:
            chosen.append(nearest.id)
    return chosen, frozenset(unsold)


def _walk(
    city: CityMap, start: str, order: Sequence[str], end: str | None, config: TimeConfig
) -> tuple[float, list[str]]:
    """From `start` through `order` (ids, or kinds: the nearest one from where the player then is) to
    `end` (None: stop at the last). Returns (seconds, the ids visited); a kind the city lacks is skipped."""
    at, total, ids = start, 0.0, []
    for target in order:
        loc = city._resolve(target, at, config)
        if loc is None:
            continue
        total += city.seconds(at, loc.id, config)
        at = loc.id
        ids.append(at)
    if end is not None:
        total += city.seconds(at, end, config)
    return total, ids


def _orders(city: CityMap, start: str, stops: Sequence[str], config: TimeConfig) -> list[tuple[str, ...]]:
    """The orders worth trying: every one for a few stops, else nearest first."""
    if len(stops) <= MAX_PERMUTED:
        return list(itertools.permutations(stops))
    left, order, at = list(stops), [], start
    while left:
        nxt = min(left, key=lambda t: _reach(city, at, t, config))
        left.remove(nxt)
        order.append(nxt)
        loc = city._resolve(nxt, at, config)
        at = loc.id if loc is not None else at
    return [tuple(order)]


def _reach(city: CityMap, at: str, target: str, config: TimeConfig) -> float:
    loc = city._resolve(target, at, config)
    return math.inf if loc is None else city.seconds(at, loc.id, config)


def _stops(city: CityMap, block: Block, config: TimeConfig) -> tuple[list[str], list[str], frozenset[int]]:
    """The block's gather and dispose stops (ids or kinds) and the vendor items nobody here sells."""
    vendors, unsold = _vendors_for(city, block.vendor_items, config)
    gather = (["mailbox"] if block.receives_mail else []) + (["ah"] if block.buys_ah else []) + vendors
    dispose = (
        (["mailbox"] if block.sends_mail else [])
        + (["ah"] if block.sells_ah else [])
        + (["vendor"] if block.sells_vendor else [])
    )
    return gather, dispose, unsold


def route(city: CityMap, block: Block, config: TimeConfig) -> list[Leg]:
    """The block's legs: from the hub through its gather stops (in the quickest order), its stations (in
    turn, the nearest each time), its dispose stops (quickest order) and back to the hub. Legs of no
    length are left out."""
    gather, dispose, _ = _stops(city, block, config)
    hub = city.hub.id
    tails: dict[str, tuple[float, list[str]]] = {}  # the quickest rest of the route from each place

    def tail(at: str) -> tuple[float, list[str]]:
        if at not in tails:
            placed = [k for k in block.stations if k not in DEPLOYABLE]
            station_s, stations = _walk(city, at, placed, None, config)
            after = stations[-1] if stations else at
            dispose_s, disposed = min(
                (_walk(city, after, o, hub, config) for o in _orders(city, after, dispose, config)),
                key=lambda w: w[0],
            )
            tails[at] = (station_s + dispose_s, stations + disposed)
        return tails[at]

    best: tuple[float, list[str]] | None = None
    for order in _orders(city, hub, gather, config):
        head_s, head = _walk(city, hub, order, None, config)
        tail_s, rest = tail(head[-1] if head else hub)
        if best is None or head_s + tail_s < best[0]:
            best = (head_s + tail_s, head + rest)
    assert best is not None
    legs, at = [], hub
    for stop in [*best[1], hub]:
        if stop != at:
            legs.append(Leg(block.who, at, stop, city.seconds(at, stop, config)))
        at = stop
    return legs


# --- timings --------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Timing:
    """How long a batch of one recipe takes in a city."""

    city: str
    batch: int
    fixed_seconds: float  # once per batch: travel, switches, AH searches
    per_craft_seconds: float  # every craft: casts, buys, posts, mail
    breakdown: Mapping[str, float]  # the whole batch's seconds by BREAKDOWN kind
    legs: tuple[Leg, ...]
    unsold: frozenset[int] = frozenset()  # vendor items no vendor in the city sells (timed at the nearest)
    missing: frozenset[str] = frozenset()  # station kinds the plan needs and the city lacks (not timed)
    deployed: frozenset[str] = frozenset()  # DEPLOYABLE stations the plan needs: there, and no trip

    @property
    def total_seconds(self) -> float:
        return self.fixed_seconds + self.batch * self.per_craft_seconds

    def per_hour(self, profit: int) -> int:
        """Copper per hour of play from `profit` per craft; 0 if the plan takes no time."""
        total = self.total_seconds
        return round(profit * self.batch * 3600 / total) if total > 0 else 0


def time_blocks(blocks: Sequence[Block], config: TimeConfig, city: CityMap) -> Timing:
    """The batch's timing: each block routed through the city, a switch between blocks, and their
    actions."""
    fixed = dict.fromkeys(BREAKDOWN, 0.0)
    per_craft = dict.fromkeys(BREAKDOWN, 0.0)
    legs: list[Leg] = []
    unsold: set[int] = set()
    missing: set[str] = set()
    deployed: set[str] = set()
    for i, block in enumerate(blocks):
        if i:
            fixed["switch"] += config.switch_character
        block_legs = route(city, block, config)
        legs.extend(block_legs)
        fixed["travel"] += sum(leg.seconds for leg in block_legs)
        unsold |= _stops(city, block, config)[2]
        deployed.update(k for k in block.stations if k in DEPLOYABLE)
        missing.update(
            k for k in block.stations if k not in DEPLOYABLE and city.nearest(k, city.hub.id, config) is None
        )
        for kind, seconds in block.fixed.items():
            fixed[kind] = fixed.get(kind, 0.0) + seconds
        for kind, seconds in block.per_craft.items():
            per_craft[kind] = per_craft.get(kind, 0.0) + seconds
    breakdown = {k: fixed[k] + config.batch * per_craft[k] for k in fixed}
    return Timing(
        city.name,
        config.batch,
        sum(fixed.values()),
        sum(per_craft.values()),
        breakdown,
        tuple(legs),
        frozenset(unsold),
        frozenset(missing),
        frozenset(deployed),
    )
