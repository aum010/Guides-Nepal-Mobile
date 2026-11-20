"""Startup must provision the schema from the migration chain.

``apply_schema`` is what the app runs on startup, so these tests pin the three
cases it has to get right: a fresh database, a database already at head, and a
database created by the app's former ``create_all`` path (which has tables but
no revision and must be adopted rather than re-created).
"""

from pathlib import Path

import pytest
from sqlalchemy import Engine, create_engine, inspect, text

import app.models  # noqa: F401  (registers every model on Base.metadata)
from app.core.database import Base
from app.core.schema import SchemaMismatchError, apply_schema, head_revision


@pytest.fixture
def database(tmp_path: Path) -> Engine:
    """A disposable SQLite database."""
    return create_engine(f"sqlite:///{tmp_path / 'startup.db'}")


def test_fresh_database_is_built_by_the_chain(database: Engine) -> None:
    assert apply_schema(database) == "upgraded"
    tables = set(inspect(database).get_table_names())
    assert set(Base.metadata.tables) <= tables
    with database.connect() as connection:
        version = connection.execute(text("SELECT version_num FROM alembic_version"))
        assert version.scalar() == head_revision()

    # A second startup must not re-run the chain.
    assert apply_schema(database) == "up-to-date"


def test_database_created_by_create_all_is_adopted(database: Engine) -> None:
    """Existing environments have every table but no revision row."""
    Base.metadata.create_all(bind=database)

    assert apply_schema(database) == "adopted"
    with database.connect() as connection:
        version = connection.execute(text("SELECT version_num FROM alembic_version"))
        assert version.scalar() == head_revision()
    assert apply_schema(database) == "up-to-date"


def test_adoption_adds_a_column_the_models_gained(database: Engine) -> None:
    """An environment one additive change behind must still be adopted."""
    Base.metadata.create_all(bind=database)
    with database.begin() as connection:
        connection.execute(text("ALTER TABLE bookmarks DROP COLUMN experience_id"))

    assert apply_schema(database) == "adopted"
    columns = {c["name"] for c in inspect(database).get_columns("bookmarks")}
    assert "experience_id" in columns


def test_stamped_database_that_is_behind_is_rejected(database: Engine) -> None:
    """Editing an applied revision leaves the stamp current but the schema old."""
    assert apply_schema(database) == "upgraded"
    with database.begin() as connection:
        connection.execute(text("ALTER TABLE bookmarks DROP COLUMN experience_id"))

    with pytest.raises(SchemaMismatchError):
        apply_schema(database)


def test_unversioned_database_that_disagrees_is_rejected(database: Engine) -> None:
    """Stamping an out-of-date database would skip the revisions that fix it."""
    with database.begin() as connection:
        connection.execute(
            text("CREATE TABLE users (id INTEGER PRIMARY KEY, email VARCHAR)")
        )

    with pytest.raises(SchemaMismatchError):
        apply_schema(database)


def test_a_schema_failure_stops_startup(monkeypatch) -> None:
    """Startup must not swallow a schema failure.

    Swallowing it is worse than crashing: the app used to boot, answer 200 on
    ``/health``, and then 500 on every query touching a missing column — which
    reads like an application bug rather than a database one.
    """
    import app.main as main

    def boom(_engine: Engine) -> str:
        raise SchemaMismatchError("column missing")

    monkeypatch.setattr(main, "apply_schema", boom)
    with pytest.raises(SchemaMismatchError):
        main.provision_schema()
