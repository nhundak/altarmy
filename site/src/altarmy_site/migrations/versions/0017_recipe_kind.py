"""recipes.kind: "craft" for profession recipes, "convert" for essence conversions

Additive: existing rows read "craft"; conversions appear with the next game data update.

Revision ID: 0017
Revises: 0016
Create Date: 2026-09-30 19:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("recipes", sa.Column("kind", sa.Text(), server_default="craft", nullable=False))


def downgrade() -> None:
    with op.batch_alter_table("recipes") as batch_op:
        batch_op.drop_column("kind")
