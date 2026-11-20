"""align schema with the ORM models

The migration history had drifted behind the models: six tables the
application queries had no revision at all, ``bookmarks`` and ``guides`` were
missing columns the ORM selects, and ``host_experiences`` still carried its
pre-rename shape (``host_user_id`` / ``max_guests``).  A database built with
``alembic upgrade head`` therefore could not serve the app, even though a
database built by ``Base.metadata.create_all`` — the startup path, and so
every existing environment — matched the models exactly.

This revision closes that gap and deliberately changes nothing else: it
creates the missing tables, adds the missing columns, and *renames*
``host_user_id`` to ``host_id`` so existing rows survive.

Revision ID: d60b8a8be10c
Revises: d2e3f4a5b6c7
Create Date: 2026-10-27 07:14:26.851470

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "d60b8a8be10c"
down_revision: Union[str, Sequence[str], None] = "d2e3f4a5b6c7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _timestamps() -> list:
    """The ``created_at`` / ``updated_at`` pair every model declares."""
    return [
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    ]


def upgrade() -> None:
    """Create the tables and columns the ORM needs."""
    op.create_table(
        "guide_applications",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("full_name", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column("city", sa.String(), nullable=True),
        sa.Column("region", sa.String(), nullable=True),
        sa.Column("nin_number", sa.String(), nullable=True),
        sa.Column("documents", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=True),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_guide_applications_id", "guide_applications", ["id"])
    op.create_index("ix_guide_applications_email", "guide_applications", ["email"])

    op.create_table(
        "host_applications",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("host_name", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("city", sa.String(), nullable=True),
        sa.Column("region", sa.String(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column("experience", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=True),
        sa.Column("credential_token_hash", sa.String(), nullable=True),
        sa.Column("credential_password_hash", sa.String(), nullable=True),
        sa.Column("details_json", sa.Text(), nullable=True),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("reviewed_by", sa.String(), nullable=True),
        sa.Column("review_note", sa.String(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_host_applications_id", "host_applications", ["id"])
    op.create_index("ix_host_applications_email", "host_applications", ["email"])

    op.create_table(
        "support_tickets",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subject", sa.String(), nullable=True),
        sa.Column("description", sa.String(), nullable=True),
        sa.Column("customer_name", sa.String(), nullable=True),
        sa.Column("customer_email", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=True),
        sa.Column("priority", sa.String(), nullable=True),
        sa.Column("assigned_to", sa.String(), nullable=True),
        sa.Column("resolution", sa.String(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_support_tickets_id", "support_tickets", ["id"])
    op.create_index(
        "ix_support_tickets_customer_email", "support_tickets", ["customer_email"]
    )

    op.create_table(
        "reviews",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id", "experience_id", name="uq_review_user_experience"
        ),
    )
    op.create_index("ix_reviews_id", "reviews", ["id"])
    op.create_index("ix_reviews_experience_id", "reviews", ["experience_id"])
    op.create_index("ix_reviews_user_id", "reviews", ["user_id"])

    op.create_table(
        "host_tours",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("host_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("city", sa.String(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("itinerary", sa.Text(), nullable=False),
        sa.Column("meeting_point", sa.String(), nullable=False),
        sa.Column("duration", sa.String(), nullable=False),
        sa.Column("difficulty", sa.String(), nullable=False),
        sa.Column("max_guests", sa.Integer(), nullable=False),
        sa.Column("price", sa.Float(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["host_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_host_tours_id", "host_tours", ["id"])
    op.create_index("ix_host_tours_host_id", "host_tours", ["host_id"])

    op.create_table(
        "host_bookings",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("host_id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=False),
        sa.Column("guest_name", sa.String(), nullable=False),
        sa.Column("guest_email", sa.String(), nullable=False),
        sa.Column("guest_phone", sa.String(), nullable=True),
        sa.Column("date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("guests", sa.Integer(), nullable=False),
        sa.Column("total_price", sa.Float(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["experience_id"], ["host_experiences.id"]),
        sa.ForeignKeyConstraint(["host_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_host_bookings_id", "host_bookings", ["id"])
    op.create_index("ix_host_bookings_host_id", "host_bookings", ["host_id"])
    op.create_index(
        "ix_host_bookings_experience_id", "host_bookings", ["experience_id"]
    )
    op.create_index("ix_host_bookings_status", "host_bookings", ["status"])

    # Columns the ORM selects that no revision had created yet.
    op.add_column(
        "bookmarks",
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
    )
    op.add_column("guides", sa.Column("verified", sa.Boolean(), nullable=True))
    op.add_column("guides", sa.Column("lives_in", sa.String(), nullable=True))

    # Indexes the models declare (``index=True``) that no revision had created.
    op.create_index("ix_guide_profiles_id", "guide_profiles", ["id"])
    op.create_index(
        "ix_guide_status_updates_listing_id", "guide_status_updates", ["listing_id"]
    )

    # `host_experiences` was created before the model was finalised: the host
    # column was renamed and the experience gained a slug, duration and hero
    # image.  Rename rather than drop so migrated rows keep their owner.
    op.drop_index("ix_host_experiences_host_user_id", table_name="host_experiences")
    with op.batch_alter_table("host_experiences") as batch_op:
        batch_op.alter_column(
            "host_user_id",
            new_column_name="host_id",
            existing_type=sa.Integer(),
            existing_nullable=False,
        )
        # NOT NULL with an empty default keeps this runnable on a table that
        # already has rows; every writer supplies a real value.
        batch_op.add_column(
            sa.Column("slug", sa.String(), nullable=False, server_default="")
        )
        batch_op.add_column(
            sa.Column("duration", sa.String(), nullable=False, server_default="")
        )
        batch_op.add_column(sa.Column("hero_image", sa.String(), nullable=True))
        batch_op.drop_column("max_guests")
    op.create_index("ix_host_experiences_host_id", "host_experiences", ["host_id"])
    op.create_index("ix_host_experiences_slug", "host_experiences", ["slug"])


def downgrade() -> None:
    """Undo the alignment, returning the pre-models schema."""
    op.drop_index("ix_host_experiences_slug", table_name="host_experiences")
    op.drop_index("ix_host_experiences_host_id", table_name="host_experiences")
    with op.batch_alter_table("host_experiences") as batch_op:
        batch_op.add_column(
            sa.Column("max_guests", sa.Integer(), nullable=False, server_default="10")
        )
        batch_op.drop_column("hero_image")
        batch_op.drop_column("duration")
        batch_op.drop_column("slug")
        batch_op.alter_column(
            "host_id",
            new_column_name="host_user_id",
            existing_type=sa.Integer(),
            existing_nullable=False,
        )
    op.create_index(
        "ix_host_experiences_host_user_id", "host_experiences", ["host_user_id"]
    )

    op.drop_index(
        "ix_guide_status_updates_listing_id", table_name="guide_status_updates"
    )
    op.drop_index("ix_guide_profiles_id", table_name="guide_profiles")
    op.drop_column("guides", "lives_in")
    op.drop_column("guides", "verified")
    op.drop_column("bookmarks", "created_at")

    op.drop_index("ix_host_bookings_status", table_name="host_bookings")
    op.drop_index("ix_host_bookings_experience_id", table_name="host_bookings")
    op.drop_index("ix_host_bookings_host_id", table_name="host_bookings")
    op.drop_index("ix_host_bookings_id", table_name="host_bookings")
    op.drop_table("host_bookings")

    op.drop_index("ix_host_tours_host_id", table_name="host_tours")
    op.drop_index("ix_host_tours_id", table_name="host_tours")
    op.drop_table("host_tours")

    op.drop_index("ix_reviews_user_id", table_name="reviews")
    op.drop_index("ix_reviews_experience_id", table_name="reviews")
    op.drop_index("ix_reviews_id", table_name="reviews")
    op.drop_table("reviews")

    op.drop_index("ix_support_tickets_customer_email", table_name="support_tickets")
    op.drop_index("ix_support_tickets_id", table_name="support_tickets")
    op.drop_table("support_tickets")

    op.drop_index("ix_host_applications_email", table_name="host_applications")
    op.drop_index("ix_host_applications_id", table_name="host_applications")
    op.drop_table("host_applications")

    op.drop_index("ix_guide_applications_email", table_name="guide_applications")
    op.drop_index("ix_guide_applications_id", table_name="guide_applications")
    op.drop_table("guide_applications")
