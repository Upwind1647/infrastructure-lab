from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import DateTime, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from db import Base


class DeploymentEvent(Base):
    __tablename__ = "deployments"
    __table_args__ = (
        UniqueConstraint(
            "git_sha",
            "environment",
            "status",
            "committed_at",
            name="uq_deployments_event",
        ),
        Index("ix_deployments_deployed_at", "deployed_at"),
        Index("ix_deployments_environment", "environment"),
    )

    id: Mapped[str] = mapped_column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid4()),
    )
    git_sha: Mapped[str] = mapped_column(String(40), nullable=False)
    environment: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    committed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    deployed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
