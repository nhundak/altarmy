"""Where WoW keeps the addons' SavedVariables. Standard library only, so the watcher and Alt Army Sync need
no database packages; `prices` re-exports these for the rest of the code."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from pathlib import Path

ALTARMY_FILE = "AltArmy_TBC.lua"
WOW_ROOTS = [
    Path(r"C:\Program Files (x86)\World of Warcraft"),
    Path(r"C:\Program Files\World of Warcraft"),
    Path(r"D:\World of Warcraft"),
]


def find_auctionator_files(
    roots: Iterable[Path] = WOW_ROOTS, flavors: Sequence[str] | None = None
) -> list[Path]:
    """Account-wide Auctionator SavedVariables under each WoW install's flavor folders (_retail_, ...), or
    only under `flavors` (e.g. ("_anniversary_",))."""
    return _find(roots, flavors, "Auctionator.lua")


def find_altarmy_files(roots: Iterable[Path] = WOW_ROOTS, flavors: Sequence[str] | None = None) -> list[Path]:
    """Alt Army's account-wide SavedVariables (characters, professions, recipes) under each WoW install,
    or only under `flavors`."""
    return _find(roots, flavors, ALTARMY_FILE)


def find_saved_variables(
    name: str, roots: Iterable[Path] = WOW_ROOTS, flavors: Sequence[str] | None = None
) -> list[Path]:
    """Any addon's account-wide SavedVariables file `name` (e.g. "frellscout.lua") under each WoW install,
    or only under `flavors`."""
    return _find(roots, flavors, name)


def _find(roots: Iterable[Path], flavors: Sequence[str] | None, name: str) -> list[Path]:
    found: list[Path] = []
    for root in roots:
        for flavor in flavors if flavors is not None else ("_*_",):
            found += sorted(root.glob(f"{flavor}/WTF/Account/*/SavedVariables/{name}"))
    return found
