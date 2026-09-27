# Emergency Hotfix Workflow

> The path to follow when **production is broken right now** and a fix cannot
> wait for the normal `feature/*` → `develop` → `main` cycle.
>
> Companion to [`docs/deployment/BRANCHING.md`](deployment/BRANCHING.md)
> (the full branch model and gate matrix).

---

## 1. The path in one line

```
main ──► hotfix/* ──► PR to main (deployed) ──► back-merge to develop
```

## 2. Why the back-merge is MANDATORY, not optional

`main` and `develop` are two different branches holding two different states of
the code. If a fix lands on `main` and never comes back to `develop`, the next
ordinary merge into `develop` **re-introduces the bug** — and the next release
from `develop` ships it again.

This is the single most common way a hotfix "disappears". Treat the back-merge
as part of the fix, not as cleanup.

```
                 hotfix merged here
                        │
       ┌────────────────┴────────────────┐
       │                                 │
   main (fixed)                    develop (still broken)
       │                                 │
       │   <──── FORGOT TO BACK-MERGE? ───┘
       │                                 │
       └──────────► next merge to develop ◄──┘
                          │
                          ▼
                   bug is BACK in production
```

## 3. Step by step

### Step 1 — Cut the branch from `main`, not from `develop`

```bash
git checkout main
git pull --ff-only
git checkout -b hotfix/<short-description>
```

The fix must be based on the code that is **actually failing in production**,
not on whatever `develop` has drifted into.

### Step 2 — Fix it, and prove it locally BEFORE pushing

```bash
# Backend
cd backend
pytest -q

# A changed route means the committed contract is now stale.
cd ..
python scripts/ci/refresh_api_contract.py
python scripts/ci/check_api_contract_drift.py

# Shopkeeper / customer apps
cd apps/shopkeeper_app
flutter analyze
flutter test
cd ../..

# If a route changed, confirm the contract is in sync:
python scripts/ci/refresh_api_contract.py --check
```

A hotfix is **not** an exemption from testing. A bypassed gate is how a
two-line fix turns into a three-day outage. If a gate is too slow to wait for,
the correct response is to fix the gate, not to skip it.

### Step 3 — Open the PR into `main`

```bash
git push -u origin hotfix/<short-description>
```

Then open: **`hotfix/<name>` → `main`**.

This PR runs the **same** gates as any other pull request:

| Gate | What it proves |
|---|---|
| Backend quality battery | static analysis, unit, integration, migration safety |
| Analyze + tests (all apps) | nothing obviously broken |
| API contract drift | app and backend agree on the API |
| Build verify | the app actually compiles |
| Secret scan | no credentials in the diff |

Plus the **production approval** on merge (`environment: production`).

### Step 4 — Confirm the release

Merging triggers the CD pipeline on `main`:
quality battery → staging → smoke → E2E contract → **approval** → production →
verify → auto rollback on failure.

Verify the deployed SHA, not just the pipeline:

```bash
curl -s https://api.hyperlocal.in/health | python -m json.tool
```

Watch the run for the first few minutes: error rate, p95 latency, and the
health endpoint.

### Step 5 — Back-merge to `develop` (do not skip)

```bash
git checkout develop
git pull --ff-only
git merge --no-ff hotfix/<short-description>
git push origin develop
```

**Merge, never rebase.** `main` is public release history; rewriting it
invalidates the deployed SHA and destroys the audit trail of what was shipped.

### Step 6 — Propagate to in-flight feature branches (recommended)

If a `feature/*` branch is still open, it will now conflict with `develop`:

```bash
git checkout feature/<in-flight>
git rebase --onto develop <develop-sha-before-the-hotfix> develop
git push --force-with-lease
```

`--force-with-lease`, never plain `--force`: it refuses to overwrite if someone
else pushed in the meantime.

---

## 4. Hard rules

| Rule | Why |
|---|---|
| Branch from `main`, never `develop` | The fix must sit on the code that actually failed. |
| **Back-merge to `develop` is mandatory** | Otherwise the next merge reintroduces the bug. |
| Merge, never rebase `main` into `develop` | Rewriting release history invalidates the deployed SHA. |
| Regenerate the contract if a route changed | A new route not in `openapi.json` blocks the *next* staging deploy. |
| Hotfixes pass the full PR gate | A skipped gate is how a small fix becomes an outage. |
| `--force-with-lease`, never `--force` | Plain force overwrites someone else's work silently. |
| Never push straight to `main` | A direct push skips every gate and the approval. |

## 5. Mobile releases are the exception

**A released APK cannot be rolled back.** Once Play Store serves a build to a
user, no pipeline can take it back — the fastest remedy is a *newer* APK.

Therefore:

- Backend hotfixes are cheap and reversible. Ship them.
- App hotfixes are permanent. Treat them as a release decision, not a hotfix.
- A mobile fix that truly cannot wait should ship to **internal testing →
  closed testing** on the Play Console, never straight to production.
- A mobile release should use a **staged rollout** (5% → 20% → 100%) with an
  automatic halt when the crash rate breaches the threshold. See
  [`docs/deployment/RELEASE_RUNBOOK.md`](deployment/RELEASE_RUNBOOK.md).

## 6. If `main` and `develop` have drifted badly

Do **not** force-merge and do **not** reset either branch.

1. Merge `main` into `develop` on a normal branch and resolve there.
2. Re-run the full gate.
3. Let the E2E contract battery on the next `main` push prove the two are
   consistent.

The E2E gate exists precisely for this: it compares the deployed `/openapi.json`
against the committed contract, so a bad merge cannot pass silently.
