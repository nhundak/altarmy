"""AHledger prices, Forever auction houses per faction: price_snapshots.source also allows 'ahledger',
feed_tables keeps each market's last price table, and Forever's shared (both-faction) named auction houses
are deleted with their prices

Forever's auction houses are split by faction, but Auctionator's Forever realm keys carry none, so uploads
went into one house both factions shared. From now on an upload's faction comes from the uploader's
characters (`uploads`) and AHledger fills each faction's house; the mixed prices are dropped.

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-27 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

OLD = "source IN ('auctionator', 'ahdb', 'blizzard_api', 'csv', 'manual')"
NEW = "source IN ('auctionator', 'ahledger', 'ahdb', 'blizzard_api', 'csv', 'manual')"
CONSTRAINT = "ck_price_snapshots_source"


def _set_sources(old: str, new: str) -> None:
    """Swap the CHECK on price_snapshots.source. SQLite can only change a CHECK by copying the table, and
    dropping price_snapshots would cascade into price_observations (foreign keys are on), so there the
    stored table definition is edited in place, as SQLite's ALTER TABLE documentation describes for
    changes that leave the stored rows valid."""
    conn = op.get_bind()
    if conn.dialect.name != "sqlite":
        op.drop_constraint(op.f(CONSTRAINT), "price_snapshots", type_="check")
        op.create_check_constraint(op.f(CONSTRAINT), "price_snapshots", sa.text(new))
        return
    version = int(conn.exec_driver_sql("PRAGMA schema_version").scalar_one())
    conn.exec_driver_sql("PRAGMA writable_schema=ON")
    conn.execute(
        sa.text(
            "UPDATE sqlite_master SET sql = replace(sql, :old, :new) "
            "WHERE type = 'table' AND name = 'price_snapshots'"
        ),
        {"old": old, "new": new},
    )
    conn.exec_driver_sql(f"PRAGMA schema_version={version + 1}")
    conn.exec_driver_sql("PRAGMA writable_schema=OFF")


SHARED = "SELECT id FROM auction_houses WHERE game_version = 'forever' AND faction = '' AND realm <> ''"


def _drop_shared_forever_houses() -> None:
    snapshots = f"SELECT id FROM price_snapshots WHERE auction_house_id IN ({SHARED})"
    for statement in (
        f"DELETE FROM price_current WHERE auction_house_id IN ({SHARED})",
        f"DELETE FROM price_daily WHERE auction_house_id IN ({SHARED})",
        f"DELETE FROM price_observations WHERE snapshot_id IN ({snapshots})",
        f"DELETE FROM price_snapshots WHERE auction_house_id IN ({SHARED})",
        f"DELETE FROM realm_aliases WHERE auction_house_id IN ({SHARED})",
        "UPDATE user_settings SET selected_realm = NULL, selected_faction = NULL "
        "WHERE game_version = 'forever' AND selected_faction = '' AND selected_realm <> ''",
        f"DELETE FROM auction_houses WHERE id IN ({SHARED})",
    ):
        op.execute(statement)


def upgrade() -> None:
    _set_sources(OLD, NEW)
    op.create_table(
        "feed_tables",
        sa.Column("source", sa.String(length=16), nullable=False),
        sa.Column("market", sa.String(length=64), nullable=False),
        sa.Column("auction_house_id", sa.Integer(), nullable=False),
        sa.Column("scanned_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("stamped_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(
            ["auction_house_id"],
            ["auction_houses.id"],
            name=op.f("fk_feed_tables_auction_house_id_auction_houses"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("source", "market", name=op.f("pk_feed_tables")),
    )
    _drop_shared_forever_houses()


def downgrade() -> None:
    # The deleted prices are gone for good; only the source and feed_tables are undone.
    op.drop_table("feed_tables")
    op.execute(
        "DELETE FROM price_current WHERE snapshot_id IN "
        "(SELECT id FROM price_snapshots WHERE source = 'ahledger')"
    )
    op.execute(
        "DELETE FROM price_observations WHERE snapshot_id IN "
        "(SELECT id FROM price_snapshots WHERE source = 'ahledger')"
    )
    op.execute("DELETE FROM price_snapshots WHERE source = 'ahledger'")
    _set_sources(NEW, OLD)
