"""recipe_items and item_sources: which items teach each recipe and where they come from, filled at ingest

Additive: tables the previous release's instances never read; they stay empty until the next game data
update.

Revision ID: 0021
Revises: 0020
Create Date: 2026-10-02 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0021"
down_revision: str | None = "0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "recipe_items",
        sa.Column("game_version", sa.String(length=16), nullable=False),
        sa.Column("spell_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("item_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.ForeignKeyConstraint(
            ["game_version"],
            ["game_versions.id"],
            name=op.f("fk_recipe_items_game_version_game_versions"),
        ),
        sa.PrimaryKeyConstraint("game_version", "spell_id", "item_id", name=op.f("pk_recipe_items")),
    )
    op.create_table(
        "item_sources",
        sa.Column("game_version", sa.String(length=16), nullable=False),
        sa.Column("item_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("seq", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("zone", sa.Text(), nullable=False),
        sa.Column("side", sa.Text(), nullable=False),
        sa.Column("chance", sa.Float(), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.Column("levels", sa.Text(), nullable=False),
        sa.Column("limited", sa.Boolean(), nullable=False),
        sa.Column("area", sa.Integer(), server_default="0", nullable=False),
        sa.Column("map_x", sa.Float(), server_default="0", nullable=False),
        sa.Column("map_y", sa.Float(), server_default="0", nullable=False),
        sa.ForeignKeyConstraint(
            ["game_version"],
            ["game_versions.id"],
            name=op.f("fk_item_sources_game_version_game_versions"),
        ),
        sa.PrimaryKeyConstraint("game_version", "item_id", "seq", name=op.f("pk_item_sources")),
    )


def downgrade() -> None:
    op.drop_table("item_sources")
    op.drop_table("recipe_items")
