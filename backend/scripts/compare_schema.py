"""Compare the live SQLite schema against the SQLAlchemy ORM metadata.

Reports, per table, any column the ORM expects but the database lacks, and
any column the database has that the ORM does not declare.  Used to verify
that a freshly migrated local database matches ``Base.metadata`` exactly.
"""

import sys
from pathlib import Path

# Allow running this file directly (``python scripts/compare_schema.py``) from
# the backend root by putting the backend directory on ``sys.path``.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from sqlalchemy import inspect  # noqa: E402

import app.models  # noqa: E402,F401  (registers every model on Base.metadata)
from app.core.database import Base, engine  # noqa: E402


def main() -> int:
    inspector = inspect(engine)
    db_tables = set(inspector.get_table_names())
    orm_tables = set(Base.metadata.tables.keys())

    print(f"database: {engine.url}")
    print(f"tables in database : {len(db_tables)}")
    print(f"tables in ORM      : {len(orm_tables)}")

    only_db = sorted(db_tables - orm_tables)
    only_orm = sorted(orm_tables - db_tables)
    if only_db:
        print(f"\nTABLES ONLY IN DATABASE: {only_db}")
    if only_orm:
        print(f"\nTABLES ONLY IN ORM: {only_orm}")

    mismatches = 0
    for table in sorted(orm_tables & db_tables):
        db_cols = {c["name"] for c in inspector.get_columns(table)}
        orm_cols = set(Base.metadata.tables[table].columns.keys())
        missing = orm_cols - db_cols
        extra = db_cols - orm_cols
        if missing or extra:
            mismatches += 1
            print(f"\n[{table}]")
            if missing:
                print(f"  MISSING in database: {sorted(missing)}")
            if extra:
                print(f"  EXTRA in database  : {sorted(extra)}")

    print()
    if mismatches == 0 and not only_db and not only_orm:
        print("RESULT: schema matches ORM metadata exactly.")
        return 0
    print(f"RESULT: {mismatches} table(s) with column mismatches.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
