"""Price sources and the price store. All money is integer copper.

Every source (an uploaded Auctionator scan, a manual price) records a snapshot for one auction house
(`record_snapshot`). A snapshot writes observations only for items it tells something new about, and those
move `price_current`, which the engine reads: the newest price per auction house and item. Auctionator's
per-day history also fills `price_daily`, pooled across uploaders. Observations are pruned after
`KEEP_DAYS`; daily rows are kept. `merge.py` fills the 7-day columns, which set the sell price
(`load_buy_and_sell`) and the baseline an uploaded scan is screened against (`screen`): one whose prices
are mostly far off it is quarantined and changes nothing.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from sqlalchemy import Connection, delete, func, select

from . import db, schema
from .auctionator import ItemPrice

KEEP_DAYS = 90  # observations older than this are pruned (price_daily is kept)
AUCTIONATOR = "auctionator"
AHLEDGER = "ahledger"  # AHledger's crowdsourced scans (`ahledger`)
HAND_SET = ("manual", "csv")  # sources whose price is used as it is, never capped by the 7-day median

# Screening an uploaded scan against the 7-day medians (normal scans have at most ~5% of items this far off)
WILD_RATIO = 4.0  # a price more than this many times off its median, either way, is wild
MIN_COMPARED = 20  # fewer comparable items than this: not enough to judge
MIN_BASELINE_DAYS = 3  # an item's median counts as a baseline once it has this many days
BASE_WILD_SHARE = 0.1  # quarantine above this share of wild prices, plus TRUST_WILD_SHARE * trust
TRUST_WILD_SHARE = 0.2


@dataclass(frozen=True)
class Observation:
    """One item's price in a snapshot."""

    item_id: int
    min_buyout: int
    seen_at: datetime  # when that price was on the auction house
    quantity: int | None = None
    listings: int | None = None


# --- auction houses --------------------------------------------------------------------------------
def find_auction_house(conn: Connection, game_version: str, realm: str, faction: str) -> int | None:
    """The auction house a realm/faction's characters use: their faction's, else one the realm shares."""
    t = schema.auction_houses
    for f in dict.fromkeys((faction, "")):
        found = conn.execute(
            select(t.c.id).where(t.c.game_version == game_version, t.c.realm == realm, t.c.faction == f)
        ).scalar_one_or_none()
        if found is not None:
            return int(found)
    return None


def auction_house(conn: Connection, game_version: str, realm: str, faction: str) -> int:
    """The auction house keyed (version, realm, faction), created if new. Faction "" means shared."""
    t = schema.auction_houses
    key = {"game_version": game_version, "realm": realm, "faction": faction}
    db.upsert(conn, t, [key], list(key))
    found: int = conn.execute(
        select(t.c.id).where(t.c.game_version == game_version, t.c.realm == realm, t.c.faction == faction)
    ).scalar_one()
    return found


def unnamed_auction_house(conn: Connection, game_version: str) -> int:
    """Where prices go when no realm is known (CLI use without characters)."""
    return auction_house(conn, game_version, "", "")


def auctionator_auction_house(conn: Connection, game_version: str, key: str, realm: str, faction: str) -> int:
    """The auction house Auctionator's `key` prices for a realm/faction's characters: their faction's if
    the key names it (split auction houses, "Dreamscythe Horde"), else one both factions share. Records
    the key as an alias."""
    split = bool(faction) and key.endswith(f" {faction}")
    ah = auction_house(conn, game_version, realm, faction if split else "")
    _add_alias(conn, ah, AUCTIONATOR, key)
    return ah


def find_auction_house_by_key(conn: Connection, game_version: str, key: str) -> int | None:
    """The auction house that has Auctionator realm `key` as an alias, if any."""
    t, a = schema.auction_houses, schema.realm_aliases
    found = conn.execute(
        select(t.c.id)
        .join(a, a.c.auction_house_id == t.c.id)
        .where(t.c.game_version == game_version, a.c.kind == AUCTIONATOR, a.c.value == key)
        .order_by(t.c.id)
        .limit(1)
    ).scalar_one_or_none()
    return None if found is None else int(found)


def find_auction_house_by_alias(conn: Connection, game_version: str, realm: str, faction: str) -> int | None:
    """The auction house a realm/faction's characters use when it was named after Auctionator's key (a
    scan uploaded before the characters): the key forms `service.match_auctionator_realm` tries."""
    nospace = realm.replace(" ", "")
    for key in dict.fromkeys((f"{nospace} {faction}", nospace, f"{realm} {faction}", realm)):
        found = find_auction_house_by_key(conn, game_version, key)
        if found is not None:
            return found
    return None


def auction_house_for_auctionator_key(conn: Connection, game_version: str, key: str) -> int:
    """The auction house an Auctionator realm key names: a known alias, else parsed from the key (a
    trailing faction means a split auction house; the realm is then as Auctionator spells it)."""
    found = find_auction_house_by_key(conn, game_version, key)
    if found is not None:
        return found
    realm, _, faction = key.rpartition(" ")
    if faction not in ("Horde", "Alliance") or not realm:
        realm, faction = key, ""
    return auctionator_auction_house(conn, game_version, key, realm, faction)


def price_version(conn: Connection, auction_house_id: int | None) -> int | None:
    """How many merges changed the auction house's 7-day columns (None: no such auction house)."""
    if auction_house_id is None:
        return None
    t = schema.auction_houses
    found = conn.execute(select(t.c.price_version).where(t.c.id == auction_house_id)).scalar_one_or_none()
    return None if found is None else int(found)


@dataclass(frozen=True)
class Coverage:
    """How well an auction house is scanned."""

    auction_house_id: int
    realm: str
    faction: str  # "" if both factions share it
    prices: int  # items with a current price
    last_scan: datetime | None  # the newest accepted scan
    last_scan_items: int  # items in it
    scans_7d: int  # accepted scans in the last 7 days
    uploaders_7d: int  # distinct users who sent them
    sources: tuple[str, ...] = ()  # sources of those scans, sorted (AHledger's must be credited)


def coverage(conn: Connection, game_version: str, now: datetime | None = None) -> list[Coverage]:
    """Every named auction house of the version, by realm then faction."""
    since = db.utc(now or db.utcnow()) - timedelta(days=7)
    t, pc, snap = schema.auction_houses, schema.price_current, schema.price_snapshots
    accepted = snap.c.status == "accepted"
    counts: dict[int, int] = dict(
        conn.execute(
            select(pc.c.auction_house_id, func.count())
            .join(t, t.c.id == pc.c.auction_house_id)
            .where(t.c.game_version == game_version)
            .group_by(pc.c.auction_house_id)
        ).all()
    )
    recent = {
        r[0]: (int(r[1]), int(r[2]))
        for r in conn.execute(
            select(snap.c.auction_house_id, func.count(), func.count(snap.c.uploader_uid.distinct()))
            .where(accepted, snap.c.scanned_at >= since)
            .group_by(snap.c.auction_house_id)
        )
    }
    sources: dict[int, list[str]] = {}
    for r in conn.execute(
        select(snap.c.auction_house_id, snap.c.source)
        .where(accepted, snap.c.scanned_at >= since)
        .distinct()
        .order_by(snap.c.auction_house_id, snap.c.source)
    ):
        sources.setdefault(r.auction_house_id, []).append(r.source)
    newest = (
        select(snap.c.auction_house_id, func.max(snap.c.id).label("id"))
        .where(accepted)
        .group_by(snap.c.auction_house_id)
        .subquery()
    )
    last = {
        r.auction_house_id: (db.utc(r.scanned_at), int(r.item_count))
        for r in conn.execute(
            select(snap.c.auction_house_id, snap.c.scanned_at, snap.c.item_count).join(
                newest, newest.c.id == snap.c.id
            )
        )
    }
    out = []
    for r in conn.execute(
        select(t.c.id, t.c.realm, t.c.faction)
        .where(t.c.game_version == game_version, t.c.realm != "")
        .order_by(t.c.realm, t.c.faction)
    ):
        scan, items = last.get(r.id, (None, 0))
        scans, uploaders = recent.get(r.id, (0, 0))
        out.append(
            Coverage(
                r.id,
                r.realm,
                r.faction,
                int(counts.get(r.id, 0)),
                scan,
                items,
                scans,
                uploaders,
                tuple(sources.get(r.id, ())),
            )
        )
    return out


def freshest_auction_house(conn: Connection, game_version: str) -> tuple[str, str] | None:
    """The (realm, faction) of the named auction house with the newest accepted snapshot; None if no named
    auction house of the version has one."""
    t, snap = schema.auction_houses, schema.price_snapshots
    found = conn.execute(
        select(t.c.realm, t.c.faction)
        .join(snap, snap.c.auction_house_id == t.c.id)
        .where(t.c.game_version == game_version, t.c.realm != "", snap.c.status == "accepted")
        .order_by(snap.c.scanned_at.desc(), snap.c.id.desc())
        .limit(1)
    ).first()
    return None if found is None else (str(found.realm), str(found.faction))


def game_version_of(conn: Connection, auction_house_id: int) -> str | None:
    t = schema.auction_houses
    found = conn.execute(select(t.c.game_version).where(t.c.id == auction_house_id)).scalar_one_or_none()
    return None if found is None else str(found)


def _add_alias(conn: Connection, auction_house_id: int, kind: str, value: str) -> None:
    row = {"auction_house_id": auction_house_id, "kind": kind, "value": value}
    db.upsert(conn, schema.realm_aliases, [row], list(row))


# --- recording -------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Recorded:
    moved: int  # items whose current price moved
    quarantined: bool = False  # the scan was held back: it changed nothing
    screened: bool = False  # it was compared with enough of the baseline to judge the uploader by


def screen(
    observations: Sequence[Observation], baseline: Mapping[int, int], scanned_at: datetime, trust: float
) -> bool | None:
    """Whether to quarantine a scan: too many of its prices seen on the scan day are more than WILD_RATIO
    off the item's 7-day median (`baseline`). The share allowed shrinks with the uploader's `trust`
    (0..1). None when fewer than MIN_COMPARED items can be compared."""
    scan_day = db.utc(scanned_at).date()
    ratios = [
        o.min_buyout / baseline[o.item_id]
        for o in observations
        if baseline.get(o.item_id, 0) > 0 and db.utc(o.seen_at).date() == scan_day
    ]
    if len(ratios) < MIN_COMPARED:
        return None
    wild = sum(1 for r in ratios if r > WILD_RATIO or r < 1 / WILD_RATIO)
    return wild / len(ratios) > BASE_WILD_SHARE + TRUST_WILD_SHARE * max(0.0, min(1.0, trust))


def baseline(conn: Connection, auction_house_id: int) -> dict[int, int]:
    """{item_id: 7-day median} for items with at least MIN_BASELINE_DAYS days of it."""
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.median_7d).where(
            pc.c.auction_house_id == auction_house_id,
            pc.c.median_7d.is_not(None),
            pc.c.scans_7d >= MIN_BASELINE_DAYS,
        )
    )
    return {r.item_id: int(r.median_7d) for r in rows}


def _insert_snapshot(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    item_count: int,
    received_at: datetime | None,
    uploader_uid: str | None,
    status: str,
) -> int:
    snap = schema.price_snapshots
    snapshot_id: int = conn.execute(
        snap.insert()
        .values(
            auction_house_id=auction_house_id,
            source=source,
            uploader_uid=uploader_uid,
            scanned_at=db.utc(scanned_at),
            received_at=db.utc(received_at or db.utcnow()),
            item_count=item_count,
            status=status,
        )
        .returning(snap.c.id)
    ).scalar_one()
    return snapshot_id


def record_snapshot(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    observations: Sequence[Observation],
    *,
    received_at: datetime | None = None,
    uploader_uid: str | None = None,
) -> int:
    """Store a snapshot and whatever it adds to `price_current`. Returns how many items it moved.

    An observation is news when the auction house has no price for the item, when it was seen on a later
    day, or when it was seen no earlier and its price differs. Re-sending the same scan writes nothing."""
    snapshot_id = _insert_snapshot(
        conn, auction_house_id, source, scanned_at, len(observations), received_at, uploader_uid, "accepted"
    )
    current = _current(conn, auction_house_id)
    news = [o for o in observations if _is_news(o, current.get(o.item_id))]
    if not news:
        return 0
    conn.execute(
        schema.price_observations.insert(),
        [
            {
                "snapshot_id": snapshot_id,
                "item_id": o.item_id,
                "min_buyout": o.min_buyout,
                "quantity": o.quantity,
                "listings": o.listings,
            }
            for o in news
        ],
    )
    pc = schema.price_current
    rows = [
        {
            "auction_house_id": auction_house_id,
            "item_id": o.item_id,
            "price": o.min_buyout,
            "seen_at": db.utc(o.seen_at),
            "snapshot_id": snapshot_id,
        }
        for o in news
    ]
    db.upsert(conn, pc, rows, ["auction_house_id", "item_id"], ["price", "seen_at", "snapshot_id"])
    return len(news)


def _current(conn: Connection, auction_house_id: int) -> dict[int, tuple[int, datetime]]:
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.seen_at).where(pc.c.auction_house_id == auction_house_id)
    )
    return {r.item_id: (r.price, db.utc(r.seen_at)) for r in rows}


def _is_news(o: Observation, current: tuple[int, datetime] | None) -> bool:
    if current is None:
        return True
    price, seen_at = current
    new_seen = db.utc(o.seen_at)
    return new_seen.date() > seen_at.date() or (new_seen >= seen_at and o.min_buyout != price)


def auctionator_observations(item_prices: Mapping[int, ItemPrice], scanned_at: datetime) -> list[Observation]:
    """Observations for one realm of Auctionator's database. An item was seen at the scan time if its
    newest day is the scan's day (Auctionator counts days in local time, as does this process), else at
    the start of that day; the quantity is that day's."""
    scan = db.utc(scanned_at)
    scan_day = scan.astimezone().date()
    out = []
    for item_id, p in sorted(item_prices.items()):
        last = p.last_seen
        if last is None or last >= scan_day:
            seen_at, quantity = scan, p.days[last].available if last is not None else None
        else:
            seen_at, quantity = datetime.combine(last, time(), scan.tzinfo), p.days[last].available
        out.append(Observation(item_id, p.min_buyout, seen_at, quantity))
    return out


def record_daily(conn: Connection, auction_house_id: int, item_prices: Mapping[int, ItemPrice]) -> int:
    """Upsert Auctionator's per-day history into `price_daily`, from the newest day already stored on
    (earlier days no longer change). A day several uploaders saw pools them: the lowest low, the highest
    high, the most available. Returns the rows written."""
    pd = schema.price_daily
    newest = conn.execute(
        select(func.max(pd.c.day)).where(pd.c.auction_house_id == auction_house_id)
    ).scalar_one_or_none()
    stored: dict[tuple[int, date], tuple[int, int, int | None]] = {}
    if newest is not None:
        for r in conn.execute(
            select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available).where(
                pd.c.auction_house_id == auction_house_id, pd.c.day >= newest
            )
        ):
            stored[(r.item_id, r.day)] = (r.low, r.high, r.available)
    rows = []
    for item_id, p in item_prices.items():
        for day, s in p.days.items():
            if newest is not None and day < newest:
                continue
            low, high, available = s.low, s.high, s.available
            old = stored.get((item_id, day))
            if old is not None:
                low, high = min(low, old[0]), max(high, old[1])
                available = max((a for a in (available, old[2]) if a is not None), default=None)
            row = {"low": low, "high": high, "available": available}
            rows.append({"auction_house_id": auction_house_id, "item_id": item_id, "day": day, **row})
    db.upsert(conn, pd, rows, ["auction_house_id", "item_id", "day"], ["low", "high", "available"])
    return len(rows)


def record_auctionator(
    conn: Connection,
    auction_house_id: int,
    item_prices: Mapping[int, ItemPrice],
    scanned_at: datetime,
    uploader_uid: str | None = None,
    trust: float | None = None,
) -> Recorded:
    """One realm of an Auctionator scan: a snapshot plus its daily history. With the uploader's `trust`,
    the scan is screened first (see `screen`); a quarantined one is kept as a snapshot row only."""
    observations = auctionator_observations(item_prices, scanned_at)
    got = record_screened(conn, auction_house_id, AUCTIONATOR, scanned_at, observations, uploader_uid, trust)
    if not got.quarantined:
        record_daily(conn, auction_house_id, item_prices)
    return got


def record_screened(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    observations: Sequence[Observation],
    uploader_uid: str | None = None,
    trust: float | None = None,
) -> Recorded:
    """A snapshot, screened first with `trust` (None: not screened); a quarantined one is kept as a
    snapshot row only."""
    verdict = None
    if trust is not None:
        verdict = screen(observations, baseline(conn, auction_house_id), scanned_at, trust)
    if verdict:
        count = len(observations)
        _insert_snapshot(conn, auction_house_id, source, scanned_at, count, None, uploader_uid, "quarantined")
        return Recorded(0, quarantined=True, screened=True)
    moved = record_snapshot(
        conn, auction_house_id, source, scanned_at, observations, uploader_uid=uploader_uid
    )
    return Recorded(moved, screened=verdict is not None)


def record_daily_observations(
    conn: Connection, auction_house_id: int, observations: Sequence[Observation]
) -> int:
    """Pool observations into `price_daily` on their UTC day, as `record_daily` pools uploaders: the
    lowest low, the highest high, the most available. Returns the rows written."""
    pd = schema.price_daily
    days: dict[tuple[int, date], tuple[int, int, int | None]] = {}
    for o in observations:
        key = (o.item_id, db.utc(o.seen_at).date())
        low, high, available = days.get(key, (o.min_buyout, o.min_buyout, o.quantity))
        days[key] = (min(low, o.min_buyout), max(high, o.min_buyout), _most(available, o.quantity))
    if not days:
        return 0
    items = sorted({item for item, _ in days})
    stored = {
        (r.item_id, r.day): (r.low, r.high, r.available)
        for r in conn.execute(
            select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available).where(
                pd.c.auction_house_id == auction_house_id,
                pd.c.item_id.in_(items),
                pd.c.day >= min(day for _, day in days),
            )
        )
    }
    rows = []
    for (item_id, day), (low, high, available) in sorted(days.items()):
        old = stored.get((item_id, day))
        if old is not None:
            low, high, available = min(low, old[0]), max(high, old[1]), _most(available, old[2])
        row = {"low": low, "high": high, "available": available}
        rows.append({"auction_house_id": auction_house_id, "item_id": item_id, "day": day, **row})
    db.upsert(conn, pd, rows, ["auction_house_id", "item_id", "day"], ["low", "high", "available"])
    return len(rows)


def _most(a: int | None, b: int | None) -> int | None:
    return max((x for x in (a, b) if x is not None), default=None)


def prune(conn: Connection, now: datetime | None = None, keep_days: int = KEEP_DAYS) -> None:
    """Drop observations of snapshots older than `keep_days`, and those snapshots unless `price_current`
    still points at them."""
    cutoff = db.utc(now or db.utcnow()) - timedelta(days=keep_days)
    snap, obs, pc = schema.price_snapshots, schema.price_observations, schema.price_current
    old = select(snap.c.id).where(snap.c.scanned_at < cutoff)
    conn.execute(delete(obs).where(obs.c.snapshot_id.in_(old)))
    conn.execute(delete(snap).where(snap.c.scanned_at < cutoff, snap.c.id.not_in(select(pc.c.snapshot_id))))


# --- reading ---------------------------------------------------------------------------------------
def load_current(conn: Connection, auction_house_id: int | None) -> dict[int, int]:
    """{item_id: price} for the auction house; empty for None."""
    if auction_house_id is None:
        return {}
    pc = schema.price_current
    rows = conn.execute(select(pc.c.item_id, pc.c.price).where(pc.c.auction_house_id == auction_house_id))
    return {r.item_id: r.price for r in rows}


def load_buy_and_sell(
    conn: Connection, auction_house_id: int | None
) -> tuple[dict[int, int], dict[int, int]]:
    """({item_id: price}, {item_id: sell price}) for the auction house; empty for None. Reagents cost the
    current price; a craft sells at the lower of it and the 7-day median, so a lone overpriced listing
    doesn't count as the going rate. Prices set by hand (manual, CSV) are used as they are."""
    if auction_house_id is None:
        return {}, {}
    pc, snap = schema.price_current, schema.price_snapshots
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.median_7d, snap.c.source)
        .join(snap, snap.c.id == pc.c.snapshot_id)
        .where(pc.c.auction_house_id == auction_house_id)
    )
    buy: dict[int, int] = {}
    sell: dict[int, int] = {}
    for r in rows:
        buy[r.item_id] = r.price
        capped = r.median_7d is not None and r.source not in HAND_SET
        sell[r.item_id] = min(r.price, r.median_7d) if capped else r.price
    return buy, sell


def count_current(conn: Connection, auction_house_id: int | None) -> int:
    if auction_house_id is None:
        return 0
    pc = schema.price_current
    return int(
        conn.execute(
            select(func.count()).select_from(pc).where(pc.c.auction_house_id == auction_house_id)
        ).scalar_one()
    )


def last_import(conn: Connection, auction_house_id: int | None, source: str = AUCTIONATOR) -> str | None:
    """When the newest snapshot from `source` for the auction house arrived, as UTC text."""
    if auction_house_id is None:
        return None
    snap = schema.price_snapshots
    newest = conn.execute(
        select(func.max(snap.c.received_at)).where(
            snap.c.auction_house_id == auction_house_id, snap.c.source == source
        )
    ).scalar_one_or_none()
    return db.timestamp_text(newest)


def daily(conn: Connection, auction_house_id: int, item_id: int) -> list[tuple[date, int, int, int | None]]:
    """An item's price history: (day, low, high, available), oldest first."""
    pd = schema.price_daily
    rows = conn.execute(
        select(pd.c.day, pd.c.low, pd.c.high, pd.c.available)
        .where(pd.c.auction_house_id == auction_house_id, pd.c.item_id == item_id)
        .order_by(pd.c.day)
    )
    return [(r.day, r.low, r.high, r.available) for r in rows]


# --- sources ---------------------------------------------------------------------------------------
def set_price(
    conn: Connection, auction_house_id: int, item_id: int, price: int, source: str = "manual"
) -> None:
    """One price, seen now."""
    now = db.utcnow()
    record_snapshot(conn, auction_house_id, source, now, [Observation(item_id, price, now)])
