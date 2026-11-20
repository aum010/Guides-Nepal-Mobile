"""publish guide listings

A guide's own listing was reachable only from its owner's dashboard: the public
catalogue served seeded content plus host experiences, and every booking was
routed to one hard-coded guide account. Published listings now appear in
``GET /experiences`` (``listing-<slug>``) and carry the guide who owns them
into the booking, so this revision adds what both need:

* ``guide_listings.slug`` — a stable URL segment, unique across the catalogue.
  Existing rows are backfilled from their id (unique by construction) because
  titles are not; new rows get a readable slug generated at create time.
* ``bookings.guide_listing_id`` — which listing a booking came from, so a
  cancellation can give the seats back.

Revision ID: f3b5c7d9e1a2
Revises: e4a1f7b9c2d3
Create Date: 2026-10-30 09:05:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "f3b5c7d9e1a2"
down_revision: Union[str, Sequence[str], None] = "e4a1f7b9c2d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the public slug and the booking back-reference."""
    # NOT NULL from the start with an empty default: SQLite cannot ALTER a
    # column to NOT NULL afterwards, and existing rows are filled by the UPDATE
    # below. The service always supplies a real slug; the empty default means a
    # row inserted behind its back collides on the unique index instead of
    # silently becoming unreachable.
    op.add_column(
        "guide_listings",
        sa.Column("slug", sa.String(), nullable=False, server_default=""),
    )
    op.execute(
        "UPDATE guide_listings "
        "SET slug = 'listing-' || CAST(id AS TEXT) "
        "WHERE slug IS NULL OR slug = ''"
    )
    op.create_index("ix_guide_listings_slug", "guide_listings", ["slug"], unique=True)

    op.add_column(
        "bookings", sa.Column("guide_listing_id", sa.Integer(), nullable=True)
    )
    op.create_index("ix_bookings_guide_listing_id", "bookings", ["guide_listing_id"])


def downgrade() -> None:
    """Drop both additions."""
    op.drop_index("ix_bookings_guide_listing_id", table_name="bookings")
    op.drop_column("bookings", "guide_listing_id")
    op.drop_index("ix_guide_listings_slug", table_name="guide_listings")
    op.drop_column("guide_listings", "slug")
