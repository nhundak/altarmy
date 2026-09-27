"""Users, their per-version settings (selection, data version, time settings) and trust scores.
Functions take a `Connection` and never commit."""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields, replace
from typing import Any

from sqlalchemy import Connection, Table, delete, select

from . import db, schema
from .auth import User


def ensure_user(conn: Connection, user: User) -> None:
    """Create the user's row on first sight, and follow tier changes (the first link sets `linked_at`)."""
    t = schema.users
    row = conn.execute(select(t.c.tier, t.c.linked_at).where(t.c.uid == user.uid)).one_or_none()
    now = db.utcnow()
    linked_at = now if user.linked else None
    if row is None:
        db.upsert(
            conn,
            t,
            [{"uid": user.uid, "created_at": now, "linked_at": linked_at, "tier": user.tier}],
            ["uid"],
            update=[],
        )
    elif row.tier != user.tier:
        values: dict[str, Any] = {"tier": user.tier}
        if user.linked and row.linked_at is None:
            values["linked_at"] = now
        conn.execute(t.update().where(t.c.uid == user.uid).values(**values))


TRUST_GAIN = 0.1  # per screened scan that was accepted, up to 1
TRUST_LOSS = 0.5  # a quarantined scan multiplies the trust by this


def trust(conn: Connection, user_uid: str) -> float:
    """How far the user's scans are trusted, 0..1 (1 for unknown users): `prices.screen` allows fewer
    wild prices the lower it is."""
    t = schema.users
    found = conn.execute(select(t.c.trust_score).where(t.c.uid == user_uid)).scalar_one_or_none()
    return 1.0 if found is None else float(found)


def adjust_trust(conn: Connection, user_uid: str, *, quarantined: bool) -> float:
    """Feed a screened scan back into the user's trust: halved by a quarantine, else raised a little."""
    now = trust(conn, user_uid)
    new = now * TRUST_LOSS if quarantined else min(1.0, now + TRUST_GAIN)
    t = schema.users
    conn.execute(t.update().where(t.c.uid == user_uid).values(trust_score=new))
    return new


def delete_user(conn: Connection, user_uid: str) -> None:
    """Delete the user and everything they own (characters, settings, AH blocks, uploads cascade).
    Their price snapshots stay in the pool, no longer attributed to them."""
    snap = schema.price_snapshots
    conn.execute(snap.update().where(snap.c.uploader_uid == user_uid).values(uploader_uid=None))
    conn.execute(delete(schema.users).where(schema.users.c.uid == user_uid))


@dataclass(frozen=True)
class UserSettings:
    selected_realm: str | None = None  # with selected_faction: whose characters count
    selected_faction: str | None = None
    data_version: int = 0  # bumped when the user's characters or prices were re-imported
    time_city: str | None = None  # the city preset profit per hour is timed in; None: the faction's default
    time_config: str | None = None  # JSON of the user's timing.TimeConfig overrides; None: the defaults


def _get(conn: Connection, t: Table, user_uid: str, game_version: str) -> dict[str, Any] | None:
    row = (
        conn.execute(select(t).where(t.c.user_uid == user_uid, t.c.game_version == game_version))
        .mappings()
        .one_or_none()
    )
    return None if row is None else dict(row)


def _put(conn: Connection, t: Table, user_uid: str, game_version: str, values: dict[str, Any]) -> None:
    row = {"user_uid": user_uid, "game_version": game_version, **values}
    db.upsert(conn, t, [row], ["user_uid", "game_version"])


def get_settings(conn: Connection, user_uid: str, game_version: str) -> UserSettings:
    row = _get(conn, schema.user_settings, user_uid, game_version)
    if row is None:
        return UserSettings()
    return UserSettings(**{f.name: row[f.name] for f in fields(UserSettings)})


def update_settings(conn: Connection, user_uid: str, game_version: str, **changes: Any) -> UserSettings:
    """Change some settings (keyword per `UserSettings` field); returns them all."""
    new = replace(get_settings(conn, user_uid, game_version), **changes)
    _put(conn, schema.user_settings, user_uid, game_version, asdict(new))
    return new
