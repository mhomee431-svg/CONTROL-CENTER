"""Phase 8 — secrets-management verification tests.

Encodes the five guarantees of the secrets-management phase as tests:

  1. secrets are not committed            → scanner over tracked files + history
  2. secrets are not logged               → AWS Secrets hydration + entrypoint
  3. secrets are not embedded in images   → .dockerignore coverage
  4. secrets are not exposed via API      → POS credentials masked views
  5. secrets are not shipped in Flutter   → public client keys only

Scanner: scripts/security/scan_secrets.py (dependency-free, repo-rooted).
"""
import fnmatch
import json
import logging
import os
import shlex
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = Path(__file__).resolve().parents[1]
SCANNER = REPO_ROOT / "scripts" / "security" / "scan_secrets.py"

# Local-only Cline checkpoint snapshots that still contain pre-rotation
# credentials (never pushed — see docs/PHASE_8_SECRETS_MANAGEMENT.md for the
# rotation/prune runbook). The history test fails on anything else.
KNOWN_LOCAL_INCIDENTS = (
    "backend/hyperlocal--discovery-firebase-adminsdk-",
    ".tools/tf_init_plan.ps1",
)


def _run_scanner(*args):
    return subprocess.run(
        [sys.executable, str(SCANNER), *args],
        capture_output=True,
        text=True,
        timeout=600,
    )


# ── 1. Secrets are not committed ─────────────────────────────────────────────


def test_scanner_detects_planted_secrets(tmp_path):
    """Sanity: the scanner actually catches real secret shapes."""
    planted = tmp_path / "leaked.py"
    planted.write_text(
        'AWS_KEY = "AKIAIOSFODNN7EXAMPLE"\n'
        'MAPS = "AIzaSyA1bC2dE3fG4hI5jK6lM7nO8pQ9rS0tU1v"\n'
        "-----BEGIN RSA PRIVATE KEY-----\n"
    )
    proc = _run_scanner("--paths", str(planted), "--json")
    assert proc.returncode == 1
    payload = json.loads(proc.stdout)
    ids = {f["detector"] for f in payload["findings"]}
    assert {"aws-access-key", "google-api-key", "private-key-block"} <= ids


def test_scanner_allows_placeholders(tmp_path):
    """Dev placeholders / localhost URLs must not raise findings."""
    doc = tmp_path / "config.env"
    doc.write_text(
        "JWT_SECRET_KEY=change-me-in-production\n"
        "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/hyperlocal\n"
        "DATABASE_URL_STAGING=postgresql+asyncpg://user:pw@host:5432/db\n"
        'REDIS_URL=redis://127.0.0.1:6379/0\n'
    )
    proc = _run_scanner("--paths", str(doc), "--json")
    assert proc.returncode == 0, proc.stdout
    assert json.loads(proc.stdout)["findings"] == []


def test_tracked_tree_is_clean():
    """Guarantee 1a: no secrets in any git-tracked file."""
    proc = _run_scanner("--tracked", "--json")
    payload = json.loads(proc.stdout)
    assert proc.returncode == 0, json.dumps(payload["findings"], indent=2)
    assert payload["findings"] == []


def test_git_history_has_no_untracked_leaks():
    """Guarantee 1b: no NEW secrets in history.

    Two documented local-only incidents exist in Cline checkpoint snapshots
    (never pushed to origin). Any OTHER historical finding is a regression.
    """
    proc = _run_scanner("--history", "--json")
    payload = json.loads(proc.stdout)
    unexpected = [
        f for f in payload["findings"]
        if not f["path"].startswith(KNOWN_LOCAL_INCIDENTS)
    ]
    assert unexpected == [], json.dumps(unexpected, indent=2)


def test_no_env_files_are_tracked():
    tracked = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    env_files = [
        p for p in tracked
        if os.path.basename(p) == ".env"
        or (os.path.basename(p).startswith(".env.") and not p.endswith(".example"))
    ]
    assert env_files == []


# ── 2. Secrets are not logged ────────────────────────────────────────────────


def test_aws_secrets_hydration_never_logs_values(caplog, monkeypatch):
    from app.core import aws_secrets

    synthetic = {
        "JWT_SECRET_KEY": "super-secret-value-9876543210",
        "SMTP_PASSWORD": "hunter2-mail-secret-42",
    }
    monkeypatch.setattr(aws_secrets, "fetch_secret", lambda sid: synthetic)
    monkeypatch.setattr(aws_secrets, "resolve_secret_id", lambda: "test/bundle")
    for key in synthetic:
        monkeypatch.delenv(key, raising=False)

    with caplog.at_level(logging.DEBUG):
        applied = aws_secrets.hydrate_os_environ("test/bundle")

    assert applied == "test/bundle"
    for key, value in synthetic.items():
        assert os.environ.get(key) == value          # hydrated correctly…
        assert value not in caplog.text               # …never logged…
    assert "JWT_SECRET_KEY" in caplog.text            # …but names are.


def test_export_output_is_shell_quoted(monkeypatch):
    from app.core import aws_secrets

    nasty = '"; rm -rf / #'
    monkeypatch.setattr(
        aws_secrets, "fetch_secret", lambda sid: {"SMTP_PASSWORD": nasty}
    )
    monkeypatch.setattr(aws_secrets, "resolve_secret_id", lambda: "test/bundle")

    out = aws_secrets.export_as_shell()
    assert out == f"export SMTP_PASSWORD={shlex.quote(nasty)}\n"


def test_entrypoint_never_echoes_secret_payload():
    entrypoint = (BACKEND_DIR / "entrypoint.sh").read_text(encoding="utf-8")
    assert "eval \"${secrets_env}\"" in entrypoint      # exported into shell
    assert 'echo "$secrets_env' not in entrypoint       # never printed
    assert "echo ${secrets_env" not in entrypoint


# ── 3. Secrets are not embedded in Docker images ────────────────────────────


def _dockerignore_ignored(rel_path: str, lines) -> bool:
    """Minimal .dockerignore matcher (ordered, `!` negations honoured)."""
    ignored = False
    rel = rel_path.replace("\\", "/")
    for raw in lines:
        pat = raw.strip()
        if not pat or pat.startswith("#"):
            continue
        negated = pat.startswith("!")
        if negated:
            pat = pat[1:]
        candidates = [pat] if pat.startswith("**/") else [pat, f"**/{pat}"]
        if any(fnmatch.fnmatch(rel, c) for c in candidates):
            ignored = not negated
    return ignored


def test_dockerignore_excludes_credentials_and_env():
    lines = (BACKEND_DIR / ".dockerignore").read_text(encoding="utf-8").splitlines()
    must_be_ignored = [
        "backend/.env",
        "backend/.env.production",
        "backend/hyperlocal--discovery-firebase-adminsdk-fbsvc-3e2c39a88e.json",
        "backend/serviceAccountKey.json",
        "backend/server.pem",
        "backend/upload.jks",
    ]
    for rel in must_be_ignored:
        assert _dockerignore_ignored(rel, lines), f"{rel} would be COPY'd into the image!"
    # Committed reference examples stay available for builds that need them.
    assert not _dockerignore_ignored("backend/.env.example", lines)


# ── 4. Secrets are not exposed through API responses ────────────────────────


def test_pos_credentials_are_masked_never_raw():
    from app.services.pos_integration.base import POSCredentials

    class _Integration:
        api_key_encrypted = "mock-key-25"
        api_secret_encrypted = "super-secret-value"
        api_base_url = "https://mock-pos.local/api"
        config_json = {"credentials": {"store_code": "STORE-42"}}

    view = POSCredentials.masked_view(_Integration())
    rendered = str(view)
    assert "mock-key-25" not in rendered
    assert "super-secret-value" not in rendered
    assert "****" in rendered


# ── 5. Secrets are not shipped in Flutter ───────────────────────────────────


FORBIDDEN_IN_FLUTTER = (
    "JWT_SECRET", "DATABASE_URL", "SENDGRID_API_KEY", "TWILIO_AUTH_TOKEN",
    "GOOGLE_CLIENT_SECRET", "FCM_CREDENTIALS", "SMTP_PASSWORD",
    "STRIPE_SECRET", "AWS_SECRET_ACCESS_KEY", "FAST2SMS_API_KEY",
)


def test_flutter_apps_carry_public_keys_only():
    """Server-side secrets must never reach client code/bundles.

    MAPS_API_KEY / API_BASE_URL are public, restriction-scoped client keys
    (deliberately allowed via --dart-define).
    """
    violations = []
    for app_dir in ("apps/customer_app", "apps/shopkeeper_app"):
        base = REPO_ROOT / app_dir
        for sub in ("lib", "android", "ios"):
            root = base / sub
            if not root.exists():
                continue
            for f in root.rglob("*"):
                if not f.is_file() or f.suffix not in {
                    ".dart", ".xml", ".gradle", ".properties", ".plist",
                    ".xcconfig", ".yaml", ".json",
                }:
                    continue
                try:
                    text = f.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                for needle in FORBIDDEN_IN_FLUTTER:
                    if needle in text:
                        violations.append(f"{f.relative_to(REPO_ROOT)}: {needle}")
    assert violations == []


# ── CI wiring ────────────────────────────────────────────────────────────────


def test_ci_secret_scan_is_configured():
    assert (REPO_ROOT / ".gitleaks.toml").is_file()
    wf = REPO_ROOT / ".github" / "workflows" / "secret-scan.yml"
    assert wf.is_file()
    content = wf.read_text(encoding="utf-8")
    assert "gitleaks" in content
    assert "scan_secrets.py" in content

