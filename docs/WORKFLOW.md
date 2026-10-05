---
title: Development, Staging and Production Workflow
last_reviewed: 2026-10-05
---

# Development, Staging and Production Workflow

This document is the operating manual for this repository. It exists because
the project has one maintainer: six months from now there is no memory of
why a rule exists, only the rule itself.

## Shape of the pipeline

```
   edit locally
       |
   git push to main
       |
   +--- CI ---------------------------------------------------+
   |  typecheck -> lint -> test -> build                     |
   |  also: CodeQL + npm audit (Security workflow)           |
   +---------------------+-----------------------------------+
         |               |
      red |              | green
         v               v
    stop, fix      deploy-staging.yml
                             |
                    staging domain (real backend)
                             |
                 verified? tag a release
                             |
                   git tag v1.2.3 && git push --tags
                             |
                  deploy-production.yml
                             |
                      production domain
```

## The rules, and why each one exists

**`main` is the trunk.** Commits go straight to it. Long-lived feature
branches are not used for routine work: with a single maintainer a branch is
a delayed commit, and rebasing it later costs more than it saves. Short-lived
branches are still fine for a large or risky change.

**Production only ships from a tag.** A commit is work-in-progress. A tag is
the deliberate statement that this exact build was verified on staging. This
is the single most useful rule here — it means an unreviewed 23:40 push can
never reach the admin console.

**CI is the reviewer, not a human.** Approving your own pull request is not
review. The machine catches what tired eyes at 23:40 do not.

**Staging is not the test environment.** Tests run locally and in CI. Staging
answers a different question: does this build behave correctly against a real
backend and real cookies. Bugs it catches are environment bugs.

## Why the admin panel needs deployment protection

This frontend can ban users, suspend shops, and read audit trails. A public
production URL would expose that surface to anyone who guesses the address.

**Enable Vercel Authentication** (Settings -> Deployment Protection). It is
available on all Vercel plans, including Hobby, and restricts every
deployment URL to Vercel accounts you explicitly grant access to. Password
Protection is Pro-only, so it is not the option here.

## Environment variables per environment

| Variable | Local | Staging | Production |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000` | staging backend | production backend |
| `NEXT_PUBLIC_WS_URL` | `ws://localhost:8000/api/v1/ws` | staging WS | production WS |
| `NEXT_PUBLIC_ENV` | `development` | `staging` | `production` |

Variables are read at build time. After changing one in Vercel, the existing
deployment keeps the old value until it is rebuilt — redeploy it.

## One-time setup

1. Import the repository into Vercel (`vercel link` locally, or connect the
   git integration).
2. Add the repository variables — `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` under
   Settings -> Secrets and variables -> Actions -> **Variables**.
3. Add `VERCEL_TOKEN` under **Secrets**.
4. Set the three `NEXT_PUBLIC_*` variables per environment.
5. Enable Vercel Authentication under Deployment Protection.
6. Point a staging domain at the preview deployment for the `main` branch.

Until `VERCEL_ORG_ID` and `VERCEL_TOKEN` exist, the two deploy workflows skip
themselves rather than failing. CI and security still run normally.

## Daily commands

```bash
# Before every push — this is the habit that replaces code review.
npm run typecheck && npm run lint && npm test

# Release to production, after verifying staging.
git tag v1.2.3
git push origin main --tags
```

## If production breaks

Vercel keeps every deployment. Dashboard -> Deployments -> pick the last good
one -> instant rollback. It takes seconds and does not need a new commit.
For a data-shape problem rather than a build problem, roll back first and
diagnose after.

## What is deliberately not here

- **Pull-request ceremony.** No self-approving PRs.
- **`develop` or `release/*` branches.** Coordination machinery for a team
  of one is just overhead.
- **Docker.** Vercel builds this frontend; a container would be something to
  maintain with no benefit.
- **Pre-commit hooks.** They get bypassed under time pressure. The habit of
  running the checks before pushing is what actually holds.