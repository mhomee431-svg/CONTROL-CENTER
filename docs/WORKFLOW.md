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
   |  commitlint (advisory) -> typecheck -> lint -> test     |
   |  -> build                                              |
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
              git tag v1.2.3 && git push origin main --tags
                             |
         +-------------------+-------------------+
         |                                       |
  release-notes.yml                    deploy-production.yml
  (GitHub Release + notes)              (production domain)
```

## Supply chain: every action is pinned to a commit SHA

Third-party actions are referenced by full SHA, not by a movable tag:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.2.2
```

`actions/checkout@v4` is a pointer the action's owner can move at any time.
If that account is ever compromised, a tag reference runs the attacker's code
inside this repository with access to its secrets. A SHA is immutable, so
`@v4` resolving to something hostile cannot happen.

Dependabot updates the pinned SHAs on its weekly schedule, so pinning costs
no ongoing effort. The trailing comment records which release the SHA is, so
the file stays readable.

## Commit messages are the project's only automatic documentation

`git log` is how "when did this break, and what touched it" gets answered
months later. That is only possible if every message says what kind of change
it was, so commits follow Conventional Commits:

```
<type>(optional scope): <description>

feat(customers): add saved-products tab
fix(imports): resolve job detail from the ingestion registry
ci: add staging and tag-driven production deployment pipeline
refactor(api): extract a single request helper
```

The type carries meaning for tooling: `fix` is a patch release, `feat` is a
minor one, and `!` or a `BREAKING CHANGE` footer is a major one.

```bash
npm run lint:commit   # check the commits you just made
```

**The CI check is advisory** (`continue-on-error`) on purpose. History still
contains `hi`, `p` and `Update hi.txt content to 565` from before the
convention existed; a hard gate would go permanently red on commits nobody is
going to rewrite. Once history is clean it can be made blocking.

## Releases are written by the tooling

Tagging `v1.2.3` publishes a GitHub Release whose notes are grouped by change
type from the commit prefixes. Nobody writes release prose at release time,
which matters most when releasing under pressure.

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

- **Pull-request ceremony.** No self-approving PRs. Approving your own work
  is not review.
- **Merge queue.** Available only on organization-owned repositories and
  private repos on Enterprise Cloud — not on a personal account, so there is
  nothing to enable.
- **`develop` or `release/*` branches.** Coordination machinery for a team of
  one is just overhead.
- **Docker.** Vercel builds this frontend; a container would be something to
  maintain with no benefit.
- **Pre-commit hooks.** They get bypassed under time pressure. The habit of
  running the checks before pushing is what actually holds.
- **A hard commitlint gate.** History predates the convention; making it
  blocking would mean permanently red CI or a history rewrite, both worse than
  reporting drift.

## GitHub settings worth turning on once

These are in the repository settings rather than in files:

- **Settings -> General -> Automatically delete head branches.** Keeps
  finished branches from accumulating.
- **Settings -> Actions -> General -> Require approval for all outside
  collaborators.** Lets you run workflows from a fork without giving it
  secrets.
- **Settings -> Branches -> main -> Require status checks to pass.** The
  check is `verify`. Even committing straight to `main`, this makes a red CI
  run visible on the branch itself.