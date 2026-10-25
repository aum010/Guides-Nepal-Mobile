"""create_revoked_tokens_table

Revision ID: a7b1c2d3e4f5
Revises: 6a3303359996
Create Date: 2026-10-23 21:40:00.000000

"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "a7b1c2d3e4f5"
down_revision = "6a3303359996"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Refresh tokens revoked at sign-out; `/auth/refresh` refuses these jtis.
    op.create_table(
        "revoked_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("jti", sa.String(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column(
            "revoked_at",
            sa.DateTime(),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_revoked_tokens_id"), "revoked_tokens", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_revoked_tokens_jti"), "revoked_tokens", ["jti"], unique=True
    )
    op.create_index(
        op.f("ix_revoked_tokens_expires_at"),
        "revoked_tokens",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_revoked_tokens_expires_at"), table_name="revoked_tokens")
    op.drop_index(op.f("ix_revoked_tokens_jti"), table_name="revoked_tokens")
    op.drop_index(op.f("ix_revoked_tokens_id"), table_name="revoked_tokens")
    op.drop_table("revoked_tokens")
