# Runbook

Failure-by-failure. Each entry: what you see, why it happens, what to do.

The first question for any failure is always:

```powershell
python scripts/hl.py check
```

If that is red, it names the gate. If it is green and CI is red, scroll to
["CI is red, local is green"](#ci-is-red-local-is-green).

---

## Lint

### `F821 Undefined name`

The most valuable finding this repo's gate produces. It means a name is used
before it is defined — an `AttributeError`/`NameError` at runtime, on a code path
your tests do not exercise.

**Why it happens:** most often a function-local import that does not exist in
the function you edited:

```python
def some_other_route():
    from app.core.responses import error_response   # local import
    ...

def this_route():
    return error_response(...)                      # F821: never imported here
```

**Fix:** hoist the import to module level, and delete the now-redundant local
copies. Do not add another local import — that is how the same bug gets
reintroduced six functions later.

### `E9 invalid-syntax`

Usually a merge-conflict marker that Python could still parse around:

```bash
git diff --check
git status                    # UU entries are the unresolved files
python scripts/hl.py check    # the gate also catches these
```

---

## Analyzer (`flutter analyze`)

### `unnecessary_import`

Two imports provide the same symbol. Delete the redundant one. If a comment
explains why the "redundant" import exists, that comment is now wrong — fix it in
the same commit, or the next person will re-add the import.

### `deprecated_member_use`

Replace it with the named alternative and **read the replacement's return type
before you touch the assertion**. This is a real trap:

```dart
// OLD: returns bool
tester.getSemantics(node).hasFlag(SemanticsFlag.isEnabled)   // compared to isTrue

// NEW: returns a THREE-valued Tristate, not a bool
tester.getSemantics(node).flagsCollection.isEnabled          // compare to Tristate.isTrue
```

Asserting `isTrue` against a `Tristate` compiles, passes the analyzer, and fails
at runtime — or worse, compares in a way that makes the test vacuous.

### The analyzer is the gate

Zero errors, warnings **and** infos. There is no baseline and no `// ignore:` for
pre-existing findings. If a finding is pre-existing and unrelated to your change,
fix it in its own commit — a commit carrying an unrelated fix is the one that
gets reverted wholesale.

---

## Tests

### A test fails only in CI

Almost always concurrency or ordering, not logic. Reproduce:

```powershell
cd apps\shopkeeper_app
flutter test --no-pub --concurrency=1
```

`hl` already defaults to `--concurrency=1`. If that fixes it, a test is sharing
mutable state — usually a module-level cache, a `DateTime.now()` outside
`fakeAsync`, or a `ProviderContainer` that is never disposed.

### `flutter test` hangs with no output

This workspace is a OneDrive sync folder. Concurrent test isolates reading the
same files can stall indefinitely; `--concurrency=1` avoids it.

A hang is not a result: it is indistinguishable from a genuinely broken build, so
you debug the wrong thing. Prefer slow-and-finite over fast-and-hung.

### Backend tests: 0 collected

```powershell
cd backend
python -m pytest --collect-only -q
```

A collection error names the file and the reason. Common causes: a module that
fails to import (see `F821` above), or two pytest configs competing — there is
now exactly one, in `pyproject.toml`.

---

## Migrations

### `duplicate revision 0027`

Two migration files declared the same `revision`. Alembic refuses to run and
reports "multiple heads" — on a deployed database that is an outage.

```bash
python scripts/hl.py migrations      # names both files
```

**Fix:** renumber the newer one to the next free revision and repoint its
`down_revision` at the previous head. Keep the `revision: str = "0027"` type
annotation — two test suites parse it with `^revision:`, and dropping the
annotation makes them report "no revision id".

### A migration succeeded in staging, failed in production

Production has rows staging does not. The usual cause is a `NOT NULL` or a
constraint added in the same migration as the backfill.

**Fix:** do not edit the applied migration. Write a new one that makes it work,
and change the plan for next time: nullable column → backfill → constraint, in
three deploys.

---

## Secrets

### A hook or CI blocks on a secret

Good. Now **rotate it** — do not just `git restore` and commit. The value is in
the history and on the remote; blocking the next commit does not un-leak the
last one.

Full procedure: [../security/SECRET_ROTATION.md](../security/SECRET_ROTATION.md).

### `gitleaks` flags a test fixture

Almost certainly a fake credential in `tests/`. Do not disable the rule. Add a
scoped allowlist entry in `.gitleaks.toml` with the exact file path, and nothing
wider — a path-level allowlist covering `tests/` only.

---

## Git

### `UU` files after a merge

The merge is half-done. Resolve each file, then:

```bash
git add <file>
python scripts/hl.py check       # catches markers you missed
git commit                       # completes the merge
```

Most "the merge destroyed my code" incidents are exactly this: resolve most
hunks, commit, discover the last one was missed. The conflict-marker hook exists
so that cannot happen silently.

### `scripts/dev/test.sh` says "No venv yet"

That script expects `backend/.venv`. It is a project-local convenience, not the
supported entry point. Use:

```powershell
python scripts/hl.py test --scope be
```

---

## CI is red, local is green

In order of likelihood:

1. **You skipped `hl check`.** Run it. That is the entire point of it.
2. **Version drift.** CI pins Python 3.12; you may be on 3.14.
   `python scripts/hl.py doctor` prints what you actually have.
3. **An untracked file made it work locally.** CI only sees committed files.
   `git status --porcelain` — if something untracked that your tests need is
   there, that is the bug.
4. **Test ordering.** Run the full suite locally, not just the file you changed.
5. **Otherwise it is a bug in `hl`.** `ci.yml` runs `scripts/hl.py`, the same
   code you run. If they disagree, fix `hl` — not the workflow.

