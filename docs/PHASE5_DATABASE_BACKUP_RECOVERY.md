# Phase 5 — Database Backup & Recovery

**Status:** implemented. **Recovery was tested for real** — see the "Recovery
test performed" section for the actual `PASS` result against a running
PostgreSQL 16.4.

This phase makes the database **backed up, restorable, and verifiably
recoverable**, with a migration rollback strategy. It does **not** claim any of
this works on faith: the automated CI drill and the local provisioned-Postgres
run restore a backup into a fresh database and prove the restored DB matches
the source (revision, tables, row counts, schema surface).

---

## 1. Two independent backup layers

### Layer A — RDS-native automated snapshots + point-in-time recovery (PITR)

`infra/terraform/rds.tf` now enables:

| Setting | Value | Effect |
|---|---|---|
| `backup_retention_period` | `7` days | Automated daily snapshots (RDS free tier ≈ 0–20 GB) |
| `backup_window` | `03:00–03:30 UTC` | Predictable maintenance window |
| PITR | enabled (implied ≤ 7-day retention) | Restore **to any second** in the window via `restore-db-instance-to-point-in-time` |
| `skip_final_snapshot` | `false` | A final `…-db-final` snapshot is always taken on destroy |
| `final_snapshot_identifier` | `<prefix>-db-final` | Recoverable last-known-good state |
| `delete_automated_backups` | `false` | Backups survive instance deletion |
| `deletion_protection` | `true` | Prevents accidental destructive `terraform destroy` |

This is the **layer-2** restore path: `infra/scripts/rds_restore.sh <env> auto`
restores the latest restorable time into a **new** instance (never touching the
live one) → verify → re-point → decommission.

### Layer B — Logical `pg_dump` backups + S3 DR copy (application-level)

`infra/scripts/backup_db.sh` produces a verifiable logical backup set:

```
<prefix>_<env>_<timestamp>.pgc           pg_dump -Fc  (schema + data)
<prefix>_<env>_<timestamp>.schema.sql    pg_dump --schema-only
<prefix>_<env>_<timestamp>.manifest.json revision + per-table row counts
```

Backups are scheduled automatically with `infra/scripts/install_backup_cron.sh`
(a **systemd timer** at 02:30 UTC, catches up after reboot) and optionally
copied to the dedicated **S3 backups bucket** (`infra/terraform/backups.tf`,
private, TLS-only, with a **retention lifecycle**: `daily/` 30 days, `monthly/`
365 days). A logical backup restore does not depend on RDS or on any single
machine, so it is the **layer-1** restore path.

---

## 2. Retention

| Backup type | Where | Retention |
|---|---|---|
| RDS automated snapshots / PITR | AWS RDS | 7 days (`backup_retention_period`) |
| Daily logical `pg_dump` | `<BACKUP_DIR>` (`/var/backups/hyperlocal`) | pruned after `RETENTION_DAYS` (default 7; `0`=keep) |
| Daily logical `pg_dump` | S3 `daily/<yyyy/mm/dd>/` | 30 days (lifecycle rule) |
| Monthly logical `pg_dump` | S3 `monthly/<yyyy/mm/dd>/` | 365 days (lifecycle rule) |
| Manual RDS snapshot (`backup_db.sh … --mode snapshot`) | AWS RDS | kept until manually deleted (pre-migration baseline) |

---

## 3. Restore / recovery procedure

### Layer 1 — Logical restore (preferred for exact point-in-time via dumps)

```bash
# 1) Take a backup
./infra/scripts/backup_db.sh production            # logical dump + manifest
# 2) Restore + verify (--replace safety-dumps the current DB first)
./infra/scripts/restore_db.sh production <backup>.pgc \
    --target 'postgresql+asyncpg://user:pass@host:5432/hyperlocal' --replace \
    --verify-architecture
```

`restore_db.sh` never trusts the restore: it **verifies** the restored
database against the manifest — alembic revision, every table's row count, and
optionally the approved architecture via `scripts/verify_rds.py` — and exits
non-zero if anything differs.

### Layer 2 — RDS snapshot / PITR restore

```bash
./infra/scripts/rds_restore.sh production auto     # PITR to latest restorable
./infra/scripts/rds_restore.sh production manual   # latest manual snapshot
./infra/scripts/rds_restore.sh production <snapshot-id>
```

Restores into a **new** instance, then (manually) verify with `verify_rds.py`,
re-point `DATABASE_URL`, then decommission the old instance.

### Layer 3 — Migration rollback (schema-only, AWS-native)

```bash
DATABASE_URL='postgresql+asyncpg://...' ./infra/scripts/rds_migrate_rollback.sh [--steps N]
```

Every migration (`0001`…`0013`) ships a real `downgrade()`. `rds_migrate_rollback.sh`
refuses to run below `0001`, checks a backup safety net exists
(RDS automated backups on / manual snapshot taken), runs `alembic downgrade -N`,
then re-verifies with `verify_rds.py`.

> The migration rollback strategy is **3 layered**: (1) restore the logical
> backup; (2) restore an RDS snapshot/PITR; (3) `alembic downgrade` for
> schema-only changes where data preservation plus verification is sufficient.

---

## 4. Recovery test — performed and PASSING

Recovery was **actually exercised**, not assumed:

1. Booted a real **PostgreSQL 16.4** and created a `hyperlocal` database with a
   realistic schema mirroring the app (17 tables, enums, FKs, indexes, and an
   `alembic_version` row at `0013`).
2. Ran the automated drill `Backend/scripts/recovery_test.py` against it:
   `pg_dump -Fc` → create a scratch DB → `pg_restore` → verify → drop scratch.
   Result: **4/4 checks PASSED** (revision, table set, row counts, schema
   surface) → `"result": "PASS"`, report written to `recovery_report.json`.
3. Ran the operator scripts end-to-end:
   - `backup_db.sh test` → produced `.pgc` + `.schema.sql` + `.manifest.json`
     (revision `0013`, all 17 tables, sha256).
   - `restore_db.sh test <backup>.pgc --target … --replace` → safety-dumped the
     current DB, recreated it, `pg_restore`, then **verified revision `0013`
     and all 17 per-table row counts** → `OK restore complete and VERIFIED`.
4. Confirmed the destructive restore left a healthy, queryable database.

The same drill runs automatically on **CI** via
`.github/workflows/db-backup-recovery-test.yml`, which:
- boots a real `postgis/postgis:16-3.4` service,
- runs `alembic upgrade head` (the full real migration chain),
- runs `scripts/recovery_test.py` **and fails the build if any check fails**
  (no `|| true` — this is the point of the drill).

---

## 5. Files added / changed

| Path | Purpose |
|---|---|
| `infra/terraform/rds.tf` | Enable automated backups (7d), backup window, PITR, final snapshot, deletion protection |
| `infra/terraform/backups.tf` | New private S3 backups bucket + lifecycle retention (daily 30d / monthly 365d) |
| `infra/terraform/ec2.tf` | Least-privilege S3 read/write on the backup bucket |
| `infra/terraform/outputs.tf` | `backup_bucket_name` output |
| `infra/scripts/backup_db.sh` | Logical backup + manifest (+ S3 DR copy, + manual RDS snapshot mode) |
| `infra/scripts/restore_db.sh` | Verified restore with safety dump + row-count/revision verification |
| `infra/scripts/install_backup_cron.sh` | Automated daily backup via systemd timer |
| `infra/scripts/rds_migrate_rollback.sh` | Safe Alembic downgrade with backup safety-net + re-verify |
| `Backend/scripts/recovery_test.py` | Automated non-destructive recovery drill (dump→restore→verify) |
| `.github/workflows/db-backup-recovery-test.yml` | CI recovery drill against a real PostGIS service |
| `Backend/tests/test_phase5_backup_recovery.py` | DB-free structural checks (downgrade present, chain linear, script coverage) |
| `docs/PHASE5_DATABASE_BACKUP_RECOVERY.md` | This runbook |

## 6. Operational notes / limitations

- **Apply via Terraform:** `terraform -chdir=infra/terraform plan && apply` to
  enable RDS backups on the live instance (a no-downtime modify).
- **Scheduling:** install `install_backup_cron.sh` on the EC2 (or the DB host)
  to automate the logical backup; wire the S3 bucket name from the
  `backup_bucket_name` output into `BACKUP_BUCKET`.
- The local drill used a schema stand-in because PostGIS binaries aren't
  bundled; the **full** PostGIS migration chain is what CI exercises. The
  recovery mechanics (pg_dump / pg_restore / verification) are identical and
  proven.

