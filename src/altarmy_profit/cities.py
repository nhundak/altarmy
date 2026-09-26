"""Build a city preset (`timing.CityMap`'s JSON) from the spawns around a city. Pure: scripts/build_cities.py
reads the spawns from vmangos (`vmangos.npcs_near`, ...) and writes data/<version>/cities/<name>.json.

A preset lists the auction house (the auctioneer nearest the middle of them all, which is also the hub every
character starts from), every mailbox, every crafting station DB2 names (anvils, forges, cooking fires,
...; stations new in WoW: Forever are not in vmangos and go in by hand), and every vendor selling something
without limit, with what they sell. Its `overrides` are hand-tuned (see `timing.CityMap.from_dict`) and kept
when the preset is regenerated.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .timing import station_kind
from .vmangos import Spawn


@dataclass(frozen=True)
class CitySpec:
    name: str  # the preset's name, as the app shows it
    tele: str  # vmangos' game_tele point the city is found around
    faction: str  # Horde | Alliance | "" (neutral)
    radius: float  # yards around the tele point that count as the city


CITY_SPECS: tuple[CitySpec, ...] = (
    CitySpec("Orgrimmar", "Orgrimmar", "Horde", 750),  # the Valley of Honor's anvils are ~660 yd out
    CitySpec("Undercity", "Undercity", "Horde", 250),
    CitySpec("Thunder Bluff", "ThunderBluff", "Horde", 450),
    CitySpec("Stormwind", "Stormwind", "Alliance", 650),
    CitySpec("Ironforge", "Ironforge", "Alliance", 350),
    CitySpec("Darnassus", "Darnassus", "Alliance", 550),
    CitySpec("Booty Bay", "BootyBay", "", 200),
    CitySpec("Gadgetzan", "Gadgetzan", "", 200),
    CitySpec("Everlook", "Everlook", "", 150),
)


def _location(loc_id: str, kind: str, s: Spawn) -> dict[str, Any]:
    return {
        "id": loc_id,
        "kind": kind,
        "name": s.name,
        "x": round(s.x, 2),
        "y": round(s.y, 2),
        "z": round(s.z, 2),
    }


def _central(spawns: Sequence[Spawn]) -> Spawn:
    """The spawn nearest the middle of them all."""
    mx = sum(s.x for s in spawns) / len(spawns)
    my = sum(s.y for s in spawns) / len(spawns)
    mz = sum(s.z for s in spawns) / len(spawns)
    return min(spawns, key=lambda s: ((s.x - mx) ** 2 + (s.y - my) ** 2 + (s.z - mz) ** 2, s.guid))


def build_city(
    spec: CitySpec,
    map_id: int,
    auctioneers: Sequence[Spawn],
    mailboxes: Sequence[Spawn],
    stations: Sequence[Spawn],
    vendors: Sequence[Spawn],
    stock: Mapping[int, Sequence[int]],
    focus_names: Mapping[int, str],
    existing: Mapping[str, Any] | None = None,
    source: str = "vmangos",
) -> dict[str, Any]:
    """The preset for `spec`: its locations and vendors' stock, with `existing`'s overrides kept.
    `stations` are spell focus objects, kept if `focus_names` (DB2's SpellFocusObject) names their focus.
    ValueError if the city has no auctioneer and no mailbox (nowhere to start from)."""
    locations: list[dict[str, Any]] = []
    hub = ""
    if auctioneers:
        locations.append(_location("ah", "ah", _central(auctioneers)))
        hub = "ah"
    for m in mailboxes:
        locations.append(_location(f"mailbox:{m.guid}", "mailbox", m))
    if not hub:
        if not mailboxes:
            raise ValueError(f"{spec.name}: no auctioneer or mailbox within {spec.radius} yd")
        hub = f"mailbox:{mailboxes[0].guid}"
    kept = [(station_kind(focus_names[s.data0]), s) for s in stations if s.data0 in focus_names]
    for kind, s in kept:
        locations.append(_location(f"{kind}:{s.guid}", kind, s))
    sold: dict[str, list[int]] = {}
    seen: set[int] = set()
    for v in vendors:
        if v.entry in seen or not stock.get(v.entry):
            continue
        seen.add(v.entry)
        locations.append(_location(f"vendor:{v.entry}", "vendor", v))
        sold[f"vendor:{v.entry}"] = sorted(set(stock[v.entry]))
    by_kind: dict[str, int] = {}
    for kind, _ in kept:
        by_kind[kind] = by_kind.get(kind, 0) + 1
    counts = {
        "auctioneers": len(auctioneers),
        "mailboxes": len(mailboxes),
        **dict(sorted(by_kind.items())),
        "vendors": len(sold),
        "items": len({i for items in sold.values() for i in items}),
    }
    return {
        "name": spec.name,
        "faction": spec.faction,
        "map": map_id,
        "hub": hub,
        "locations": locations,
        "vendors": sold,
        "generated": {"source": source, "tele": spec.tele, "radius": spec.radius, "counts": counts},
        "overrides": dict((existing or {}).get("overrides") or {}),
    }
