"""items: armor, weapon damage and the stat and effect lines of the tooltip, computed at ingest

Additive: the previous release's instances read named columns, and its ingest job inserts named ones, so
the defaults cover both until the next game data update fills them.

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-28 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("items", sa.Column("armor", sa.Integer(), server_default="0", nullable=False))
    op.add_column("items", sa.Column("dmg_min", sa.Integer(), server_default="0", nullable=False))
    op.add_column("items", sa.Column("dmg_max", sa.Integer(), server_default="0", nullable=False))
    op.add_column("items", sa.Column("dps", sa.Float(), server_default="0", nullable=False))
    op.add_column("items", sa.Column("stats", sa.Text(), server_default="[]", nullable=False))
    op.add_column("items", sa.Column("effects", sa.Text(), server_default="[]", nullable=False))


def downgrade() -> None:
    for column in ("effects", "stats", "dps", "dmg_max", "dmg_min", "armor"):
        op.execute(f"ALTER TABLE items DROP COLUMN {column}")
