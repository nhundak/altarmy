"""game_versions.loads: game data loads so far, part of the cached markets' stamp

Additive: existing rows read 0; the next load makes it 1.

Revision ID: 0018
Revises: 0017
Create Date: 2026-09-30 21:30:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("game_versions", sa.Column("loads", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    # Not a batch operation: SQLite would rebuild game_versions, which other tables' foreign keys name.
    # Its own ALTER TABLE DROP COLUMN (3.35+) does it in place.
    op.drop_column("game_versions", "loads")
