"""character_talents: each character's Legacy talents (WoW: Forever) by spell id

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-25 22:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "character_talents",
        sa.Column("character_id", sa.Integer(), nullable=False),
        sa.Column("spell_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("rank", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["character_id"],
            ["characters.id"],
            name=op.f("fk_character_talents_character_id_characters"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("character_id", "spell_id", name=op.f("pk_character_talents")),
    )


def downgrade() -> None:
    op.drop_table("character_talents")
