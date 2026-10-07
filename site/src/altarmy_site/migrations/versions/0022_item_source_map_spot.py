"""item_sources.area, map_x, map_y: a vendor's zone map and where on it it stands

Additive: existing rows read 0 until the next game data update. 0021 was released without these columns and
later edited to have them, so a database migrated with the edited 0021 already has them: only missing ones
are added.

Revision ID: 0022
Revises: 0021
Create Date: 2026-10-02 19:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0022"
down_revision: str | None = "0021"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

COLUMNS = (
    sa.Column("area", sa.Integer(), server_default="0", nullable=False),
    sa.Column("map_x", sa.Float(), server_default="0", nullable=False),
    sa.Column("map_y", sa.Float(), server_default="0", nullable=False),
)


def upgrade() -> None:
    present = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("item_sources")}
    for column in COLUMNS:
        if column.name not in present:
            op.add_column("item_sources", column)


def downgrade() -> None:
    with op.batch_alter_table("item_sources") as batch_op:
        for column in COLUMNS:
            batch_op.drop_column(column.name)
