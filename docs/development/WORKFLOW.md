# Development Workflow

**The short version:** one command locally, the same command in CI, a branch per
change, and a protected `main` that only moves through a green build.

---

## 1. Setup (once)

```powershell
git clone https://github.com/Akasharyan47/hyperlocal_app.git
cd hyperlocal_app

python scripts/hl.py doctor          # what is installed, what is missing
pip install -r backend/requirements.txt
pip install ruff pre-commit pyyaml

cd apps/shopkeeper_app; flutter pub get; cd ../..
cd apps/customer_app;   flutter pub get; cd ../..

python scripts/hl.py hooks install   # stop problems BEFORE they are committed
```

`hooks install` is the highest-value line above. It runs the secret scan,
conflict-marker check, lint gate and analyzer on every `git commit`, which means
most problems are caught while you still have the keyboard in your hand — before
they become a red build on GitHub.

---

## 2. The daily loop

```powershell
git switch -c feature/what-you-are-building   # always a branch, never develop directly

# ... write code ...

python scripts/hl.py check      # ~40s: lint, analyzer, migrations, conflicts, secrets
python scripts/hl.py test       # the full suite
git commit -am "..."           # hooks run here
git push -u origin HEAD
# open a pull request -> develop
```

`check` and `test` are the same commands GitHub Actions runs (`ci.yml` calls
`scripts/hl.py` — there is no inline CI logic to drift from).

---

## 3. Branching model

```
main          production. Protected: PR-only, 1 approval (you), CI required.
  ^
  |  promote after staging soak
develop       integration. Protected: PR-only, CI required.
  ^
  |  merge via PR
feature/*     one branch per change. Deleted on merge.
fix/*         a production bug. Branch from main, PR to main, then back-merge.
```

**Rules that matter for a solo maintainer**

| Rule | Why |
|---|---|
| Never commit to `main` or `develop` | CI can only be *required* on a PR. A direct push has no gate, so the gate does not exist for that commit. |
| One concern per PR | A 900-line PR that fails takes 20 minutes to bisect. Nine small PRs take 20 seconds each. |
| Never mix a refactor with a fix | The refactor makes the fix unreviewable, so the fix gets reverted along with it. |
| `fix/*` branches PR to `main` | Cherry-picking back into `develop` is how branches diverge and then fail to merge for reasons unrelated to the fix. |
| Rebase `feature/*` onto `develop`, never merge `develop` into it | Keeps the branch's history linear and makes the PR diff show only your change. |

---

## 4. What CI enforces, and where

| Check | Where | Blocks a merge? |
|---|---|---|
| Ruff gate (undefined names, syntax, type misuse) | `ci.yml` -> `hl check` | **Yes** |
| `flutter analyze` both apps | `ci.yml` -> `hl check` | **Yes** |
| Alembic chain linear, one head | `ci.yml` -> `hl check` | **Yes** |
| Conflict markers in tracked files | `ci.yml` -> `hl check` | **Yes** |
| Secret scan | `ci.yml` -> `hl check` | **Yes** |
| pytest (backend) | `ci.yml` -> `hl test` | **Yes** |
| `flutter test` (both apps) | `ci.yml` -> `hl test` | **Yes** |
| Dependency updates | `dependabot.yml` | No (PR only) |
| Deployment gates | `backend-cd.yml`, `backend-deploy.yml` | Yes, for `main` |

Configure `ci / gate` as a **required status check** on both `develop` and
`main`. Until you do, CI is advisory: GitHub will happily let you merge a red
build, and the gate protects nothing.

### The other workflows

There are 14 more workflows. They are not duplicates of `ci.yml`:

- `aws-iam-foundation.yml`, `aws-network-foundation.yml` — infrastructure
  validation against Terraform.
- `secret-scan.yml` — deeper scan than `hl check`, including git history.
- `db-backup-recovery-test.yml` — proves a restore actually works.
- `direct-push-audit.yml` — compensates for the fact that a solo maintainer
  *can* bypass branch protection. It reports rather than blocks, because by the
  time it runs the push has already happened.
- `release-ordering-guard.yml` — blocks a release whose migrations are not in
  dependency order.
- `backend-cd.yml`, `backend-deploy.yml` — deploy to staging / production.
- `flutter-customer.yml`, `flutter-shopkeeper.yml`, `flutter-admin.yml` — build
  release artefacts (APK/IPA). `ci.yml` tests them; these package them.

If two workflows ever disagree about whether the code is good, `ci.yml` is
authoritative: it is the one branch protection points at.


---

## 5. Environments

Three environments, one pipeline, promotion by rebuild-not-by-reuse.

```
develop  --PR-->  main  --tag vX.Y.Z-->  production
   |                  |                      |
   +-- staging --------+----------------------+
```

- **staging** — deployed from `develop`. Owned by `backend-deploy.yml`. This is
  where migrations are rehearsed against real Postgres + PostGIS.
- **production** — deployed from a release tag on `main`, never a direct push.
  Owned by `backend-cd.yml`.

**Why migrations are the hard part.** A migration that succeeded in staging can
still fail in production if production has data staging does not — a `NOT NULL`
on a column that is empty locally, an `ALTER` on a table far larger than
anything you tested with. So:

1. Never write a migration and its rollback in separate commits.
2. Every migration must be reversible. `alembic downgrade` must work.
3. Add new columns as nullable, backfill, then add the constraint in a *later*
   migration. Three deploys beat one outage.
4. `hl check` verifies the chain is linear with a single head. It does not
   verify the SQL — only a real rehearsal against staging does that.

---

## 6. Coding standard

### Backend (Python)

The blocking rules are `E9`, `F63`, `F7`, `F82`, defined once in
`backend/pyproject.toml`:

| Rule | Catches |
|---|---|
| `E9` | syntax error — the file does not parse |
| `F82` | undefined name — a `NameError` waiting to happen at runtime |
| `F63` | comparison/type misuse — wrong result, no error |
| `F7` | statement-level bugs |

That is deliberately narrow. The wider Ruff defaults report **~2000 findings**
across this codebase, almost all `Optional[X]` vs `X | None`. Turning those into
a merge blocker means either 2000 mechanical edits or a gate you learn to skip —
and a gate you skip does not catch the one real bug in the noise.

Adopt the rest incrementally with `hl lint:fix`, in this order: `F401`
(unused imports, ~288), `I` (import order, ~246), `F841` (~21), `B904`
(raise-without-from, ~13), `UP` (~1200, all at once, in one boring commit).

**Style:** 4-space indent, 100-col lines, double quotes,
`from __future__ import annotations` at the top of every module. Docstrings
explain **why**, not what — the code already says what.

### Flutter (Dart)

- `flutter analyze` must be clean: **zero** errors, warnings and infos. The
  analyzer is the gate; there is no lint baseline to grandfather against.
- `const` wherever the value is known at compile time.
- No `print` in `lib/`. Use `debugPrint` or the app's logger.
- Every user-facing string goes through `appText(context)`. A hard-coded string
  in a widget is an untranslatable string.

### Tests

A test must fail when the behaviour it names is broken. The three failure modes
to avoid:

1. **Asserting on your own mock.** A test that builds a fake and asserts the
   fake's values passes forever and catches nothing. Assert on what the *screen*
   renders, or what the *repository* is asked for.
2. **Asserting `findsNothing` for something you never added.**
   `expect(find.byKey(x), findsNothing)` passes if the widget was never built —
   including because the screen crashed.
3. **Broad exception assertions.** `assertRaises(Exception)` also passes for the
   `AttributeError` you did not intend.

Naming: `test_<condition>_<expected outcome>`. The test name is the
specification; if you cannot write it as a sentence, the test is unclear.

---

## 7. Releases

```powershell
# 1. green locally
python scripts/hl.py ci

# 2. merge develop -> main via PR (CI must be green)

# 3. tag
git tag -a v1.4.0 -m "..."
git push origin v1.4.0        # this triggers production deployment

# 4. watch the CD run
```

Semantic version:
- **patch** — bug fix, no API change
- **minor** — a feature, backwards compatible
- **major** — a breaking API or data change

Roll back: `git revert -m 1 <merge-sha>`, then push. Never force-push `main` —
its history is your audit trail and your only record of what production ran.

---

## 8. If something breaks

See [RUNBOOK.md](RUNBOOK.md) for the failure-by-failure playbook. The two you
will hit most:

- **CI red, local green** — you skipped `hl check`. Run it.
- **CI red, local also red** — `hl check` tells you which gate. It is the same
  output CI saw.
