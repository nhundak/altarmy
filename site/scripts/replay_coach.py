"""Replay the gold coach's pick on every scanned auction house. Read-only: the go/no-go evidence before the
coach card ships (see CLAUDE.md's gold list).

Usage: python scripts/replay_coach.py [--game-version forever|tbc] [--batch 1 5 10] [--top 10]
For each named auction house with an accepted scan (`prices.coverage`), browsing without characters (every
recipe, for one crafter), at each batch size: the coach's pick (`service.coach_pick`) or why there is none,
then the top N by likely profit and by profit if all sell, each with its sale verdict and reasons. The
database is DATABASE_URL, else data/altarmy.sqlite; it is never migrated or written, so it must be
migrated already (`altarmy-site migrate`).
"""

import argparse
import sys

from sqlalchemy.exc import DBAPIError

from altarmy_site import db, prices, service, store, timing, versions
from altarmy_site.engine import Filters, Result, TimeModel, format_money
from altarmy_site.versions import GameVersion


def line(r: Result, priced: store.Priced, v: GameVersion) -> str:
    """One result: likely and all-sell profit, the verdict and why, and the units counted elsewhere."""
    judged = service.verdict(r, priced.listings, priced.watched, priced.market, v.disenchant_verified)
    made = service.likely(r, priced.listings, priced.market.sell_prices.get(r.recipe.output_item_id))
    why = ", ".join((*judged.reasons, *judged.buy_flags)) or "-"
    units = r.recipe.output_count * r.crafts
    excess = f" ({made.excess_units} of {units} elsewhere)" if made.excess_units else ""
    return (
        f"    {format_money(made.profit):>14} likely  {format_money(r.profit):>14} all sell  "
        f"{judged.level:<9} {r.recipe.name} via {r.best_exit}{excess}  [{why}]"
    )


def replay(
    priced: store.Priced, house: prices.Coverage, v: GameVersion, batches: list[int], top: int
) -> None:
    """The coach's pick and the top results at each batch size on one auction house."""
    cities = store.load_cities(v.cities_dir)
    everything = Filters(min_profit=-(10**18))
    print(
        f"\n{house.realm} ({house.faction or 'both factions'}): last scan {house.last_scan}, "
        f"{house.scans_7d} scans this week, {priced.watched:.1f} h of sales watched, "
        f"{len(priced.listings)} items priced"
    )
    for batch in batches:
        model = TimeModel(timing.TimeConfig(batch=batch), service.default_city(cities, house.faction))
        results = service.search(priced.market, [], "none", everything, time=model)
        pick, none = service.coach_pick(
            results, priced.listings, priced.watched, priced.market, v.disenchant_verified
        )
        print(f"  batch {batch}: {len(results)} recipes ranked")
        if pick is not None:
            print(f"  pick:\n{line(pick, priced, v)}")
        elif none is not None:
            surest = f" (the surest: {none.best.recipe.name})" if none.best else ""
            print(f"  no pick: {none.reason}{surest}")
        print("  by likely profit:")
        for r in service.by_likely(results, priced.listings, priced.market)[:top]:
            print(line(r, priced, v))
        print("  by profit if all sell:")
        for r in results[:top]:
            print(line(r, priced, v))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--game-version", choices=list(versions.VERSIONS), default=versions.DEFAULT_VERSION)
    p.add_argument("--batch", type=int, nargs="+", default=[1, 5, 10], help="crafts per session to replay")
    p.add_argument("--top", type=int, default=10)
    args = p.parse_args()
    v = versions.VERSIONS[args.game_version]
    database = db.Database(db.default_url(), migrate=False)
    with database.engine.connect() as conn:
        try:
            houses = [c for c in prices.coverage(conn, v.key) if c.last_scan is not None]
            if not houses:
                print(f"{v.label}: no auction house has an accepted scan.")
                return
            for h in houses:
                priced = store.load_priced(
                    conn, v.key, h.auction_house_id, ah_cut=v.ah_cut, mail_postage=v.mail_postage
                )
                replay(priced, h, v, args.batch, args.top)
        except DBAPIError as e:
            sys.exit(f"The database is behind the code (run `altarmy-site migrate` first): {e.orig}")


if __name__ == "__main__":
    main()
