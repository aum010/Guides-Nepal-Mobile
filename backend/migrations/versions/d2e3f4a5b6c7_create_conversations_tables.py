"""create_conversations_tables

Revision ID: d2e3f4a5b6c7
Revises: c9d3e4f5a6b7
Create Date: 2026-10-25 12:00:00.000000

"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "d2e3f4a5b6c7"
down_revision = "c9d3e4f5a6b7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Direct message threads: two users, canonical pair order, unique.
    op.create_table(
        "conversations",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_a_id", sa.Integer(), nullable=False),
        sa.Column("user_b_id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_a_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["user_b_id"], ["users.id"]),
        sa.UniqueConstraint("user_a_id", "user_b_id", name="uq_conversations_pair"),
    )
    op.create_index(op.f("ix_conversations_id"), "conversations", ["id"], unique=False)
    op.create_index(
        op.f("ix_conversations_user_a_id"), "conversations", ["user_a_id"], unique=False
    )
    op.create_index(
        op.f("ix_conversations_user_b_id"), "conversations", ["user_b_id"], unique=False
    )

    op.create_table(
        "messages",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("conversation_id", sa.Integer(), nullable=False),
        sa.Column("sender_id", sa.Integer(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=True
        ),
        sa.Column("read_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["conversation_id"], ["conversations.id"]),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"]),
    )
    op.create_index(op.f("ix_messages_id"), "messages", ["id"], unique=False)
    op.create_index(
        op.f("ix_messages_conversation_id"),
        "messages",
        ["conversation_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_messages_sender_id"), "messages", ["sender_id"], unique=False
    )
    op.create_index(
        op.f("ix_messages_created_at"), "messages", ["created_at"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_messages_created_at"), table_name="messages")
    op.drop_index(op.f("ix_messages_sender_id"), table_name="messages")
    op.drop_index(op.f("ix_messages_conversation_id"), table_name="messages")
    op.drop_index(op.f("ix_messages_id"), table_name="messages")
    op.drop_table("messages")
    op.drop_index(op.f("ix_conversations_user_b_id"), table_name="conversations")
    op.drop_index(op.f("ix_conversations_user_a_id"), table_name="conversations")
    op.drop_index(op.f("ix_conversations_id"), table_name="conversations")
    op.drop_table("conversations")
