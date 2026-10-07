> Routine work commits straight to `main` — see [docs/WORKFLOW.md](../docs/WORKFLOW.md).
> Use a pull request when the change is risky, hard to review, or you want
> the CI run recorded separately from `main`.

## What this changes

<!-- One or two sentences. What is different after this merges? -->

## Why

<!-- The reasoning, not the diff — the diff is already on the right. -->

## How it was verified

- [ ] `npm run typecheck`
- [ ] `npm run lint`
- [ ] `npm test` — new behaviour has a test that fails without this change
- [ ] `npm run build`
- [ ] Backend changes: `python -m pytest tests` (from `backend/`)
- [ ] Checked on a staging deployment against the real backend (when available; not required during feature development)

## Checklist

- [ ] No credentials, tokens or `.env` values committed
- [ ] A failed request still renders a distinct error state, not an empty list
- [ ] Loading and empty states are handled
- [ ] Database model changes include a reviewed Alembic migration
- [ ] Architecture contracts in `docs/` were not removed or contradicted
- [ ] New env vars documented in `.env.example`

## Risk and rollback

<!--
What breaks if this is wrong, and how to undo it.
For application code, redeploy the last known-good commit. For database
changes, note the migration and any required restore or forward-fix plan.
-->