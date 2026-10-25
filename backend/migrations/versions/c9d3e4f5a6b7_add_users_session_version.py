"""add_users_session_version

Revision ID: c9d3e4f5a6b7
Revises: b8c2d3e4f5a6
Create Date: 2026-10-23 22:25:00.000000

"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "c9d3e4f5a6b7"
down_revision = "b8c2d3e4f5a6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Compared against the `sver` claim of refresh tokens; bumped by
    # "sign out everywhere" so no previously issued refresh token can be
    # exchanged again.
    op.add_column(
        "users",
        sa.Column("session_version", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("users", "session_version")
