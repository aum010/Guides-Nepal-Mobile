"""add bookmark experience_id

Bookmarks used to be a free-form ``{title, city, image, link}`` tuple, so
clients had to match a saved row back to an experience by the slug they had
written into ``link``. They can now carry the catalogue row's id; rows created
before this keep ``NULL`` and continue to match on ``link``.

Kept separate from the schema-alignment revision on purpose: that revision was
already stamped on databases, and editing an applied revision would leave them
silently one column behind.

Revision ID: e4a1f7b9c2d3
Revises: d60b8a8be10c
Create Date: 2026-10-27 08:40:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "e4a1f7b9c2d3"
down_revision: Union[str, Sequence[str], None] = "d60b8a8be10c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the experience back-reference to bookmarks."""
    op.add_column("bookmarks", sa.Column("experience_id", sa.Integer(), nullable=True))


def downgrade() -> None:
    """Remove the experience back-reference."""
    op.drop_column("bookmarks", "experience_id")
