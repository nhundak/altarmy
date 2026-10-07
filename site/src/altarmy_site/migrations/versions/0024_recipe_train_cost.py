"""recipes.train_cost: what a trainer asks to teach each recipe, filled at ingest

Additive: every recipe reads 0 (no fee known) until the next game data update.

Revision ID: 0024
Revises: 0023
Create Date: 2026-10-05 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0024"
down_revision: str | None = "0023"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, also on SQLite: no table rebuild (see 0007).
    op.add_column("recipes", sa.Column("train_cost", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    op.execute("ALTER TABLE recipes DROP COLUMN train_cost")
