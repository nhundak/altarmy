"""job_runs: each run of a scheduled CLI job (ingest, merge, prune, ahledger), for the Admin page

Additive: the previous release's jobs and instances never read it.

Revision ID: 0010
Revises: 0009
Create Date: 2026-09-27 16:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "job_runs",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("job", sa.String(length=16), nullable=False),
        sa.Column("game_version", sa.String(length=16), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ok", sa.Boolean(), nullable=True),
        sa.Column("summary", sa.Text(), server_default="", nullable=False),
        sa.CheckConstraint("job IN ('ingest', 'merge', 'prune', 'ahledger')", name=op.f("ck_job_runs_job")),
        sa.ForeignKeyConstraint(
            ["game_version"], ["game_versions.id"], name=op.f("fk_job_runs_game_version_game_versions")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_job_runs")),
    )
    op.create_index(op.f("ix_job_runs_job_started_at"), "job_runs", ["job", "started_at"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_job_runs_job_started_at"), table_name="job_runs")
    op.drop_table("job_runs")
