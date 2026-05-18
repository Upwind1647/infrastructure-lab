"""create deployments table

Revision ID: 20260413_0001
Revises:
Create Date: 2026-04-13 00:00:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20260413_0001"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "deployments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("git_sha", sa.String(length=40), nullable=False),
        sa.Column("environment", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("committed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deployed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "git_sha",
            "environment",
            "status",
            "committed_at",
            name="uq_deployments_event",
        ),
    )
    op.create_index(
        "ix_deployments_deployed_at", "deployments", ["deployed_at"], unique=False
    )
    op.create_index(
        "ix_deployments_environment", "deployments", ["environment"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_deployments_environment", table_name="deployments")
    op.drop_index("ix_deployments_deployed_at", table_name="deployments")
    op.drop_table("deployments")
