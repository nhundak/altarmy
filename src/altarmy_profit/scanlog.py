"""Which faction an Auctionator upload's prices came from, from the Alt Army addon's log of Auctionator's
database updates (`AltArmyTBC_AuctionScans` in `AltArmy_TBC.lua`, written by the addon's
`Data/Integrations/AuctionatorScans.lua`). On a modern auction house (WoW: Forever) Auctionator keys prices by
realm alone, so the watcher sends the faction the log names with the upload (`POST /api/uploads`' `faction`).

Pure and standard library only (the watcher and Alt Army Sync use it). The log is read leniently: anything
malformed is ignored and means "don't know", never an error.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from .luasv import parse_assignment

GLOBAL = "AltArmyTBC_AuctionScans"
FACTIONS = ("Horde", "Alliance")
SLACK = 60  # seconds a scan may be stamped after the file's modified time (clock rounding)


@dataclass(frozen=True)
class Scan:
    t: int  # Unix seconds, the game client's time()
    faction: str  # Horde | Alliance
    key: str  # Auctionator's realm key


def read(data: bytes) -> list[Scan]:
    """The logged scans in an `AltArmy_TBC.lua`, oldest first; [] without a (readable) log."""
    try:
        log = parse_assignment(data, GLOBAL)
    except (ValueError, IndexError, RecursionError):
        return []
    scans = log.get("scans") if isinstance(log, dict) else None
    if not isinstance(scans, dict):
        return []
    out = []
    for entry in scans.values():
        if not isinstance(entry, dict):
            continue
        t, faction, key = entry.get("t"), entry.get("faction"), entry.get("key")
        if isinstance(t, int | float) and not isinstance(t, bool) and faction in FACTIONS:
            out.append(Scan(int(t), str(faction), key if isinstance(key, str) else ""))
    return sorted(out, key=lambda s: s.t)


def scan_faction(scans: Iterable[Scan], since: int | None, until: int) -> str | None:
    """The faction every price update in an Auctionator file came from, or None if unknown or mixed.

    `until` is the file's modified time; `since` the modified time of the copy uploaded before, whose
    updates are already accounted for. Without one (never uploaded), the newest update alone decides: it
    wrote the current prices."""
    scans = [s for s in scans if s.t <= until + SLACK]
    if since is None:
        return max(scans, key=lambda s: s.t).faction if scans else None
    factions = {s.faction for s in scans if s.t > since}
    return factions.pop() if len(factions) == 1 else None
