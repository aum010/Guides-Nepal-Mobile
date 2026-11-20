"""Guard: a database built from migrations must be usable by the models.

The rest of the suite builds its schema with ``Base.metadata.create_all``, so a
migration that disagrees with the models — a renamed column, a table that was
never added — stays invisible to every other test while breaking any
environment provisioned with ``alembic upgrade head``.  This module runs the
real migration chain against a throwaway SQLite database and then checks the
models can select from every table.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from pytest import TempPathFactory
from sqlalchemy import Engine, create_engine, inspect

import app.models  # noqa: F401  (registers every model on Base.metadata)
from app.core.database import Base

BACKEND_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def migrated_database(tmp_path_factory: TempPathFactory) -> str:
    """Run ``alembic upgrade head`` against a fresh database; return its URL."""
    db_path = tmp_path_factory.mktemp("migrations") / "migrated.db"
    url = f"sqlite:///{db_path}"
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_ROOT,
        env={**os.environ, "DATABASE_URL": url},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        "alembic upgrade head failed:\n" f"{result.stdout}\n{result.stderr}"
    )
    return url


@pytest.fixture(scope="module")
def migrated_engine(migrated_database: str) -> Engine:
    """Engine pointed at the migrated database."""
    return create_engine(migrated_database)


def test_migrations_create_every_model_table(migrated_engine: Engine) -> None:
    """No model table may be missing from a freshly migrated database."""
    present = set(inspect(migrated_engine).get_table_names())
    missing = sorted(set(Base.metadata.tables) - present)
    assert missing == [], f"tables missing from migrations: {missing}"


def test_migrated_columns_match_the_models(migrated_engine: Engine) -> None:
    """Every column the ORM selects must exist after migrating."""
    inspector = inspect(migrated_engine)
    mismatches: dict[str, dict[str, list[str]]] = {}
    for table in sorted(Base.metadata.tables.values(), key=lambda item: item.name):
        db_columns = {column["name"] for column in inspector.get_columns(table.name)}
        expected = set(table.columns.keys())
        missing, extra = sorted(expected - db_columns), sorted(db_columns - expected)
        if missing or extra:
            mismatches[table.name] = {"missing": missing, "extra": extra}
    assert mismatches == {}, f"migrated schema differs from the models: {mismatches}"


def test_models_can_query_the_migrated_schema(migrated_engine: Engine) -> None:
    """Selecting from each table exercises every column the ORM declares."""
    failures: dict[str, str] = {}
    with migrated_engine.connect() as connection:
        for table in sorted(Base.metadata.tables.values(), key=lambda t: t.name):
            try:
                connection.execute(table.select().limit(1)).all()
            except Exception as exc:  # noqa: BLE001 - report every broken table
                failures[table.name] = f"{type(exc).__name__}: {exc}"
    assert failures == {}, f"tables the models cannot query: {failures}"
