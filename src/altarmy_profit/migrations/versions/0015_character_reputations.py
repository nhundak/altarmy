"""character_reputations: each character's standing with the city factions, which discounts what their
vendors charge

Additive: a table the previous release's instances never read.

Revision ID: 0015
Revises: 0014
Create Date: 2026-09-30 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "character_reputations",
        sa.Column("character_id", sa.Integer(), nullable=False),
        sa.Column("faction_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("standing", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["character_id"],
            ["characters.id"],
            name=op.f("fk_character_reputations_character_id_characters"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("character_id", "faction_id", name=op.f("pk_character_reputations")),
    )


def downgrade() -> None:
    op.drop_table("character_reputations")
