# DATABASE MIGRATION — Guides Nepal

**Version:** 1.0 · **Date:** 2026-10-18

---

## 1. MIGRATION STRATEGY

### 1.1 Fresh PostgreSQL database

alembic upgrade head

This creates all tables, indexes, constraints, and defaults from the revision chain.

### 1.2 Existing SQLite database to PostgreSQL

Data migration is not required for the core application because:
- The current seed data lives in seed scripts, not in a persistent SQLite database.
- The bookings table and other core tables are created on first app run.
- Historical data (if any) should be exported from SQLite and imported via SQL.

Procedure:
1. Back up the SQLite database.
2. Export tables to SQL (using sqlite3 .dump or pgloader).
3. Restore the SQL dump into the PostgreSQL database.
4. Verify row counts.
5. Disable seed scripts and run alembic upgrade head.

### 1.3 Existing database that was created by the app

Databases created before migrations were enforced have every table but no
`alembic_version` row, so `alembic upgrade head` would try to re-create them.
Startup handles this: `app.core.schema.apply_schema()` creates any missing
tables, adds missing *additive* columns (nullable, or with a default), then
stamps the database at head. Nothing is dropped, and a change that cannot be
made additively fails loudly with `SchemaMismatchError` instead of being
guessed at — that case needs a real revision and a manual `upgrade head`.

To do it by hand instead:

1. `python scripts/compare_schema.py` — must report `0 table(s) with column
   mismatches` (that means the database already equals the models).
2. `alembic stamp head` — records the current revision without running DDL.

From then on the normal `upgrade head` path applies.

### 1.5 A revision that failed half way (SQLite)

SQLite runs DDL outside a transaction, so a revision that fails part way
through leaves the earlier statements applied while `alembic_version` still
points at the previous revision. The next `upgrade head` then fails on
already-existing objects (`duplicate column name: …`).

Startup is fatal on a schema failure precisely so this cannot pass unnoticed —
the app refuses to serve requests that would 500 on a missing column.

To recover, compare the database with the revision and undo the partial work
before retrying. For the reflective version of this, run
`python scripts/compare_schema.py` and read the SQL Alembic suggested:

1. Drop the objects the failed revision already created (e.g.
   `ALTER TABLE guide_listings DROP COLUMN slug`).
2. `alembic current` — still the previous revision.
3. `alembic upgrade head` — re-runs the whole revision cleanly.

Never `alembic stamp head` a database that is missing part of a revision; the
startup guard will detect the mismatch and refuse to boot.

### 1.4 Migration verification

- Verify with alembic current (should show the head revision).
- Verify with alembic history (should show the full chain).
- `python scripts/compare_schema.py` — the migrated schema must match the ORM
  metadata exactly.  `tests/test_migrations.py` runs the whole chain against a
  throwaway database and fails if any model table or column is missing, so
  drift is caught by `pytest` rather than by a broken deployment.
- Run pytest for integration tests.
- Inspect pg_dump output to confirm constraints and indexes were created.

---

## 2. REVISION HISTORY

| Revision | File | Description |
|---|---|---|
| 5da9b06e2e4f | create_users_table.py | Rewritten: creates users table (portable) |
| ff8b527a0b00 | create_bookings_table.py | Rewritten: creates bookings table (portable) |
| 3f4a5b6c7d8e | create_guides_table.py | Rewritten: creates guides table (portable) |
| c8e1f2a3b4c5 | create_experience_workflow_tables.py | Creates experience_proposals + experience_change_requests |
| d4e5f6a7b8c9 | create_host_guide_tables.py | Creates host_guides + host_experience_guides |
| d60b8a8be10c | align_schema_with_orm_models.py | Adds the six tables and the columns the history never created; renames `host_experiences.host_user_id` to `host_id` |
| e4a1f7b9c2d3 | add_bookmark_experience_id.py | `bookmarks.experience_id`, so a save resolves back to its catalogue row |
| f3b5c7d9e1a2 | publish_guide_listings.py | `guide_listings.slug` (unique, backfilled from the id) and `bookings.guide_listing_id` |
| a4c6d8e0f2b4 | add_guide_listing_hero_image.py | `guide_listings.hero_image` (nullable path under `/uploads`) |

---

## 3. CORRECTIVE REVISION NAMING

The historical revisions are kept with their original IDs (never reused). New
corrective revisions are named with a clear fix_<issue> slug:

- fix_users_bookings_migrations — rewrites empty revisions into real DDL.
- fix_guides_portable_json — removes PostgreSQL-only postgresql.JSONB from the
guides migration.
- fix_booking_constraints — adds CHECK constraints to bookings and guide_listings.
- fix_add_indexes — adds recommended indexes.

---

## 4. DATA MIGRATION (COPY RECOVERY)

If data must be retained from SQLite to PostgreSQL:

sqlite3 guides_nepal.db .dump > sqlite_dump.sql
psql -h localhost -U postgres -d guides_nepal < sqlite_dump.sql

Then verify counts and constraints.

**Rollback:** Drop the PostgreSQL database and restore from backup. Never attempt
to roll back a data migration via alembic downgrade.

---

## 5. MIGRATION RISK REGISTER

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Migration history currently broken | High | High | Rewrite empty revisions first |
| PostgreSQL JSONB divergence | Medium | High | Use portable JSONB / portable types in shared migrations |
| Data loss during SQLite->PG migration | Medium | High | Back up SQLite first; verify row counts |
| Constraint violation on capacity | Low | High | Add CHECK constraints; test with generated data |
| Float rounding drift on money | Medium | Low | Use NUMERIC(12,2) for new monetary columns |
