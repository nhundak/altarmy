"""favorite_recipes: the recipes each user marked as favorites

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-26 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "favorite_recipes",
        sa.Column("user_uid", sa.String(length=128), nullable=False),
        sa.Column("game_version", sa.String(length=16), nullable=False),
        sa.Column("recipe_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["game_version"],
            ["game_versions.id"],
            name=op.f("fk_favorite_recipes_game_version_game_versions"),
        ),
        sa.ForeignKeyConstraint(
            ["user_uid"], ["users.uid"], name=op.f("fk_favorite_recipes_user_uid_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("user_uid", "game_version", "recipe_id", name=op.f("pk_favorite_recipes")),
    )


def downgrade() -> None:
    op.drop_table("favorite_recipes")
