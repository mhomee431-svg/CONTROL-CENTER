# Secret Rotation Runbook

**Read this before you deploy anything.**

## Why this file exists

Three files were committed to this repository that contain credentials:

| File | Shape | Status |
|---|---|---|
| `backend/_new_secret.txt` | 64-char token | untracked; **treat as compromised** |
| `backend/_access.txt` | 327 bytes | untracked; **treat as compromised** |
| `backend/admin_token.txt` | 284 bytes | untracked; **treat as compromised** |

They are now in `.gitignore`, so they will not be committed **again**. That is
not the same as fixing the problem: they are already in the commit history, and
therefore already on GitHub and in every clone.

**Untracking a secret does not un-leak a secret. Only rotation does.**

## The rule

> A credential that has ever been in a commit is a burned credential.
> Rotate it. Do not "just delete the file".

## Rotation checklist

Run this once, in order. Do not skip step 4 — it is the one that actually
removes the secret from the remote.

- [ ] **1. Identify** — open the three files above and note which real
      credential each one holds (an AWS access key, a DB password, an admin
      JWT, ...). Anything unreadable is assumed live.
- [ ] **2. Revoke at the source** — AWS IAM, the RDS instance, or whichever
      system issued it. Revoke first, rotate second: revoking first means the
      window where the old key still works is as short as possible.
- [ ] **3. Issue a replacement** into the environment, never into a file in
      the repository. See `backend/app/core/aws_secrets.py` and
      `docs/security/PHASE_8_SECRETS_MANAGEMENT.md` for how the backend reads
      secrets at runtime.
- [ ] **4. Scrub history** — the history rewrite. This rewrites commit SHAs, so
      do it **before** anyone else clones, and expect to force-push:

      ```powershell
      # Install once:  pip install git-filter-repo
      git filter-repo --path backend/_new_secret.txt `
                      --path backend/_access.txt `
                      --path backend/admin_token.txt `
                      --invert-paths
      git push --force --mirror origin
      ```

      If you would rather not rewrite history (shared clones, open PRs), the
      acceptable alternative is: leave history alone, and rely on rotation
      having made the old values worthless. That is safe **only because you
      completed steps 2 and 3**. Record which route you took below.
- [ ] **5. Verify** — `python scripts/security/scan_secrets.py` must be clean,
      and `gitleaks detect` must report nothing on the pushed history.
- [ ] **6. Record** — fill in the table at the bottom. A rotation with no
      record is a rotation nobody repeats.

## Making it not happen again

| Control | Where | What it stops |
|---|---|---|
| `.gitignore` rules | `.gitignore` | the next accidental commit |
| `scripts/hl secrets` | `scripts/hl` | committing a secret on this machine |
| `secret-scan.yml` | GitHub Actions | a secret reaching the remote |
| `.gitleaks.toml` | repo root | a secret anywhere, including history |
| pre-commit hook | `.pre-commit-config.yaml` | the commit itself, locally |

The pre-commit hook is the one that actually prevents it, because it fails the
commit while you are still holding the keyboard. Install it once:

```powershell
scripts/hl hooks install
```

## Rotation log

| Date | Credential | Action | History scrubbed? |
|---|---|---|---|
| _(pending)_ | `backend/_new_secret.txt` | revoke + rotate | _ |
| _(pending)_ | `backend/_access.txt` | revoke + rotate | _ |
| _(pending)_ | `backend/admin_token.txt` | revoke + rotate | _ |
