"""recipe timing: recipes.cast_time_ms and station; user_settings.time_city and time_config

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-25 23:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: a batch rebuild of recipes would cascade its drop into
    # recipe_reagents, and one of user_settings would need its foreign keys rebuilt.
    op.add_column("recipes", sa.Column("cast_time_ms", sa.Integer(), server_default="0", nullable=False))
    op.add_column("recipes", sa.Column("station", sa.Text(), server_default="", nullable=False))
    op.add_column("user_settings", sa.Column("time_city", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("time_config", sa.Text(), nullable=True))


def downgrade() -> None:
    # Native DROP COLUMN (SQLite 3.35+) for the same reason: no table rebuild.
    op.execute("ALTER TABLE user_settings DROP COLUMN time_config")
    op.execute("ALTER TABLE user_settings DROP COLUMN time_city")
    op.execute("ALTER TABLE recipes DROP COLUMN station")
    op.execute("ALTER TABLE recipes DROP COLUMN cast_time_ms")
