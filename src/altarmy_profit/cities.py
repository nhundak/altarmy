"""Build a city preset (`timing.CityMap`'s JSON) from the spawns around a city. Pure: scripts/build_cities.py
reads the spawns from vmangos (`vmangos.npcs_near`, ...) and writes data/<version>/cities/<name>.json.

A preset lists the auction house (the auctioneer nearest the middle of them all, which is also the hub every
character starts from), every mailbox, every crafting station DB2 names (anvils, forges, cooking fires,
...; stations new in WoW: Forever are not in vmangos and go in by hand), and every vendor selling something
without limit, with what they sell. Its `overrides` are hand-tuned (see `timing.CityMap.from_dict`) and kept
when the preset is regenerated.

Forever's new mailboxes aren't in vmangos either: the frellscout addon records where the player opens them,
and `add_scouted_mailboxes` (scripts/import_mailboxes.py) adds the ones no preset has yet to its `overrides`.
"""

from __future__ import annotations

import copy
import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import luasv
from .ingest import ZoneBox
from .timing import CityMap, station_kind
from .vmangos import Spawn


@dataclass(frozen=True)
class CitySpec:
    name: str  # the preset's name, as the app shows it
    tele: str  # vmangos' game_tele point the city is found around
    faction: str  # Horde | Alliance: only faction cities, whose auction house is the one prices track
    radius: float  # yards around the tele point that count as the city


CITY_SPECS: tuple[CitySpec, ...] = (
    CitySpec("Orgrimmar", "Orgrimmar", "Horde", 750),  # the Valley of Honor's anvils are ~660 yd out
    CitySpec("Undercity", "Undercity", "Horde", 250),
    CitySpec("Thunder Bluff", "ThunderBluff", "Horde", 450),
    CitySpec("Stormwind", "Stormwind", "Alliance", 650),
    CitySpec("Ironforge", "Ironforge", "Alliance", 350),
    CitySpec("Darnassus", "Darnassus", "Alliance", 550),
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


def _zone(
    map_id: int, locations: Sequence[dict[str, Any]], hub: str, zones: Sequence[ZoneBox]
) -> dict[str, Any] | None:
    """The smallest zone map on `map_id` whose box holds the hub; None if none does."""
    at = next(loc for loc in locations if loc["id"] == hub)
    around = [z for z in zones if z[0] == map_id and z[2] <= at["x"] <= z[4] and z[3] <= at["y"] <= z[5]]
    if not around:
        return None
    _, name, x0, y0, x1, y1 = min(around, key=lambda z: (z[4] - z[2]) * (z[5] - z[3]))
    return {"name": name, "min_x": x0, "min_y": y0, "max_x": x1, "max_y": y1}


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
    zones: Sequence[ZoneBox] = (),
) -> dict[str, Any]:
    """The preset for `spec`: its locations and vendors' stock, with `existing`'s overrides kept.
    `stations` are spell focus objects, kept if `focus_names` (DB2's SpellFocusObject) names their focus.
    `zones` (`ingest.zone_boxes`) give the city's zone map: the smallest on its map around the hub.
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
        **({"zone": zone} if (zone := _zone(map_id, locations, hub, zones)) else {}),
        "locations": locations,
        "vendors": sold,
        "generated": {"source": source, "tele": spec.tele, "radius": spec.radius, "counts": counts},
        "overrides": dict((existing or {}).get("overrides") or {}),
    }


# --- mailboxes found in game (the frellscout addon) --------------------------------------------------------
MAILBOX_YARDS = 10.0  # a scouted mailbox this close to a known one (flat distance) is that one


@dataclass(frozen=True)
class ScoutedMailbox:
    id: int
    map_id: int  # the continent (UnitPosition's instance): 0 Eastern Kingdoms, 1 Kalimdor
    x: float
    y: float
    z: float  # 0 if the client didn't say
    zone: str


def scouted_mailboxes(data: bytes) -> list[ScoutedMailbox]:
    """The mailboxes in frellscout's SavedVariables (`FrellscoutDB.mailboxes`); none if the file has no
    FrellscoutDB. ValueError if it is malformed."""
    saved = luasv.parse_assignments(data).get("FrellscoutDB")
    if saved is None:
        return []
    if not isinstance(saved, dict):
        raise ValueError("FrellscoutDB is not a table")
    boxes = saved.get("mailboxes") or {}
    if not isinstance(boxes, dict):
        raise ValueError("FrellscoutDB.mailboxes is not a table")
    out = []
    for key, box in sorted(boxes.items(), key=lambda kv: str(kv[0])):
        if not isinstance(box, dict):
            raise ValueError(f"mailbox {key} is not a table")

        def num(field: str, box: Mapping[luasv.LuaKey, luasv.LuaValue] = box, key: object = key) -> float:
            v = box.get(field, 0 if field == "z" else None)
            if isinstance(v, bool) or not isinstance(v, int | float):
                raise ValueError(f"mailbox {key}: {field} is not a number")
            return float(v)

        zone = box.get("zone")
        out.append(
            ScoutedMailbox(
                int(num("id")), int(num("instance")), num("x"), num("y"), num("z"), str(zone or "")
            )
        )
    return sorted(out, key=lambda m: m.id)


def _flat(ax: float, ay: float, bx: float, by: float) -> float:
    return math.hypot(ax - bx, ay - by)


def _radius(preset: Mapping[str, Any]) -> float:
    generated = preset.get("generated") or {}
    if "radius" in generated:
        return float(generated["radius"])
    spec = next((s for s in CITY_SPECS if s.name == preset.get("name")), None)
    return spec.radius if spec else 0.0


def add_scouted_mailboxes(
    presets: Mapping[str, Mapping[str, Any]], found: Sequence[ScoutedMailbox]
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Add each scouted mailbox to the preset of the city it is in (same map, within the preset's radius of
    its hub; the nearest such hub) as an `overrides` location, unless a mailbox the preset already has (from
    vmangos, or scouted before) stands within `MAILBOX_YARDS`. A mailbox with no height takes the nearest
    location's. Returns the changed presets (copies; `presets` is left alone) by name and one report line
    per mailbox."""
    changed: dict[str, dict[str, Any]] = {}
    maps = {name: CityMap.from_dict(p) for name, p in presets.items()}
    boxes = {  # every mailbox each preset has: (id, x, y)
        name: [(loc.id, loc.x, loc.y) for loc in city.locations if loc.kind == "mailbox"]
        for name, city in maps.items()
    }
    report = []
    for m in found:
        where = f"#{m.id}: {m.zone or '?'} ({m.x:.0f}, {m.y:.0f})"
        near = [
            (_flat(m.x, m.y, city.hub.x, city.hub.y), name)
            for name, city in maps.items()
            if presets[name].get("map") == m.map_id
            and _flat(m.x, m.y, city.hub.x, city.hub.y) <= _radius(presets[name])
        ]
        if not near:
            report.append(f"{where} is in no city preset: skipped")
            continue
        name = min(near)[1]
        known = min(((_flat(m.x, m.y, bx, by), i) for i, bx, by in boxes[name]), default=None)
        if known is not None and known[0] <= MAILBOX_YARDS:
            how = "scouted before" if known[1].startswith("mailbox:scout:") else "known from Classic"
            report.append(f"{where} is {name}'s {known[1]}, {known[0]:.1f} yd off ({how}): skipped")
            continue
        z = m.z
        if z == 0:
            z = min(maps[name].locations, key=lambda loc: _flat(m.x, m.y, loc.x, loc.y)).z
        loc_id = f"mailbox:scout:{round(m.x)}:{round(m.y)}"
        preset = changed.setdefault(name, copy.deepcopy(dict(presets[name])))
        overrides = preset.setdefault("overrides", {})
        overrides.setdefault("locations", []).append(
            {
                "id": loc_id,
                "kind": "mailbox",
                "name": "Mailbox",
                "x": round(m.x, 2),
                "y": round(m.y, 2),
                "z": round(z, 2),
            }
        )
        boxes[name].append((loc_id, m.x, m.y))
        report.append(f"{where}: added to {name} as {loc_id}")
    return changed, report
