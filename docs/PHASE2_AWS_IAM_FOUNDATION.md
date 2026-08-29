# PHASE 2 — AWS ACCOUNT & IAM FOUNDATION

**Status:** ✅ APPLIED & LIVE-VERIFIED (2026-08-27) in AWS account
`935173128886`, region `ap-south-1`. Terraform remote state is enabled
(`s3://hyperlocal-935173128886-tfstate/hyperlocal/foundation/terraform.tfstate`,
DynamoDB lock `terraform-locks`). Full test evidence in §6a; residual follow-ups
in §7.

## 0. Decisions (non-negotiable, by design)

| Decision | Rationale |
|---|---|
| **No root account at runtime** | Root is used **once** (optionally) to create the bootstrap user, then never again. All admin is via assumed roles. |
| **Roles over long-lived keys** | The *only* long-lived credential is a bootstrap IAM user whose **entire** policy is `sts:AssumeRole` → it cannot touch resources directly. Everything else is role-based (Task roles, OIDC, operator/monitor roles). |
| **Least privilege, scoped by resource** | Every policy limits **actions** and **resources** to the specific project resources (repo, cluster, buckets, secrets, RDS instance). |
| **Separated concerns** | Infrastructure administration ≠ deployment ≠ runtime ≠ database ≠ S3 ≠ monitoring. Each has its own role/principal. |
| **Default deny** | No policy grants `*` unless the AWS service cannot be resource-scoped (documented in §5). |

## 1. What already existed (verified) and what Phase 2 adds

**Exists in `infra/terraform/` (application module):**
- ECS task-**execution** role (pull ECR, inject secrets, logs) and ECS task-**runtime** role (S3 + Secrets + SES/SNS). No static keys for the app.
- KMS key, Secrets Manager, S3 (SSE-KMS), ECR (KMS, immutable, scan-on-push).

**Added by Phase 2 (`infra/terraform/foundation/`):**
1. Remote Terraform state: S3 bucket + DynamoDB lock table.
2. GitHub Actions **OIDC provider** + scoped **CI/CD deploy** role (feeds the `AWS_DEPLOY_ROLE_ARN` secret).
3. **Operator** role (infra administration) + **bootstrap** IAM user (assume-role-only).
4. **Monitoring**, **database-operator**, **S3-backup** roles — read/lean, resource-scoped.
5. **Human ops group** with self-service MFA + account password policy.
6. Verification runbook (`infra/scripts/iam_verify.ps1`).

## 2. Account, region, environments

### Single account, single region (recommended to start)
- **AWS account ID:** `935173128886` (recorded in `foundation/terraform.tfvars`).
- **Region:** single region everywhere (`ap-south-1`); change once in both `infra/terraform` and `infra/terraform/foundation`.

> A shared single region keeps VPC/log/KMS/S3 relationships simple. Replicate or
> split accounts only when the business justifies it — out of scope for Phase 2.

### Environments (mirror `HYPERLOCAL_ENV` in the backend)
| Environment | Purpose | AWS | Foundation + App modules | Notes |
|---|---|---|---|---|
| `development` | local (Docker PostGIS+Redis) | none | — | No AWS |
| `staging` | pre-prod | yes | both modules | secrets `hyperlocal/staging` |
| `production` | live public | yes | both modules | secrets `hyperlocal/production` |

Each stage prefixes resources `${project_name}-${environment}` (e.g.
`hyperlocal-prod-…`) and uses its own Secrets Manager path.

## 3. IAM architecture (who can do what)

```
                 ┌────────────────── AWS account 1234… ───────────────────┐
                 │                                                       │
  GitHub Actions ─► OIDC (token.actions.githubusercontent.com)           │
   (CI/CD)         └─ role: hyperlocal-cicd-deploy                      │
                        ECR push + ECS rolling update (scoped)           │
                 │                                                       │
  Humans         ─► bootstrap user (only sts:AssumeRole)                │
  (ops/terraform)   └─ role: hyperlocal-operator (scoped admin)         │
                 │   └─ group: hyperlocal-ops (MFA) → assume roles      │
                 │                                                       │
  Backend        ECS task-exec (pull/inject) + task-runtime (S3/KMS/… ) │
  (ECS Fargate)  (already present in app module)                         │
                 │                                                       │
  Monitoring     hyperlocal-monitor   (read-only CW/logs/ECS)            │
  Database       hyperlocal-db-operator  (RDS lifecycle; NO psql)        │
  S3 backup      hyperlocal-s3-backup   (read app+state, write archive)  │
                 └───────────────────────────────────────────────────────┘
```

### Role / permission matrix (source of truth: `foundation/*.tf`)
| Concern | Role / principal | Trust | Key permissions | Resource scope |
|---|---|---|---|---|
| Infrastructure admin | `hyperlocal-operator` | bootstrap + configured | ECS, ECR, EC2/VPC, ELB, RDS, ElastiCache, S3, Secrets, KMS, ACM (PassRole only own task roles) | project ARNs only; no `iam:*`, no admin |
| CI/CD | `hyperlocal-cicd-deploy` | GitHub OIDC (repo + main + prod env) | ECR push, ECS RegisterTaskDefinition + UpdateService | the ECR repo; cluster services |
| Backend runtime | ECS task-exec + task-runtime (app) | `ecs-tasks.amazonaws.com` | pull image / secret inject / S3 / SES / KMS | repo ARN, bucket, one secret |
| Database access | `hyperlocal-db-operator` | ops principals | RDS lifecycle only (reboot/snapshot/start/stop) | DB `hyperlocal-<env>-db`; **no psql** |
| S3 access | `hyperlocal-s3-backup` + task runtime | ops / task | List/Get on app+state; PutObject → `archive/` | project buckets only |
| Monitoring | `hyperlocal-monitor` | ops principals | CW read + logs read + ECS describe (read) | `/ecs/…`, cluster |
| Humans (console) | `hyperlocal-ops` group (MFA) | MFA device | self MFA + assume operator/monitor | — |

**DB-separation note:** the app reaches Postgres with its **own** RDS credentials
stored only in Secrets Manager (the `DATABASE_URL` secret from `rds.tf`). DB
operators manage the *instance lifecycle* only — no psql credential is handed to
humans, which is far safer than rotating a dba password.
## 4. No-wildcard audit (the only `Resource = "*"` grants)

Every statement is action- and resource-scoped. The only wildcards are where AWS
*cannot* scope:

| Concern | Role | Why `*` is unavoidable / mitigated |
|---|---|---|
| `sts:GetCallerIdentity` | all | Identity-only; AWS has no resource to scope. |
| `ecr:GetAuthorizationToken` | CI/CD + task | API has no resource-level ARN. |
| `ec2:*`（VPC/NAT/SG/route） | operator | Most EC2 actions lack resource-level policy keys. |
| `cloudwatch:*Read*` metrics | monitor | CloudWatch read has no resource keys. |

Everything else is pinned to real ARNs. There is **no** `iam:*`, no
`AdministratorAccess`, and `iam:PassRole` is limited to the two ECS task roles.
`iam_verify.ps1` prints any remaining wildcard statements for a human review.

## 5. Bootstrap & run order

```bash
# 1. From a machine with the bootstrap credential (never root for daily work)
export AWS_REGION=ap-south-1
cd infra/terraform/foundation
cp terraform.tfvars.example terraform.tfvars   # fill account_id, github org/repo, region
terraform init                                   # local state (bucket not yet)
terraform plan
terraform apply                                  # prints bootstrap keys ONCE — save them

# 2. Enable remote state (main.tf s3 backend → bucket = <project>-state, table = terraform-locks)

# 3. Wire CI: set repo secret AWS_DEPLOY_ROLE_ARN = foundation output ci_deploy_role_arn

# 4. Daily operator work — assume the role, don't use the static key for tasks:
export AWS_PROFILE=hyperlocal-ops    # from outputs.bootstrap_profile
aws sts get-caller-identity           # expect the operator role ARN
```

## 6. Testing (requires a live credential)

The `Test:` requirements map to `infra/scripts/iam_verify.ps1`:
1. **Authentication** — `sts:GetCallerIdentity` (assert principal is not root).
2. **Permissions** — `iam:simulate-principal-policy` on the CI role's required actions.
3. **Role assumption** — `sts:AssumeRole` on the operator role.
4. **Required service access** — smoke `ecr:GetAuthorizationToken`, `get-account-password-policy`.
5. **No unnecessary privilege** — enumerate policies, flag every `Resource = "*"`.

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/iam_verify.ps1 `
  -Region ap-south-1 -AccountId <id> -OpRole <operator-role-arn> -CiRole <ci-deploy-role-arn>
```

## 6a. LIVE VERIFICATION RESULTS (2026-08-27, account 935173128886)

Executed from the developer workstation using the temporary `cline-devops-admin`
identity (to be rotated — see §7):

| # | Requirement | Method | Result |
|---|---|---|---|
| 1 | Authentication | `sts get-caller-identity` | ✅ IAM user, non-root |
| 2 | Role assumption | `sts assume-role` × 4 roles | ✅ operator / monitor / db-operator / s3-backup |
| 2b | Least privilege enforced | un-granted `iam list-users` inside operator session | ✅ **AccessDenied** (expected deny proves scoping) |
| 3 | Permissions | `simulate-principal-policy` on `cicd-deploy` (with resource ARNs) | ✅ ecr:GetAuthorizationToken, ecr:PutImage, ecs:RegisterTaskDefinition, ecs:UpdateService all *allowed*; negative probes (`s3:PutObject`, `iam:CreateUser`) denied |
| 4 | Required service access | ECR token under operator session; S3 GET on state bucket; DynamoDB lock during remote-state migration | ✅ |
| 5 | No unnecessary privilege | wildcard inventory sweep of all 6 role policies | ✅ matches §4 whitelist exactly (identity-only, un-scopable APIs); db-operator & s3-backup policies have **zero** wildcards |

> Simulator note: `simulate-principal-policy` without `--resource-arns`
> reports `implicitDeny` for ARN-scoped actions (it has no target resource).
> Always pass explicit resource ARNs when simulating scoped actions.

Apply history: first plan surfaced two real bugs caught only by live AWS —
illegal characters in IAM/S3 tag values (`"CI/CD (…)"`, parens) and SIDs with
underscores — both fixed; a third error (`BucketAlreadyExists` for the generic
state-bucket name) led to the account-id-suffixed naming now standard here.

## 7. Residual follow-ups

1. **🚨 ROTATE THE PASTED ADMIN KEY NOW.** Access key `AKIA5TPF…` for
   `cline-devops-admin` was shared in plaintext chat. Deactivate/delete it at
   *IAM → Users → Security credentials*, then either use the console password +
   MFA (create the device first via the ops group policy), or mint a fresh key,
   and drop its `AdministratorAccess` attachments once routine work flows
   through `hyperlocal-operator` / GitHub OIDC. Prefer assuming
   `arn:aws:iam::935173128886:role/hyperlocal-operator` (profile snippet in
   outputs `bootstrap_profile`).
2. **Wire CI:** set GitHub repo settings per the table below so
   `.github/workflows/aws-iam-foundation.yml` runs the same verification suite
   read-only via OIDC (no static keys):
   `vars.AWS_REGION=ap-south-1`, `vars.AWS_ACCOUNT_ID=935173128886`,
   `secrets.AWS_VERIFY_ROLE_ARN=(output ci_verify_role_arn)`,
   `secrets.AWS_OPERATOR_ROLE_ARN=(operator_role_arn)`,
   `secrets.AWS_DEPLOY_ROLE_ARN=(ci_deploy_role_arn)`.
3. **Backend runtime roles** (app module `iam.tf`) were tightened during this
   phase: unused `ses:SendRawEmail` removed, SES/SNS split into documented
   statements (SNS phone-number publishes cannot be ARN-scoped), and the exec
   role's `logs:*:*:*` narrowed to `/ecs/<project>-<env>` only.
4. **Accepted residual:** support-role trust includes account root to allow
   future console/SSO principals; identity-side policies currently restrict
   assumes to bootstrap/admin only. Revisit when SSO arrives.
5. Historical local-run runbook kept below for reference.

**Run the following on an internet-connected developer machine** (never in chat):

```bash
# A. Install tools once (script provided; no admin required)
powershell -ExecutionPolicy Bypass -File infra/scripts/install_tools.ps1
export PATH="$PWD/.tools:$PWD/.tools/aws/dist:$PATH"

# B. Provide the bootstrap credential as ENV VARS (never paste into chat/repo)
export AWS_ACCESS_KEY_ID=AKIA...      # from your bootstrap user
export AWS_SECRET_ACCESS_KEY=...       # scoped to sts:AssumeRole only
export AWS_REGION=ap-south-1
export AWS_IAM_ACCOUNT_ID=123456789012 # your 12-digit account id

# C. Validate the identity is NOT root, then assume the operator role
aws sts get-caller-identity            # expect a non-root principal (bootstrap user)
export AWS_PROFILE=hyperlocal-ops      # profile = outputs.bootstrap_profile

# D. Apply the PHASE 2 foundation
cd infra/terraform/foundation
cp terraform.tfvars.example terraform.tfvars   # fill account_id, github org/repo, region
terraform init
terraform plan                                # REVIEW — then:
terraform apply                               # capture bootstrap keys, ci_deploy_role_arn
# (out of scope for you to start): enable the s3 backend in main.tf and re-init.)

# E. Wire CI: set the GitHub secret AWS_DEPLOY_ROLE_ARN = <ci_deploy_role_arn>
# F. Run the verification runbook
powershell -ExecutionPolicy Bypass -File infra/scripts/iam_verify.ps1 `
  -Region ap-south-1 -AccountId $AWS_IAM_ACCOUNT_ID `
  -OpRole <operator-role-arn> -CiRole <ci-deploy-role-arn>

# G. Rotate/secrets hygiene: after the run, reduce/disable the bootstrap key.
```

The four Test requirements map 1:1 to that runbook (auth → role assumption →
`simulate-principal-policy` → service access + wildcard scan). **Never paste your
bootstrap secret into chat.**

### Alternative: run the Test steps in CI (no local toolchain needed)
`.github/workflows/aws-iam-foundation.yml` automates the same checks in GitHub
Actions (runner already has the AWS CLI + Terraform + network). It runs on push
to `infra/terraform/foundation/**` and on manual dispatch. It needs only these
GitHub repo settings (all non-secret values are `vars`, role ARNs are `secrets`):

| Setting | Value (from `terraform output` after `foundation` apply) |
|---|---|
| `vars.AWS_REGION` | e.g. `ap-south-1` |
| `vars.AWS_ACCOUNT_ID` | your 12-digit account id |
| `secrets.AWS_VERIFY_ROLE_ARN` | output `ci_verify_role_arn` (read-only) |
| `secrets.AWS_OPERATOR_ROLE_ARN` | output `operator_role_arn` |
| `secrets.AWS_DEPLOY_ROLE_ARN` | output `ci_deploy_role_arn` (also used by backend-deploy) |

The `validate` job does `terraform fmt -check` + `terraform init` + `terraform
validate` (no credentials). The `verify` job assumes the read-only `ci_verify`
role via OIDC and runs `iam_verify.ps1` end-to-end. It never modifies anything.