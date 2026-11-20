"""add guide listing hero image

A published listing had no photo of its own, so every catalogue card fell back
to a stock photo chosen by category. Guides can now upload one
(``POST /guide/listings/{id}/photo``), stored as a path under ``/uploads``.
Nullable: an existing listing keeps the fallback until its guide adds a photo.

Revision ID: a4c6d8e0f2b4
Revises: f3b5c7d9e1a2
Create Date: 2026-10-31 01:10:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "a4c6d8e0f2b4"
down_revision: Union[str, Sequence[str], None] = "f3b5c7d9e1a2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the optional hero image column."""
    op.add_column("guide_listings", sa.Column("hero_image", sa.String(), nullable=True))


def downgrade() -> None:
    """Remove it."""
    op.drop_column("guide_listings", "hero_image")
