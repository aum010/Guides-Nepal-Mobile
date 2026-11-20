"""Apply the database schema by running the Alembic chain.

The app used to create its schema with ``Base.metadata.create_all`` at startup.
That worked, but it made two provisioning paths: a database built by the app
and one built by ``alembic upgrade head`` could disagree — and they did, which
is how ``users.first_name`` ended up in the migrations while the ORM selected
``users."firstName"``.

Migrations are now the only way the schema is created or changed:

* an empty database     → the whole chain runs;
* a database already stamped with a revision → only newer revisions run;
* a database built before migrations existed (the app's own ``create_all``
  output, and therefore every already-running environment) → it is adopted
  with ``alembic stamp head`` *only* if its columns already match the models,
  so an out-of-date database is reported instead of silently mis-stamped.
"""

import logging
from pathlib import Path
from typing import Callable

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import Engine, inspect, text

import app.models  # noqa: F401  (registers every model on Base.metadata)
from app.core.database import Base

logger = logging.getLogger(__name__)

BACKEND_ROOT = Path(__file__).resolve().parents[2]
ALEMBIC_INI = BACKEND_ROOT / "alembic.ini"


class SchemaMismatchError(RuntimeError):
    """A database has tables but no revision, and they disagree with the models."""


def _config() -> Config:
    return Config(str(ALEMBIC_INI))


def head_revision() -> str:
    """The revision this codebase expects."""
    head = ScriptDirectory.from_config(_config()).get_current_head()
    if head is None:
        raise RuntimeError("Alembic has no head revision")
    return str(head)


def _current_revision(engine: Engine) -> str | None:
    with engine.connect() as connection:
        row = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).first()
    return None if row is None else str(row[0])


def _add_missing_columns(engine: Engine) -> None:
    """Add columns the models declare but an unversioned database lacks.

    Only additive and safe cases are handled: a nullable column, or one with a
    default. Anything else needs a real revision, so it is reported instead of
    being guessed at.
    """
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())
    missing = [
        (table.name, column)
        for table in Base.metadata.tables.values()
        if table.name in existing_tables
        for column in table.columns
        if column.name not in {c["name"] for c in inspector.get_columns(table.name)}
    ]
    for table_name, column in missing:
        if (
            not column.nullable
            and column.default is None
            and column.server_default is None
        ):
            raise SchemaMismatchError(
                f"{table_name}.{column.name} is required but missing, and cannot "
                "be added automatically. Run `alembic upgrade head` manually "
                "(see DATABASE_MIGRATION.md)."
            )
        column_type = column.type.compile(dialect=engine.dialect)
        clause = "" if column.nullable else " NOT NULL"
        if column.server_default is not None:
            clause += f" DEFAULT {column.server_default.arg}"
        with engine.begin() as connection:
            connection.execute(
                text(
                    f'ALTER TABLE {table_name} ADD COLUMN "{column.name}" {column_type}{clause}'
                )
            )
        logger.info("Added missing column %s.%s", table_name, column.name)


def schema_matches_models(engine: Engine) -> bool:
    """True when every model table and column exists in the database."""
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    for table in Base.metadata.tables.values():
        if table.name not in tables:
            return False
        present = {column["name"] for column in inspector.get_columns(table.name)}
        if set(table.columns.keys()) - present:
            return False
    return True


def _run(
    config: Config, engine: Engine, operation: Callable[..., None], revision: str
) -> None:
    """Run an Alembic command against this engine's own connection."""
    with engine.begin() as connection:
        config.attributes["connection"] = connection
        operation(config, revision)


def apply_schema(engine: Engine) -> str:
    """Bring the database to ``head``; returns what was done.

    Returns ``"upgraded"``, ``"adopted"`` or ``"up-to-date"``.
    """
    config = _config()
    head = head_revision()
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    if "alembic_version" in tables:
        if _current_revision(engine) == head:
            # A revision that was edited after being applied leaves the stamp
            # looking current while the schema is behind. Say so instead of
            # booting an app that will fail every query.
            if not schema_matches_models(engine):
                raise SchemaMismatchError(
                    "Database is stamped at the head revision but its columns do "
                    "not match the models — an already-applied revision was "
                    "probably edited. Put the change in a new revision "
                    "(see DATABASE_MIGRATION.md)."
                )
            return "up-to-date"
    elif tables & set(Base.metadata.tables):
        # Tables without a revision: the database was created by the app's
        # former ``create_all`` path.  Bring it up to the models with additive
        # changes only (new tables, safely-added columns), then adopt it, so
        # existing environments join the chain instead of being re-created.
        Base.metadata.create_all(bind=engine)
        _add_missing_columns(engine)
        if not schema_matches_models(engine):
            raise SchemaMismatchError(
                "Database has tables but no alembic_version, and its columns do "
                "not match the models. Run `alembic upgrade head` against it "
                "manually (see DATABASE_MIGRATION.md)."
            )
        _run(config, engine, command.stamp, "head")
        return "adopted"

    _run(config, engine, command.upgrade, "head")
    return "upgraded"
