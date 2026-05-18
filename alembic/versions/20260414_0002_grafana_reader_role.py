"""create grafana read-only role

Revision ID: 20260414_0002
Revises: 20260413_0001
Create Date: 2026-04-14 00:00:00.000000

"""

import os
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20260414_0002"
down_revision: Union[str, Sequence[str], None] = "20260413_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return

    role_name = os.getenv("GRAFANA_DB_USER", "grafana_reader")
    role_password = os.getenv("GRAFANA_DB_PASSWORD", "")
    role_name_ident = role_name.replace('"', '""')
    role_name_literal = role_name.replace("'", "''")

    if role_password:
        role_password_literal = role_password.replace("'", "''")
        op.execute(sa.text(f"""
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM pg_roles WHERE rolname = '{role_name_literal}'
                    ) THEN
                        EXECUTE 'CREATE ROLE "{role_name_ident}" LOGIN PASSWORD ''{role_password_literal}''';
                    ELSE
                        EXECUTE 'ALTER ROLE "{role_name_ident}" WITH LOGIN PASSWORD ''{role_password_literal}''';
                    END IF;
                END
                $$;
                """))
    else:
        op.execute(sa.text(f"""
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM pg_roles WHERE rolname = '{role_name_literal}'
                    ) THEN
                        EXECUTE 'CREATE ROLE "{role_name_ident}" LOGIN';
                    END IF;
                END
                $$;
                """))

    current_database = bind.execute(sa.text("SELECT current_database()"))
    db_name = str(current_database.scalar_one()).replace('"', '""')

    op.execute(sa.text(f'GRANT CONNECT ON DATABASE "{db_name}" TO "{role_name_ident}"'))
    op.execute(sa.text(f'GRANT USAGE ON SCHEMA public TO "{role_name_ident}"'))
    op.execute(sa.text(f'GRANT SELECT ON TABLE deployments TO "{role_name_ident}"'))
    op.execute(
        sa.text(
            f'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "{role_name_ident}"'
        )
    )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return

    role_name = os.getenv("GRAFANA_DB_USER", "grafana_reader")
    role_name_ident = role_name.replace('"', '""')

    op.execute(sa.text(f'REVOKE SELECT ON TABLE deployments FROM "{role_name_ident}"'))
    op.execute(
        sa.text(
            f'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM "{role_name_ident}"'
        )
    )

    if os.getenv("GRAFANA_DB_DROP_USER_ON_DOWNGRADE", "false").lower() == "true":
        op.execute(sa.text(f'DROP ROLE IF EXISTS "{role_name_ident}"'))
