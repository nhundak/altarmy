"""items.disenchantable: False for items ItemSparse flags NO_DISENCHANT

Additive: existing rows read true until the next game data update.

Revision ID: 0016
Revises: 0015
Create Date: 2026-09-30 18:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "items", sa.Column("disenchantable", sa.Boolean(), server_default=sa.true(), nullable=False)
    )


def downgrade() -> None:
    with op.batch_alter_table("items") as batch_op:
        batch_op.drop_column("disenchantable")
