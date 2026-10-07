"""paste uploads: uploads.via also allows 'paste' (the Alt Army addon's paste export)

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-25 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _uploads(via: str) -> sa.Table:
    """`uploads` as it stands, for SQLite's table copy (reflection would lose the CHECK constraints). Nothing
    references `uploads`, so the copy cascades nowhere."""
    return sa.Table(
        "uploads",
        sa.MetaData(),
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_uid", sa.String(128), sa.ForeignKey("users.uid", ondelete="CASCADE"), nullable=False),
        sa.Column("game_version", sa.String(16), sa.ForeignKey("game_versions.id"), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("via", sa.String(16), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("outcome", sa.String(16), nullable=False),
        sa.Column("detail", sa.Text(), nullable=False),
        sa.CheckConstraint("kind IN ('altarmy', 'auctionator')", name="ck_uploads_kind"),
        sa.CheckConstraint(via, name="ck_uploads_via"),
        sa.CheckConstraint("outcome IN ('accepted', 'rejected')", name="ck_uploads_outcome"),
        sa.Index("ix_uploads_user_uid_received_at", "user_uid", "received_at"),
    )


OLD = "via IN ('browser', 'watcher')"
NEW = "via IN ('browser', 'watcher', 'paste')"


def _set_via(old: str, new: str) -> None:
    with op.batch_alter_table("uploads", copy_from=_uploads(old)) as batch_op:
        batch_op.drop_constraint(op.f("ck_uploads_via"), type_="check")
        batch_op.create_check_constraint(op.f("ck_uploads_via"), sa.text(new))


def upgrade() -> None:
    _set_via(OLD, NEW)


def downgrade() -> None:
    op.execute("DELETE FROM uploads WHERE via = 'paste'")
    _set_via(NEW, OLD)
