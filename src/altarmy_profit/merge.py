"""The merge: pooled price statistics per auction house, run hourly (`altarmy-profit merge`, a Cloud Run
job).

For every item with `price_daily` rows in the last LOOKBACK_DAYS days:

- `price_daily.median`: the median of that day's Auctionator low and high plus the price in every accepted
  snapshot scanned that (UTC) day, each clamped to the day's low..high.
- `price_current.median_7d`: the median of the item's daily medians on its latest SAMPLE_DAYS days with
  data (one sample per day, so a busy day doesn't outweigh the rest); `avail_7d` the median of those days'
  availability; `scans_7d` how many days that was. Latest days with data rather than the last 7 calendar
  days: one player scans every few days, and a lone overpriced listing must not be the only sample.

A snapshot's price is its market price where it has one (an Alt Army scan: the price a little way into
the listed units), else its minimum buyout.

- `price_current.sale_rate`: the units a day that sold over the last SALES_DAYS days
  (`price_sales_daily`, which Alt Army's scans fill); `sale_price`: by units, the middle price they sold
  for, once MIN_SALES sold.

Items without a day in the lookback get NULLs. A merge that changed anything bumps
`auction_houses.price_version`, which moves `store.market_stamp`, so every instance's cached market is
rebuilt.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Sequence
from datetime import date, datetime, time, timedelta

from sqlalchemy import Connection, bindparam, func, select, update

from . import db, prices, schema

SAMPLE_DAYS = 7  # the latest days with data that make an item's median
LOOKBACK_DAYS = 30  # how far back those days may be
SALES_DAYS = 7  # the calendar days whose inferred sales count
MIN_SALES = 5  # fewer units sold than this say nothing of a price

Stats = tuple[int | None, int | None, int | None]  # median_7d, avail_7d, scans_7d
Sales = tuple[int | None, float | None]  # sale_price, sale_rate


def median(values: Sequence[int]) -> int:
    """The median, rounded down to whole copper."""
    s = sorted(values)
    mid = len(s) // 2
    return s[mid] if len(s) % 2 else (s[mid - 1] + s[mid]) // 2


def merge(conn: Connection, game_version: str | None = None, *, today: date | None = None) -> dict[int, bool]:
    """Merge every auction house (of `game_version`, else of every version). Returns {id: changed}."""
    t = schema.auction_houses
    query = select(t.c.id).order_by(t.c.id)
    if game_version is not None:
        query = query.where(t.c.game_version == game_version)
    day = today or db.utcnow().date()
    ids: list[int] = list(conn.execute(query).scalars())
    return {ah: merge_auction_house(conn, ah, day) for ah in ids}


def merge_auction_house(conn: Connection, auction_house_id: int, today: date) -> bool:
    """Recompute the auction house's daily medians and 7-day columns; True if anything changed."""
    start = today - timedelta(days=LOOKBACK_DAYS - 1)
    pd, pc = schema.price_daily, schema.price_current
    days = conn.execute(
        select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available, pd.c.median).where(
            pd.c.auction_house_id == auction_house_id, pd.c.day >= start, pd.c.day <= today
        )
    ).all()
    samples = _scan_samples(conn, auction_house_id, start, today)

    daily_updates = []
    # (day, daily median, available)
    per_item: dict[int, list[tuple[date, int, int | None]]] = defaultdict(list)
    for r in days:
        clamped = [min(max(p, r.low), r.high) for p in samples.get((r.item_id, r.day), ())]
        m = median([r.low, r.high, *clamped])
        per_item[r.item_id].append((r.day, m, r.available))
        if m != r.median:
            daily_updates.append({"i": r.item_id, "d": r.day, "m": m})
    if daily_updates:
        conn.execute(
            update(pd)
            .where(
                pd.c.auction_house_id == auction_house_id,
                pd.c.item_id == bindparam("i"),
                pd.c.day == bindparam("d"),
            )
            .values(median=bindparam("m")),
            daily_updates,
        )

    sold = _sales(conn, auction_house_id, today)
    current_updates = []
    sales_updates = []
    for r in conn.execute(
        select(pc.c.item_id, pc.c.median_7d, pc.c.avail_7d, pc.c.scans_7d)
        .add_columns(pc.c.sale_price, pc.c.sale_rate)
        .where(pc.c.auction_house_id == auction_house_id)
    ):
        stats = _stats(per_item.get(r.item_id, []))
        if stats != (r.median_7d, r.avail_7d, r.scans_7d):
            current_updates.append({"i": r.item_id, "m": stats[0], "a": stats[1], "s": stats[2]})
        sales = sold.get(r.item_id, (None, None))
        if sales != (r.sale_price, r.sale_rate):
            sales_updates.append({"i": r.item_id, "p": sales[0], "r": sales[1]})
    if current_updates:
        conn.execute(
            update(pc)
            .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
            .values(median_7d=bindparam("m"), avail_7d=bindparam("a"), scans_7d=bindparam("s")),
            current_updates,
        )
    if sales_updates:
        conn.execute(
            update(pc)
            .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
            .values(sale_price=bindparam("p"), sale_rate=bindparam("r")),
            sales_updates,
        )

    changed = bool(daily_updates or current_updates or sales_updates)
    if changed:
        prices.bump_price_version(conn, auction_house_id)
    return changed


def _stats(days: list[tuple[date, int, int | None]]) -> Stats:
    latest = sorted(days, reverse=True)[:SAMPLE_DAYS]
    if not latest:
        return None, None, None
    available = [a for _, _, a in latest if a is not None]
    return median([m for _, m, _ in latest]), median(available) if available else None, len(latest)


def _sales(conn: Connection, auction_house_id: int, today: date) -> dict[int, Sales]:
    """{item_id: (sale price, units sold a day)} over the SALES_DAYS days up to `today`, for items that
    sold at all. The sale price is, by units, the middle of the days' average prices; None under
    MIN_SALES units."""
    t = schema.price_sales_daily
    rows = conn.execute(
        select(t.c.item_id, t.c.units, t.c.copper)
        .where(
            t.c.auction_house_id == auction_house_id,
            t.c.day > today - timedelta(days=SALES_DAYS),
            t.c.day <= today,
            t.c.units > 0,
        )
        .order_by(t.c.item_id, t.c.day)
    )
    days: dict[int, list[tuple[int, int]]] = defaultdict(list)  # (average price, units)
    for r in rows:
        days[r.item_id].append((r.copper // r.units, r.units))
    out: dict[int, Sales] = {}
    for item_id, sold in days.items():
        units = sum(u for _, u in sold)
        out[item_id] = (_middle(sold) if units >= MIN_SALES else None, units / SALES_DAYS)
    return out


def _middle(priced: list[tuple[int, int]]) -> int:
    """The price of the middle unit of (price, units) pairs."""
    half = sum(u for _, u in priced) / 2
    seen = 0
    for price, units in sorted(priced):
        seen += units
        if seen >= half:
            return price
    raise ValueError("no units")


def _scan_samples(
    conn: Connection, auction_house_id: int, start: date, today: date
) -> dict[tuple[int, date], list[int]]:
    """{(item_id, day): prices} from the accepted snapshots scanned in the window."""
    snap, obs = schema.price_snapshots, schema.price_observations
    since = datetime.combine(start, time(), db.utcnow().tzinfo)
    until = datetime.combine(today + timedelta(days=1), time(), db.utcnow().tzinfo)
    rows = conn.execute(
        select(
            obs.c.item_id,
            snap.c.scanned_at,
            func.coalesce(obs.c.market_price, obs.c.min_buyout).label("min_buyout"),
        )
        .join(snap, snap.c.id == obs.c.snapshot_id)
        .where(
            snap.c.auction_house_id == auction_house_id,
            snap.c.status == "accepted",
            snap.c.scanned_at >= since,
            snap.c.scanned_at < until,
        )
    )
    out: dict[tuple[int, date], list[int]] = defaultdict(list)
    for r in rows:
        out[(r.item_id, db.utc(r.scanned_at).date())].append(int(r.min_buyout))
    return out


def observation_count(conn: Connection) -> int:
    """Rows in `price_observations`: partition it by month once this passes a few million."""
    return int(conn.execute(select(func.count()).select_from(schema.price_observations)).scalar_one())
