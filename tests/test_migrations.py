"""The Alembic migrations build exactly `schema.metadata`, can be undone, and keep existing data."""

from datetime import UTC, datetime

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import Connection, MetaData, func, inspect, select
from sqlalchemy.exc import IntegrityError

from altarmy_profit import db, schema

from .conftest import ME


def test_migrations_match_the_schema(database: db.Database) -> None:
    with database.engine.connect() as conn:
        ctx = MigrationContext.configure(conn, opts={"compare_type": True})
        assert compare_metadata(ctx, schema.metadata) == []


def test_downgrade_to_base_and_back(database: db.Database) -> None:
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "base")
        assert set(inspect(conn).get_table_names()) <= {"alembic_version"}
        db.upgrade(conn)
        db.register_versions(conn)
        assert set(schema.metadata.tables) <= set(inspect(conn).get_table_names())


def _seed_0001(conn: Connection) -> None:
    """Local state as revision 0001 stored it: key-value settings, and no owners."""
    old = MetaData()
    old.reflect(conn)
    t = old.tables
    settings = {
        "selected_realm": "Dreamscythe",
        "selected_faction": "Horde",
        "data_version": "7",
        "altarmy_path": "C:\\WoW\\AltArmy_TBC.lua",
        "altarmy_mtime": "1790278648646352200",
        "altarmy_synced": "2026-09-24 20:53:15",
        "auctionator_path": "C:\\WoW\\Auctionator.lua",
        "auctionator_mtime": "1790278648000000000",
        "auctionator_synced": "2026-09-24 20:53:16",
        "auctionator_realm": "Dreamscythe Horde",
        "auctionator_for": "Dreamscythe\tHorde",
        "some_retired_key": "ignored",
    }
    conn.execute(
        t["settings"].insert(), [{"game_version": "tbc", "key": k, "value": v} for k, v in settings.items()]
    )
    conn.execute(
        t["settings"].insert(), [{"game_version": "forever", "key": "selected_realm", "value": "PvE"}]
    )
    for char_id, name in ((5, "Tailor"), (9, "Enchanter")):
        conn.execute(
            t["characters"]
            .insert()
            .values(
                id=char_id,
                game_version="tbc",
                realm="Dreamscythe",
                name=name,
                faction="Horde",
                class_file="MAGE",
                level=70,
            )
        )
        conn.execute(
            t["character_professions"]
            .insert()
            .values(character_id=char_id, skill_name="Tailoring", rank=375, max_rank=375)
        )
        conn.execute(
            t["character_recipes"].insert(),
            [{"character_id": char_id, "skill_name": "Tailoring", "spell_id": s} for s in (100, 200)],
        )
    added = datetime(2026, 9, 1, 12, 0, tzinfo=UTC)
    conn.execute(t["ah_blocked"].insert().values(game_version="tbc", item_id=42, added_at=added))
    ah: int = conn.execute(
        t["auction_houses"]
        .insert()
        .values(game_version="tbc", realm="Dreamscythe", faction="Horde")
        .returning(t["auction_houses"].c.id)
    ).scalar_one()
    conn.execute(
        t["price_snapshots"]
        .insert()
        .values(
            auction_house_id=ah,
            source="auctionator",
            scanned_at=added,
            received_at=added,
            item_count=1,
            status="accepted",
        )
    )


def test_0002_moves_local_state_to_the_local_user(database: db.Database) -> None:
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0001")
        _seed_0001(conn)
        db.upgrade(conn)

        users = conn.execute(select(schema.users.c.uid, schema.users.c.tier)).all()
        assert [tuple(u) for u in users] == [("local", "linked")]

        s = schema.user_settings
        rows = conn.execute(select(s).order_by(s.c.game_version)).mappings().all()
        assert [dict(r) for r in rows] == [
            {
                "user_uid": "local",
                "game_version": "forever",
                "selected_realm": "PvE",
                "selected_faction": None,
                "data_version": 0,
                "time_city": None,
                "time_config": None,
            },
            {
                "user_uid": "local",
                "game_version": "tbc",
                "selected_realm": "Dreamscythe",
                "selected_faction": "Horde",
                "data_version": 7,
                "time_city": None,
                "time_config": None,
            },
        ]

        ls = schema.local_sync
        sync = conn.execute(select(ls)).mappings().one()
        assert (sync["user_uid"], sync["game_version"]) == ("local", "tbc")
        assert sync["altarmy_path"] == "C:\\WoW\\AltArmy_TBC.lua"
        assert sync["altarmy_mtime"] == 1790278648646352200
        assert db.timestamp_text(sync["altarmy_synced"]) == "2026-09-24 20:53:15"
        assert sync["auctionator_mtime"] == 1790278648000000000
        assert db.timestamp_text(sync["auctionator_synced"]) == "2026-09-24 20:53:16"
        assert sync["auctionator_realm"] == "Dreamscythe Horde"
        assert sync["auctionator_for"] == "Dreamscythe\tHorde"

        c = schema.characters
        chars = conn.execute(select(c.c.id, c.c.user_uid, c.c.name).order_by(c.c.id)).all()
        assert [tuple(r) for r in chars] == [(5, "local", "Tailor"), (9, "local", "Enchanter")]
        cp, cr = schema.character_professions, schema.character_recipes
        profs = conn.execute(select(cp.c.character_id, cp.c.rank).order_by(cp.c.character_id)).all()
        assert [tuple(r) for r in profs] == [(5, 375), (9, 375)]
        known = conn.execute(
            select(cr.c.character_id, cr.c.spell_id).order_by(cr.c.character_id, cr.c.spell_id)
        )
        assert [tuple(r) for r in known] == [(5, 100), (5, 200), (9, 100), (9, 200)]

        b = schema.ah_blocked
        blocked = conn.execute(select(b.c.user_uid, b.c.game_version, b.c.item_id)).all()
        assert [tuple(r) for r in blocked] == [("local", "tbc", 42)]
        assert conn.execute(select(schema.price_snapshots.c.item_count)).scalar_one() == 1
        assert "settings" not in inspect(conn).get_table_names()


def test_0002_downgrade_restores_the_local_users_settings(database: db.Database) -> None:
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0001")
        _seed_0001(conn)
        db.upgrade(conn)
        command.downgrade(db.alembic_config(conn), "0001")
        old = MetaData()
        old.reflect(conn)
        t = old.tables["settings"]
        tbc: dict[str, str] = dict(
            conn.execute(select(t.c.key, t.c.value).where(t.c.game_version == "tbc")).all()
        )
        assert tbc["selected_realm"] == "Dreamscythe"
        assert tbc["data_version"] == "7"
        assert tbc["altarmy_mtime"] == "1790278648646352200"
        assert tbc["auctionator_synced"] == "2026-09-24 20:53:16"
        assert tbc["auctionator_for"] == "Dreamscythe\tHorde"
        chars = old.tables["character_recipes"]
        assert len(conn.execute(select(chars)).all()) == 4
        db.upgrade(conn)


def test_0005_keeps_uploads_and_allows_paste(database: db.Database) -> None:
    u = schema.uploads
    row = {
        "user_uid": ME,
        "game_version": "tbc",
        "kind": "altarmy",
        "via": "watcher",
        "size": 10,
        "received_at": datetime(2026, 9, 25, tzinfo=UTC),
        "outcome": "accepted",
        "detail": "4 characters",
    }
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0004")
        conn.execute(u.insert().values(**row))
        db.upgrade(conn)
        conn.execute(u.insert().values(**{**row, "via": "paste"}))
        assert conn.execute(select(u.c.via).order_by(u.c.id)).scalars().all() == ["watcher", "paste"]
        assert inspect(conn).get_indexes("uploads")[0]["name"] == "ix_uploads_user_uid_received_at"


def test_0009_allows_ahledger_and_drops_forevers_shared_houses(database: db.Database) -> None:
    t, snap, obs, pc = (
        schema.auction_houses,
        schema.price_snapshots,
        schema.price_observations,
        schema.price_current,
    )
    when = datetime(2026, 9, 25, tzinfo=UTC)
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0008")
        houses: dict[tuple[str, str], int] = {}
        for version, realm, faction in (
            ("forever", "Classic Beta PvE", ""),  # shared: dropped
            ("forever", "", ""),  # the unnamed one: kept
            ("tbc", "Dreamscythe", "Horde"),  # kept
        ):
            houses[(version, realm)] = conn.execute(
                t.insert().values(game_version=version, realm=realm, faction=faction).returning(t.c.id)
            ).scalar_one()
        for ah in houses.values():
            snapshot: int = conn.execute(
                snap.insert()
                .values(
                    auction_house_id=ah,
                    source="auctionator",
                    scanned_at=when,
                    received_at=when,
                    item_count=1,
                    status="accepted",
                )
                .returning(snap.c.id)
            ).scalar_one()
            conn.execute(obs.insert().values(snapshot_id=snapshot, item_id=1, min_buyout=5))
            conn.execute(
                pc.insert().values(
                    auction_house_id=ah, item_id=1, price=5, seen_at=when, snapshot_id=snapshot
                )
            )
        conn.execute(
            schema.realm_aliases.insert().values(
                auction_house_id=houses[("forever", "Classic Beta PvE")],
                kind="auctionator",
                value="ClassicBetaPvE",
            )
        )
        conn.execute(
            schema.user_settings.insert().values(
                user_uid=ME, game_version="forever", selected_realm="Classic Beta PvE", selected_faction=""
            )
        )
        db.upgrade(conn)
        kept = {houses[("forever", "")], houses[("tbc", "Dreamscythe")]}
        assert set(conn.execute(select(t.c.id)).scalars()) == kept
        assert set(conn.execute(select(pc.c.auction_house_id)).scalars()) == kept
        assert conn.execute(select(func.count()).select_from(obs)).scalar_one() == 2
        assert conn.execute(select(schema.realm_aliases.c.value)).all() == []
        assert conn.execute(select(schema.user_settings.c.selected_realm)).scalar_one() is None
        conn.execute(
            snap.insert().values(
                auction_house_id=houses[("tbc", "Dreamscythe")],
                source="ahledger",
                scanned_at=when,
                received_at=when,
                item_count=0,
                status="accepted",
            )
        )
        with pytest.raises(IntegrityError), conn.begin_nested():
            conn.execute(
                snap.insert().values(
                    auction_house_id=houses[("tbc", "Dreamscythe")],
                    source="nonsense",
                    scanned_at=when,
                    received_at=when,
                    item_count=0,
                    status="accepted",
                )
            )


def test_0010_records_job_runs(database: db.Database) -> None:
    t = schema.job_runs
    when = datetime(2026, 9, 27, tzinfo=UTC)
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0009")
        assert "job_runs" not in inspect(conn).get_table_names()
        db.upgrade(conn)
        conn.execute(t.insert().values(job="merge", started_at=when))
        assert conn.execute(select(t.c.job, t.c.summary, t.c.ok)).one() == ("merge", "", None)
        with pytest.raises(IntegrityError), conn.begin_nested():
            conn.execute(t.insert().values(job="nonsense", started_at=when))


def test_0011_item_tooltip_columns_default_empty(database: db.Database) -> None:
    t = schema.items
    with database.engine.begin() as conn:
        command.downgrade(db.alembic_config(conn), "0010")
        assert "armor" not in {c["name"] for c in inspect(conn).get_columns("items")}
        old = MetaData()
        old.reflect(conn, only=["items"])
        required = {c.name: 0 for c in old.tables["items"].columns if not c.nullable}
        values = {**required, "game_version": "forever", "id": 1, "name": "Linen Cloth"}
        conn.execute(old.tables["items"].insert().values(**values))
        db.upgrade(conn)
        row = conn.execute(select(t.c.armor, t.c.dmg_min, t.c.dmg_max, t.c.dps, t.c.stats, t.c.effects)).one()
        assert tuple(row) == (0, 0, 0, 0.0, "[]", "[]")
