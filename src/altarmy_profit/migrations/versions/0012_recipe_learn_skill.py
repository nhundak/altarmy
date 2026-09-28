"""recipes: the skill the recipe item teaching one requires, filled at ingest

Additive: the previous release's instances read named columns, and its ingest job inserts named ones, so
the default covers both until the next game data update fills it.

Revision ID: 0012
Revises: 0011
Create Date: 2026-09-28 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, also on SQLite: no table rebuild (see 0007).
    op.add_column("recipes", sa.Column("learn_skill", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    op.execute("ALTER TABLE recipes DROP COLUMN learn_skill")
