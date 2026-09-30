"""The game versions the app supports: TBC Anniversary and WoW: Forever.

Alt Army runs on both clients and writes the same `AltArmy_TBC.lua` on each; only the WoW flavor folder
(`_anniversary_`, `_classic_beta_`) tells them apart. Every version shares one database, keyed by `key`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from .engine import AH_CUT, MAIL_POSTAGE

GameVersionKey = Literal["tbc", "forever"]
DATA_DIR = Path("data")


@dataclass(frozen=True)
class GameVersion:
    key: GameVersionKey
    label: str
    wago_product: str  # wago.tools product whose DB2 tables describe this client
    default_build: str  # pinned build ingested unless another (or "latest") is asked for
    flavor_folders: tuple[str, ...]  # WoW install subfolders whose WTF holds this client's SavedVariables
    data_dir: Path  # hand-maintained CSVs: disenchant.csv, vendor_items.csv
    interface: int  # the client's interface number (## Interface in addon TOCs)
    max_level: int  # the level cap
    max_skill: int  # the highest profession skill rank
    ah_cut: float = AH_CUT
    mail_postage: int = MAIL_POSTAGE  # copper per attachment
    # Prices come from the Alt Army addon's full scans (and prices set by hand) alone: `prices.record_book`
    first_party_prices: bool = False
    # (standing, percent off) at a vendor for the buyer's standing with the vendor's faction (5 Friendly,
    # 6 Honored, 7 Revered, 8 Exalted; see `reputation`); standings not listed get nothing off
    reputation_discounts: tuple[tuple[int, int], ...] = ()

    @property
    def disenchant_csv(self) -> Path:
        return self.data_dir / "disenchant.csv"

    @property
    def vendor_csv(self) -> Path:
        return self.data_dir / "vendor_items.csv"

    @property
    def cities_dir(self) -> Path:
        """City presets for timing crafts (`timing.CityMap` JSON), from scripts/build_cities.py."""
        return self.data_dir / "cities"


VERSIONS: dict[str, GameVersion] = {
    "forever": GameVersion(
        key="forever",
        label="WoW: Forever",
        wago_product="wow_classic_beta",
        default_build="1.60.1.70124",
        flavor_folders=("_classic_beta_",),
        data_dir=DATA_DIR / "forever",
        interface=16001,
        max_level=60,
        max_skill=300,
        first_party_prices=True,
        reputation_discounts=((6, 10), (7, 10), (8, 10)),  # vanilla's: 10% from Honored, no more after
    ),
    "tbc": GameVersion(
        key="tbc",
        label="TBC Anniversary",
        wago_product="wow_anniversary",
        default_build="2.5.6.69795",
        flavor_folders=("_anniversary_",),
        data_dir=DATA_DIR / "tbc",
        interface=20506,
        max_level=70,
        max_skill=375,
    ),
}
DEFAULT_VERSION: GameVersionKey = "forever"


def get(key: str) -> GameVersion:
    """The version named `key`; ValueError listing the known ones otherwise."""
    try:
        return VERSIONS[key]
    except KeyError:
        raise ValueError(f"unknown game version {key!r}; expected one of {', '.join(VERSIONS)}") from None


def version_of_build(build: str) -> GameVersionKey:
    """Which version a DB2 build belongs to: 2.x is TBC, anything else (1.60.x) is Forever."""
    return "tbc" if build.startswith("2.") else "forever"
