"""price_observations and price_current: a feed's sell cap, and the quantity listed

AHledger's table gives each item's 7- and 30-day medians; the poller stores the lower one where it is below
the cheapest listing (a lone absurd ask) as the most a sale counts as. `price_current.quantity` is the units
listed, for thin-market flags. Every market's last table is forgotten, so the next poll records every row
with them instead of waiting for each to change (a lone stale listing, the very case, may not change for
days).

Additive: nullable columns the previous release's instances never read; its ahledger job could record a
first table without them between the migrate job and the rollout, and those rows fill as they change.

Revision ID: 0013
Revises: 0012
Create Date: 2026-09-29 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("price_observations", sa.Column("sell_cap", sa.BigInteger(), nullable=True))
    op.add_column("price_current", sa.Column("sell_cap", sa.BigInteger(), nullable=True))
    op.add_column("price_current", sa.Column("quantity", sa.Integer(), nullable=True))
    op.execute("DELETE FROM feed_tables")


def downgrade() -> None:
    for column in ("quantity", "sell_cap"):
        op.execute(f"ALTER TABLE price_current DROP COLUMN {column}")
    op.execute("ALTER TABLE price_observations DROP COLUMN sell_cap")
