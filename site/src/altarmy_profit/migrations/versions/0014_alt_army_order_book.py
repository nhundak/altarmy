"""Alt Army's order book: price_snapshots.source also allows 'altarmy', price_current keeps each item's
ladder and what the merge makes of its sales, price_sales_daily holds the inferred sales, and Forever's
prices from AHledger and Auctionator are deleted

Forever's prices now come from the Alt Army addon's full scans alone (`prices.record_book`): per item the
units listed at each price, so buying walks the ladder. What AHledger and Auctionator uploads recorded for
Forever (one minimum buyout per item) is dropped with its daily history; TBC's prices stay.

Additive: nullable columns and a table the previous release's instances never read. Its ahledger job may
still record a table between the migrate job and the rollout: the new release reads Forever's prices from
'altarmy' and hand-set snapshots only (`prices.FIRST_PARTY`), so those rows are never used.

Revision ID: 0014
Revises: 0013
Create Date: 2026-09-29 18:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

OLD = "source IN ('auctionator', 'ahledger', 'ahdb', 'blizzard_api', 'csv', 'manual')"
NEW = "source IN ('auctionator', 'ahledger', 'altarmy', 'ahdb', 'blizzard_api', 'csv', 'manual')"
CONSTRAINT = "ck_price_snapshots_source"

CURRENT_COLUMNS = (
    ("ladder", sa.Text()),
    ("listed", sa.Boolean()),
    ("market_price", sa.BigInteger()),
    ("sale_price", sa.BigInteger()),
    ("sale_rate", sa.Float()),
)


def _set_sources(old: str, new: str) -> None:
    """Swap the CHECK on price_snapshots.source, on SQLite by editing the stored table definition in
    place (see 0009: copying the table would cascade into price_observations)."""
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


FOREVER = "SELECT id FROM auction_houses WHERE game_version = 'forever'"
THIRD_PARTY = (
    f"SELECT id FROM price_snapshots WHERE source IN ('ahledger', 'auctionator') "
    f"AND auction_house_id IN ({FOREVER})"
)


def _drop_forevers_third_party_prices() -> None:
    for statement in (
        f"DELETE FROM price_current WHERE snapshot_id IN ({THIRD_PARTY})",
        f"DELETE FROM price_observations WHERE snapshot_id IN ({THIRD_PARTY})",
        f"DELETE FROM price_snapshots WHERE id IN ({THIRD_PARTY})",
        # daily rows carry no source; hand-set prices never wrote any
        f"DELETE FROM price_daily WHERE auction_house_id IN ({FOREVER})",
        f"UPDATE price_current SET median_7d = NULL, avail_7d = NULL, scans_7d = NULL, sell_cap = NULL "
        f"WHERE auction_house_id IN ({FOREVER})",
        "DELETE FROM feed_tables",
        f"UPDATE auction_houses SET price_version = price_version + 1 WHERE id IN ({FOREVER})",
    ):
        op.execute(statement)


def upgrade() -> None:
    _set_sources(OLD, NEW)
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    for name, kind in CURRENT_COLUMNS:
        op.add_column("price_current", sa.Column(name, kind, nullable=True))
    op.add_column("price_observations", sa.Column("market_price", sa.BigInteger(), nullable=True))
    op.create_table(
        "price_sales_daily",
        sa.Column("auction_house_id", sa.Integer(), nullable=False),
        sa.Column("item_id", sa.Integer(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("units", sa.Integer(), nullable=False),
        sa.Column("copper", sa.BigInteger(), nullable=False),
        sa.Column("cancelled", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["auction_house_id"],
            ["auction_houses.id"],
            name=op.f("fk_price_sales_daily_auction_house_id_auction_houses"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("auction_house_id", "item_id", "day", name=op.f("pk_price_sales_daily")),
    )
    _drop_forevers_third_party_prices()


def downgrade() -> None:
    # The deleted prices are gone for good; only the source, the columns and the table are undone.
    altarmy = "SELECT id FROM price_snapshots WHERE source = 'altarmy'"
    op.drop_table("price_sales_daily")
    op.execute(f"DELETE FROM price_current WHERE snapshot_id IN ({altarmy})")
    op.execute(f"DELETE FROM price_observations WHERE snapshot_id IN ({altarmy})")
    op.execute("DELETE FROM price_snapshots WHERE source = 'altarmy'")
    op.execute("ALTER TABLE price_observations DROP COLUMN market_price")
    for name, _ in reversed(CURRENT_COLUMNS):
        op.execute(f"ALTER TABLE price_current DROP COLUMN {name}")
    _set_sources(NEW, OLD)
