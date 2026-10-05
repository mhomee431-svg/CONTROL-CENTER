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
- [ ] Checked on the staging deployment against the real backend

## Checklist

- [ ] No credentials, tokens or `.env` values committed
- [ ] A failed request still renders a distinct error state, not an empty list
- [ ] Loading and empty states are handled
- [ ] Architecture contracts in `docs/` were not removed or contradicted
- [ ] New env vars documented in `.env.example`

## Risk and rollback

<!--
What breaks if this is wrong, and how to undo it.
Vercel keeps every deployment, so rollback is Dashboard -> Deployments ->
instant rollback. Say here if this needs a coordinated backend change.
-->