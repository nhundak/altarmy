"""Time loading the market and ranking recipes for each realm/faction's characters. Read-only.

Usage: python scripts/bench_rank.py [--game-version forever|tbc] [--uid UID] [--altarmy <AltArmy_TBC.lua>]
[--repeat N]
Characters come from --altarmy if given, else from the database (user --uid's). Prices are that user's
selected realm's auction house's (without a user, the freshest one). The database is DATABASE_URL, else
data/altarmy-profit.sqlite. Prints the best of N runs per step. "timed" ranks with unlearned recipes in
the version's first faction city (or anywhere) at 50 gold per hour of play; "by rate" then sorts those
results by profit per hour (timing each).
"""

import argparse
import time
from collections.abc import Callable
from functools import partial
from pathlib import Path
from typing import TypeVar

from altarmy_profit import altarmy, db, prices, service, store, timing, versions
from altarmy_profit.engine import Filters, TimeModel

T = TypeVar("T")


def best_of(n: int, fn: Callable[[], T]) -> tuple[float, T]:
    """The fastest of `n` runs (at least one) and the last result."""
    times = []
    for _ in range(max(1, n)):
        start = time.perf_counter()
        out = fn()
        times.append(time.perf_counter() - start)
    return min(times), out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--game-version", choices=list(versions.VERSIONS), default=versions.DEFAULT_VERSION)
    p.add_argument("--uid", default="", help="whose characters and selection (a users.uid)")
    p.add_argument("--altarmy", type=Path, help="Alt Army SavedVariables to take characters from")
    p.add_argument("--repeat", type=int, default=3)
    args = p.parse_args()
    v = versions.VERSIONS[args.game_version]
    database = db.Database(db.default_url())
    conn = database.connect()
    ah = service.selected_auction_house(conn, args.uid, v.key)
    print(
        f"{v.label}: build {db.get_build(conn, v.key)}, {db.count_rows(conn, 'items', v.key)} items, "
        f"{db.count_rows(conn, 'recipes', v.key)} recipes, {prices.count_current(conn, ah)} prices"
    )
    load, market = best_of(
        args.repeat, partial(store.load_market, conn, v.key, ah, ah_cut=v.ah_cut, mail_postage=v.mail_postage)
    )
    print(f"load_market: {load:.3f}s")
    chars = (
        altarmy.parse_characters(args.altarmy.read_bytes())
        if args.altarmy
        else store.load_characters(conn, args.uid, v.key)
    )
    everything = Filters(min_profit=-(10**18))
    cities = store.load_cities(v.cities_dir)
    config = timing.TimeConfig(time_value=50 * 10_000)
    columns = f"{'learned':>16} {'+ unlearned':>16} {'timed':>16} {'by rate':>8}"
    print(f"{'realm (faction)':<32} {'chars':>5} {columns}")
    for g in altarmy.groups(chars):
        cells = []
        for unlearned in (False, True):
            search = partial(service.search, market, g.characters, unlearned, everything)
            secs, results = best_of(args.repeat, search)
            cells.append(f"{secs:6.3f}s {len(results):>5}")
        model = TimeModel(config, service.default_city(cities, g.faction))
        timed = partial(service.search, market, g.characters, True, everything, time=model)
        secs, results = best_of(args.repeat, timed)
        cells.append(f"{secs:6.3f}s {len(results):>5}")
        rate_secs, _ = best_of(1, partial(service.by_rate, results))
        cells.append(f"{rate_secs:6.3f}s")
        print(
            f"{g.realm + ' (' + g.faction + ')':<32} {len(g.characters):>5} {cells[0]:>16} {cells[1]:>16}"
            f" {cells[2]:>16} {cells[3]:>8}"
        )
    conn.close()
    database.dispose()


if __name__ == "__main__":
    main()
