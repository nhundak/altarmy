"""recipes: what teaches each (a trainer, a tradable recipe item, a bind on pickup one), filled at ingest

Additive: the previous release's instances read named columns, and its ingest job inserts named ones, so
the default ("trainer") covers both until the next game data update fills it.

Revision ID: 0019
Revises: 0018
Create Date: 2026-10-01 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, also on SQLite: no table rebuild (see 0007).
    op.add_column("recipes", sa.Column("source", sa.Text(), server_default="trainer", nullable=False))


def downgrade() -> None:
    op.execute("ALTER TABLE recipes DROP COLUMN source")
