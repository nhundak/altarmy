"""price_sales_daily.pairs, price_current.sold_pairs_7d: the pairs of scans sales were seen in

Additive: existing sales rows count no pair, and no item has a 7-day count until the next merge.

Revision ID: 0023
Revises: 0022
Create Date: 2026-10-04 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0023"
down_revision: str | None = "0022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("price_sales_daily", sa.Column("pairs", sa.Integer(), server_default="0", nullable=False))
    op.add_column("price_current", sa.Column("sold_pairs_7d", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.execute("ALTER TABLE price_current DROP COLUMN sold_pairs_7d")
    op.execute("ALTER TABLE price_sales_daily DROP COLUMN pairs")
