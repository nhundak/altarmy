"""game_versions.ingest_fingerprint: what the loaded game data was made by, so a changed ingest reloads it

Additive: existing rows read NULL, which matches no fingerprint, so the next `ingest --only-if-new` reloads
the loaded build once and records it.

Revision ID: 0020
Revises: 0019
Create Date: 2026-10-01 18:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0020"
down_revision: str | None = "0019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("game_versions", sa.Column("ingest_fingerprint", sa.String(length=64), nullable=True))


def downgrade() -> None:
    # Not a batch operation: SQLite would rebuild game_versions, which other tables' foreign keys name.
    # Its own ALTER TABLE DROP COLUMN (3.35+) does it in place.
    op.drop_column("game_versions", "ingest_fingerprint")
