# Phase 4 — RDS PostgreSQL + PostGIS (Production Database)

**Status:** authored + statically validated in-repo (no live AWS/Docker in this
sandbox). Follows the same pattern as Phase 2 (IaC authored, applied on an
internet-connected machine with AWS access).

This phase provisions/operates the **production PostgreSQL** on **Amazon RDS**
with **PostGIS** and verifies the schema against the **approved architecture**.

---

## 1. Design decisions (aligned to the approved architecture)

- **Migrations already exist** (`Backend/alembic/versions/0001..0013`). We
  **never recreate the database** or hand-edit schema. The DB schema is the
  migration chain, and the approved architecture is encoded in
  `Backend/tests/test_database_schema.py` plus the migration sources.
- **PostGIS is enabled by migration `0002`** (`CREATE EXTENSION IF NOT EXISTS
  postgis`); `pg_trgm` is enabled by `0006`. PostGIS **Geography POINT** columns
  exist on `shops.location`, `customer_addresses.location`, and
  `search_indexes.location` (with a **GiST spatial index** on the search layer).
- **RDS is private**: no public subnet, app SG only, `rds.force_ssl=1`.
- **Connection string** is injected into ECS from Secrets Manager (never hand
  pasted, never committed).

Entity coverage (source of truth = migration chain; `scripts/verify_rds.py`
encodes the full list): `users`, `roles`, `permissions`, `role_permissions`,
`customers`, `customer_addresses`, `otps`, `user_interactions`, `shops`,
`shop_owners`, `shop_managers`,
`shop_addresses`, `shop_hours`, `shop_holidays`, `shop_documents`,
`shop_verifications`, `brands`, `categories`, `product_masters`,
`product_variants`, `product_images`, `product_attributes`,
`product_attribute_values`, `product_identifiers`, `barcode_relationships`,
`shop_products`, `inventory`, `inventory_movements`, `inventory_adjustments`,
`inventory_import_jobs`, `inventory_import_rows`, `price_history`, `offers`,
`offer_products`, `offer_conditions`, `search_history`, `search_events`,
`popular_searches`, `barcode_scans`, `search_indexes`,
`search_index_sync_runs`, `pos_integrations`, `pos_devices`, `pos_sync_jobs`,
`pos_sync_logs`, `pos_product_mappings`, `notifications`,
`notification_preferences`, `notification_deliveries`, `device_tokens`,
`admin_actions`, `admin_notes`, `product_approvals`, `reports`, `complaints`,
`audit_logs`, `product_views`, `shop_views`, `product_clicks`,
`inventory_events`, `system_metrics`, `analytics_events`,
`analytics_daily_aggregates`, `system_settings`, `feature_flags`,
`subscription_plans`, `subscriptions`, `payments`, `payment_events`,
`saved_products`, `saved_shops`.

The verifier also confirms the verified **enums**, **primary keys**, **foreign
keys**, **unique constraints**, **check constraints**, and **indexes** that the
approved architecture requires (timestamps `created_at`/`updated_at`, audit
fields, soft-delete flags, cascading behavior and transaction boundaries are
defined by the models/migrations and enforced by the migration chain).

---

## 2. RDS provisioning (Terraform)

`infra/terraform/rds.tf` provisions:

| Setting | Value | Notes |
|---------|-------|-------|
| engine | `postgres` `16.3` | PostGIS available via extension in migration |
| multi-AZ | `var.database_multi_az` | staging default off, prod on |
| storage | encrypted (SSE), 20 GB default | |
| backups | `backup_retention_days` (7), window 03:00–03:30 | automated snapshots + PITR |
| **deletion_protection** | true (default) | prevents accidental destroy |
| **auto_minor_version_upgrade** | true | keeps PG minor patched |
| **Performance Insights** | enabled, 7-day retention | |
| CloudWatch logs | `postgresql` export | error log audit |
| final snapshot | `skip_final_snapshot=false` | data preserved on destroy |
| SSL | `rds.force_ssl=1` | app connects `?sslmode=require` |

`random_password.master` seeds the admin password; the `DATABASE_URL` is written
to Secrets Manager (`…/database`) and injected into ECS — never stored in git.

### Provision

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply          # creates VPC/subnets/ECS/Redis/RDS/Secrets/S3
```

Apply the migration chain (idempotent, never recreates the DB):

```bash
aws ecs run-task --cluster <cluster> --task-definition <web_task> \
  --overrides '{"containerOverrides":[{"name":"api","command":["sh","-c","alembic upgrade head"]}]}'
```

Or use the safe workflow script (Section 4).

---

## 3. Verification (live)

Run the Phase 4 verifier against the live RDS instance, after every migration
and after every restore.

```bash
# From a machine/container with the backend venv:
DATABASE_URL='postgresql+asyncpg://hyperlocal:...@<rds-endpoint>:5432/hyperlocal?sslmode=require' \
  python Backend/scripts/verify_rds.py

# or from the backend directory (reads $DATABASE_URL / .env.production)
cd Backend && python scripts/verify_rds.py -v
```

It checks and **fails (exit 1)** if any of these is not true:

1. Database connection (`SELECT 1`).
2. **PostGIS** enabled (`PostGIS_Version()`).
3. **Migrations at HEAD** (`alembic_version == 0011`, no drift).
4. All approved **tables** + **enums** present.
5. **PK / FK / unique / check / index** integrity surface present.
6. **Geography columns** really typed `geography`.
7. **GiST spatial index** on the search layer.
8. Real **spatial queries**: `ST_Distance`, `ST_DWithin` and `ST_Within` plus a
   sample-data round-trip that is **rolled back** (safe, non-polluting).

DB-free structural checks are also in `Backend/tests/test_phase4_rds.py`
(run in CI without a database). The existing integration suite
`Backend/tests/test_database_schema.py` (`test_postgis_extension_enabled`,
`test_all_expected_tables_exist`, `test_expected_enums_exist`,
relationship/column tests) runs against the live DB and is the other half.

---

## 4. Safe migration workflow

`infra/scripts/rds_migrate.sh` implements the safe workflow:

1. (Optional) **pre-migration schema snapshot** via `pg_dump --schema-only`
   (upload to S3 if `SNAPSHOT_BUCKET` set).
2. **`alembic upgrade head`** — idempotent, never recreates the database.
3. **Runs `verify_rds.py`** and aborts (non-zero) if the DB no longer matches
   the approved architecture.

```bash
# in the backend container with the app venv:
DATABASE_URL='...' PGDUMP_URL='postgresql://...' ./infra/scripts/rds_migrate.sh
```

> The container `entrypoint.sh` already runs `alembic upgrade head` when
> `RUN_MIGRATIONS=true` (see `docker-compose.yml`), so a running ECS task migrates
> idempotently on boot. `rds_migrate.sh` adds the snapshot + post-checks for
> controlled/operator-driven deploys.

---

## 5. Backup configuration

- **Automated snapshots** (RDS native): retention 7 days, window 03:00–03:30
  UTC, enabling **point-in-time recovery** to any second within retention.
- **Manual snapshot before major migrations** so you can restore the exact
  pre-migration state:
  ```bash
  aws rds create-db-snapshot --db-instance-identifier hyperlocal-production-db \
     --db-snapshot-identifier hyperlocal-prod-pre-migrate-YYYYMMDD
  ```
- **Final snapshot on destroy**: `skip_final_snapshot=false` guarantees a
  `…-db-final` snapshot if the instance is ever removed.
- **Schema snapshots**: `rds_migrate.sh` optionally uploads `pg_dump
  --schema-only` to S3 (`SNAPSHOT_BUCKET`) for reversible schema history.
- **CloudWatch** exports the Postgres error log for auditing.

---

## 6. Restore procedure

`infra/scripts/rds_restore.sh <environment> <auto|manual|<snapshot-id>>`
implements the **safe** RDS restore path (snapshot → **new** instance → verify →
re-point → decommission):

```bash
./infra/scripts/rds_restore.sh production auto
# 1) resolves latest restorable time / snapshot
# 2) aws rds restore-db-instance-from-db-snapshot -> hyperlocal-production-db-restored-<ts>
# 3) waits for availability, prints the new endpoint
```

Then, manually:

```bash
# 1) Verify the restored DB first (never trust silently):
DATABASE_URL='postgresql+psycopg://<user>:<pw>@<restored-endpoint>:5432/hyperlocal?sslmode=require' \
  python Backend/scripts/verify_rds.py

# 2) Re-point the app by updating the DATABASE_URL secret:
aws secretsmanager update-secret --secret-id hyperlocal/production/database \
  --secret-string '{"DATABASE_URL":"postgresql+asyncpg://<user>:<pw>@<restored-endpoint>:5432/hyperlocal?sslmode=require"}'

# 3) Force a new ECS deployment so tasks pick up the new secret.
# 4) Only after the app is healthy, delete the old instance:
aws rds delete-db-instance --db-instance-identifier hyperlocal-production-db --region <region>
```

> Restoring creates a **new** instance and never overwrites the live one, so a
> restore is reversible and side-effect-safe.

---

## 7. Files added/changed (this phase)

| Path | Purpose |
|------|---------|
| `infra/terraform/rds.tf` | RDS hardening (deletion protection, auto minor upgrade, Performance Insights, log export) |
| `infra/terraform/variables.tf` | `database_deletion_protection` variable |
| `infra/terraform/outputs.tf` | `database_endpoint` / `database_name` / final-snapshot outputs |
| `infra/scripts/rds_migrate.sh` | Safe migration workflow (snapshot → migrate → verify) |
| `infra/scripts/rds_restore.sh` | Safe snapshot-restore procedure |
| `Backend/scripts/verify_rds.py` | Live PostGIS + architecture verifier (+ spatial sample, rolled back) |
| `Backend/tests/test_phase4_rds.py` | DB-free structural tests (chain, PostGIS, geography, verifier coverage) |
| `docs/PHASE4_RDS_POSTGRESQL_POSTGIS.md` | This runbook |

No database was recreated; the approved migration chain stays the source of truth.