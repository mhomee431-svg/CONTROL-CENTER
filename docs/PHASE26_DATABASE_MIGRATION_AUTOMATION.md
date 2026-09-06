# PHASE 26 — Database Migration Automation

**Status:** Implemented — 2026-09
**Scope:** Every schema change travels through a version-controlled migration
pipeline — generate → review → test (rehearse, safety-scan) → staging →
production. No normal development ever requires manually editing a production
database table.

## 1. The workflow the phase automates

```
developer changes model/schema
      │
      ▼
python scripts/generate_migration.py -m "…"     ← creates alembic/versions/0016_….py
      │                                        (autogenerate diff vs the ORM,
      ▼                                          next sequential revision id)
review:  python scripts/migration_safety_check.py   ← DANGEROUS ops block auto-deploy
      │
      ▼
test:     CI integration job (every PR / push):
      │        alembic upgrade head        (forward migration rehearsal)
      │        verify_rds.py               (approved architecture surface)
      │        migration_rehearsal.py      (forward + rollback + data safety +
      │                                       index + FK + PostGIS, full chain)
      │        check_migration_drift.py   (ORM↔DB drift audit report)
      │        recovery_test.py            (backup/recovery drill — Phase 5)
      ▼
staging → production   (pipeline fires cicd_migrate.sh on the instance;
                            dangerous migrations stay gated on human approval)
```

## 2. The six verifications and how each is automated

| # | Requirement       | Static (no DB)                                    | Live (CI PostGIS service)                             |
|---|--------------------|-----------------------------------------------------|--------------------------------------------------------------|
| 1 | Forward migration  | chain is linear / single-head / sequential ids (test + rehearsal)                  | `alembic upgrade head` reaches the computed head revision|
| 2 | Rollback (where supported) | every `downgrade()` statically reverses its `upgrade()` (tables + indexes, incl. raw-SQL `CREATE INDEX`) | `downgrade -1` reverses the newest revision; `--full-chain-rollback` walks `downgrade base` and re-applies `upgrade head` from scratch|
| 3 | Data safety          | no `add_column(..., nullable=False)` without `server_default` (static policy scan)   | drill rows survive a `-1` downgrade → re-upgrade round-trip|
| 4 | Index creation        | —                                                          | representative btree / composite / GIN-trigram indexes exist after upgrade |
| 5 | Foreign keys          | —                                                          | FKs exist in `pg_constraint` AND an orphaned insert is rejected (enforcement) |
| 6 | PostGIS changes        | —                                                          | `postgis` extension installed; Geography columns typed; GiST indexes present |

All six run in CI on every PR/push (reusable-backend-checks → integration-tests) and
can be run locally:
```
DATABASE_URL=postgresql+asyncpg://… python scripts/migration_rehearsal.py --full-chain-rollback
python scripts/migration_rehearsal.py --chain-only        # static portion only
python scripts/check_migration_drift.py                    # ORM↔DB drift audit (report-only)
```

## 3. New tooling (Backend/scripts)

- **`migration_rehearsal.py`** — the centerpiece. Creates a *scratch* database on
  the same server (`hyperlocal_rehearsal_<ts>`, dropped at the end) so the
  *target* database is NEVER touched. Drills: chain integrity -> forward
  migration -> schema surface (tables, indexes, FKs, PostGIS, Geography, GiST)
  -> drill rows (positive FK path shops -> restaurants -> menu_categories) ->
  orphaned insert rejected (FK enforcement) -> `downgrade -1` (unrelated data
  survives) -> re-upgrade -> `--full-chain-rollback`: `downgrade base` ->
  `upgrade head` (the chain is fully reversible AND re-appliable). Emits
  `migration_rehearsal_report.json`.
- **`check_migration_drift.py`** — reflects the live DB and diffs it against
  `Base.metadata` (81 tables in this codebase). Detects the classic
  "model changed but no migration" defect (missing tables/columns,
  type-family, nullability). Report-only by default;
  `--fail-on-drift` makes it a hard gate.
- **`generate_migration.py`** — wraps `alembic revision --autogenerate` with the
  project conventions: next sequential revision id (`--rev-id 0016`),
  data-safety lint on the generated file, printed review checklist. Also
  supports `--no-autogenerate` (blank revision) and `--dry-run`.

## 4. Real defect found and fixed — migration 0002 rollback gap

The new downgrade-reversal verification (and the full-chain rollback drill)
caught a genuine hole: migration `0002` dropped the 0001-shaped `saved_products`
table during its upgrade and re-created it against `product_masters`, but its
`downgrade()` dropped the new version WITHOUT restoring the old shape.
Re-running `upgrade head` after a `downgrade base` therefore crashed at 0002's
`drop_table("saved_products")`. Fixed by restoring the 0001-shaped
`saved_products` (referencing `products`, plus its three indexes) in the `0002`
downgrade. The full chain is now genuinely reversible — and the rehearsal
proves it in CI on every push.

## 5. CI wiring

`reusable-backend-checks.yml` -> `integration-tests` (PostGIS 16 + Redis 7):

1. `alembic upgrade head`                                        (existing)
2. `python scripts/verify_rds.py`                                 (existing)
3. `python scripts/recovery_test.py`                              (existing)
4. `python scripts/migration_rehearsal.py --full-chain-rollback`  (NEW)
5. `python scripts/check_migration_drift.py`                      (NEW audit)
6. `python -m pytest -q … --maxfail=20`               (existing; now includes
      `tests/test_phase26_migration_automation.py`)
7. upload `phase26-migration-reports` artifact                    (NEW)

The Phase 25 CD pipeline already gates deploys on the static safety scan
(`migration_safety_check.py`; DANGEROUS => human approval required). The new
rehearsal + drift steps run in the same quality gate, so nothing reaches
staging/production unless every verification passes.

## 6. Pytest coverage (tests/test_phase26_migration_automation.py)

| Test                                                      | DB? |
|-----------------------------------------------------------|-----|
| chain is linear / single head / sequential ids             | no  |
| every revision defines `upgrade()` and `downgrade()`        | no  |
| `downgrade()` statically reverses its `upgrade()` surface  | no  |
| no silent NOT NULL column adds (data-safety policy)        | no  |
| generator computes the next revision id (0016)             | no  |
| drift checker self-consistent (ORM vs itself = zero drift) | no  |
| live DB is at the computed head                            | yes |
| live index / FK / PostGIS / Geography / GiST surface       | yes |
| tooling can reach the live DB                              | yes |

The live DB tests follow the repo's standard `requires_db` skip pattern. The
destructive round-trips never run against the shared test DB — they run on the
rehearsal's own scratch database (safe by construction).

## 7. Operator notes

- **Never edit production tables by hand.** The migration file IS the change;
  it travels through CI (rehearsal + safety scan), staging, production.
- To create a new migration: change the ORM model, then run
  `python scripts/generate_migration.py -m "<message>"`; review; commit together
  with the model change; CI proves every guarantee — a DANGEROUS op or a broken
  downgrade blocks the deploy until a human reviews it.
- The full-chain rollback drill double-checks every *legacy* downgrade too;
  if it ever surfaces an issue in an old revision (like the 0002 fix), fix the
  migration file. Alembic stores revision ids, not file hashes — amending an old
  migration only affects fresh databases/rehearsals, never an already-applied
  production database.
- Backups remain the ultimate safety net — the rehearsal proves rollback *where
  supported*; the Phase 5 Layer 1/2/3 restore paths cover everything else, and
  `cicd_migrate.sh` still takes a schema snapshot before applying in production.