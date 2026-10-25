"""add_users_token_version

Revision ID: b8c2d3e4f5a6
Revises: a7b1c2d3e4f5
Create Date: 2026-10-23 22:10:00.000000

"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "b8c2d3e4f5a6"
down_revision = "a7b1c2d3e4f5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Counter compared against the `ver` claim of access tokens so ending a
    # session invalidates tokens that were already issued.
    op.add_column(
        "users",
        sa.Column("token_version", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("users", "token_version")
