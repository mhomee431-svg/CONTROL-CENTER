#!/usr/bin/env python3
"""Phase 8 — secret scanner (dependency-free).

Scans the repository for accidentally committed credentials. Complements
gitleaks in CI (see .github/workflows/secret-scan.yml) and runs anywhere
Python 3.10+ runs — no third-party packages required.

Modes (combinable):

  --tracked    scan every file tracked by git (what would be pushed)
  --history    scan every line ever added across the full git history
  --paths D..  scan arbitrary filesystem paths (tests / ad-hoc audits)

Usage::

    python scripts/security/scan_secrets.py --tracked
    python scripts/security/scan_secrets.py --tracked --history

Exit codes: 0 = clean, 1 = findings, 2 = usage / runtime error.

The scanner NEVER prints secret values — every match is redacted in output.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
MAX_FILE_BYTES = 2 * 1024 * 1024  # skip absurdly large files

# Cheap superset gate for the detector battery below.
#
# Every detector's regex necessarily contains at least one of these anchors, so
# a line that fails this test cannot match ANY detector — which makes the gate
# result-preserving rather than a heuristic. Running it first turns ~40 regex
# passes per line into 1, which is the difference between seconds and many
# minutes on this repository's history (>10M added lines).
#
# KEEP IN SYNC when adding a detector: a missing anchor would silently narrow
# coverage. The Phase 8 tests cover each anchor they exercise.
_PRE_FILTER = re.compile(
    r"akia|aiza|-----begin|sg\.|[sr]k_(?:live|test)_|xox[baprs]-|gh[pousr]_"
    r"|npm_|://|aws|secret|password|passwd|api_key|apikey|private_key"
    r"|auth_token|access_token|service_account",
    re.IGNORECASE,
)
_PRE_FILTER_BYTES = re.compile(
    _PRE_FILTER.pattern.encode("ascii"),
    re.IGNORECASE,
)


def _entropy(value: str) -> float:
    """Shannon entropy (bits/char) — random secrets score high (~3.5+)."""
    if not value:
        return 0.0
    freq: dict = {}
    for ch in value:
        freq[ch] = freq.get(ch, 0) + 1
    n = len(value)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


# Known throwaway / dev-only credential values (ephemeral CI containers,
# localhost compose stacks) — still never used outside local dev.
DEV_DB_HOSTS = {
    "localhost", "127.0.0.1", "::1", "db", "postgres", "postgresql", "redis",
    "mongodb", "database", "mysql", "host.docker.internal",
}
DEV_DB_PASSWORDS = {
    "postgres", "password", "pass", "root", "example", "secret", "changeme",
    "change-me", "hyperlocal_pw", "hyperlocal_dev_pw", "placeholder",
}

BENIGN_VALUES = {
    "change-me-in-production", "dev-secret-key-change-in-production",
    "mock-payment-secret", "supersecret", "secretkey", "jwt_secret",
    "your-secret-key", "changeme", "changeit", "secret", "hyperlocal_pw",
    "hyperlocal_dev_pw", "postgres", "password", "none", "null", "nil",
    "true", "false", "mock", "local", "memory://", "unset", "empty",
    "redacted", "removed", "invalid", "disabled", "not-configured",
    "belongs_in_secrets_manager", "test-key", "test-key-1", "test_key",
    "mock-key-25", "secret-1", "dummy", "sample", "hyperlocal",
    "optional", "str", "int", "bool", "float", "field", "bytes", "lambda",
}

_PLACEHOLDER_VALUE_RE = re.compile(
    r"(?i)(change[-_]?me|change[-_]?in|placeholder|your[-_ ]|<[^>]+>"
    r"|\$\{[^}]*\}|\{\{[^}]*\}\}|example|sample|dummy|mock|test|fixture|fake"
    r"|redacted|xxx|\*{3,}|belongs[-_]in|from[-_]vault|insert[-_]?"
    r"|replace[-_]?|documentation|reference|todo)"
)

# Paths that may legitimately mention secret *shapes* (docs, committed
# reference examples, the scanner's own regexes, unit tests with synthetic
# values). Case-insensitive, matched against POSIX-style repo-relative paths.
ALLOWLIST_PATHS = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"(^|/)\.env(\.[^/]*)?\.example$",          # committed reference docs
        r"(^|/)\.gitleaks\.toml$",
        r"(^|/)scan_secrets\.py$",                   # this file (contains regexes)
        r"(^|/)tests?/",                             # synthetic test fixtures
        r"(^|/)docs/",
        r"(^|/)readme(\..*)?$",
        r"production_readiness_report\.md$",         # archived under docs/deployment
        r"(^|/)\.pytest_cache/",
        r"(^|/)\.dart_tool/",
        r"(^|/)\.idea/",
        r"(^|/)\.vscode/",
        r"(^|/)pubspec\.lock$",
        r"(^|/)package-lock\.json$",
        # Firebase/Google Android client config — the API key inside is a public
        # identifier (restricted by package name), not a server secret.
        r"(^|/)google-services\.json(\.bak)?$",
        # FlutterFire-generated client config (Flutter/Dart) — holds the same
        # public, package-name-restricted API key as google-services.json.
        r"(^|/)firebase_options\.dart$",
        # Build script references the key by variable (%MAPS_API_KEY% injected
        # from gitignored local.properties at build time) — no literal secret.
        r"(^|/)build_customer_app\.bat$",
    ]
]


def _db_url_validator(m):
    """Suppress dev/CI database URLs (localhost, compose services, dev defaults)."""
    pw = m.group("pw")
    user = m.group("user")
    host = m.group("host").lower().strip("[]")
    if not re.search(r"[A-Za-z0-9]", pw):  # placeholder like "..." or "${...}"
        return False
    if "${" in pw or "${" in user or "<" in pw or "<" in user:
        return False  # terraform / shell templated credentials
    if user.lower() in {"user", "username", "u", "<user>", "your-user"}:
        return False  # literal placeholder examples (user:pw@host)
    if pw.lower() in {"pw", "p", "<password>", "your-password", "your-pw"}:
        return False
    if any(
        _PLACEHOLDER_VALUE_RE.search(part)
        for part in (user, pw, host)
    ):
        return False  # CHANGE_ME / example.com style placeholders
    if pw.lower() in DEV_DB_PASSWORDS:
        return False
    if host in DEV_DB_HOSTS:
        return False
    return True


def _generic_validator(m):
    """Heuristic filter for KEY=VALUE assignments."""
    val = m.group("val")
    name = m.group("name")
    if len(val) < 8:
        return False
    if _entropy(val.lower()) < 2.8:
        return False
    if val.lower() in BENIGN_VALUES:
        return False
    if val.lower() == name.lower():
        return False
    if val.startswith(("-", "$", "<")):
        return False  # shell / template variable references & flags
    if m.start() > 0 and m.string[m.start() - 1] in "${@":
        return False  # value is inside a template: ${POSTGRES_PASSWORD:-…}
    if re.match(r"^(?:List|Get|Put|Create|Delete|Update|Describe|Tag|Untag)[A-Z]", val):
        return False  # AWS IAM action names (secretsmanager:ListSecrets …)
    if _PLACEHOLDER_VALUE_RE.search(val):
        return False
    return True


@dataclass(frozen=True)
class Detector:
    detector_id: str
    regex: "re.Pattern"
    description: str
    validator: Optional[Callable] = None


DETECTORS = [
    Detector(
        "aws-access-key",
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "AWS access key ID",
    ),
    Detector(
        "aws-secret-key",
        re.compile(
            r"(?i)aws.{0,32}?secret[_a-z0-9]{0,20}[\"']?\s*[:=]\s*[\"']?[A-Za-z0-9/+=]{40}\b"
        ),
        "AWS secret access key",
    ),
    Detector(
        "private-key-block",
        re.compile(
            r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----"
        ),
        "Embedded private key material",
    ),
    Detector(
        "google-api-key",
        re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"),
        "Google / Firebase API key",
    ),
    Detector(
        "google-oauth-client-secret",
        re.compile(
            r"(?i)client_secret[\"']?\s*[:=]\s*[\"']?[A-Za-z0-9_\-]{24,}\b"
        ),
        "Google OAuth client secret",
    ),
    Detector(
        "gcp-service-account-json",
        re.compile(r"(?i)\"type\"\s*:\s*\"service_account\""),
        "GCP service-account JSON (private key embedded)",
    ),
    Detector(
        "sendgrid-key",
        re.compile(r"\bSG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}\b"),
        "SendGrid API key",
    ),
    Detector(
        "stripe-key",
        re.compile(r"\b[sr]k_(?:live|test)_[0-9a-zA-Z]{20,}\b"),
        "Stripe secret / restricted key",
    ),
    Detector(
        "slack-token",
        re.compile(r"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b"),
        "Slack token",
    ),
    Detector(
        "github-token",
        re.compile(r"\bgh[pousr]_[0-9A-Za-z]{35,}\b"),
        "GitHub token",
    ),
    Detector(
        "npm-token",
        re.compile(r"\bnpm_[0-9A-Za-z]{36}\b"),
        "npm token",
    ),
    Detector(
        "database-url-with-credentials",
        re.compile(
            r"(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|rediss|amqps?|"
            r"mssql|oracle)(?:\+[a-z0-9]+)?://(?P<user>[^\s:/@\"']+):(?P<pw>[^\s@/\"']+)"
            r"@(?P<host>[^\s@/\"':]+)"
        ),
        "Database/queue URL with embedded credentials",
        validator=_db_url_validator,
    ),
    Detector(
        "generic-secret-assignment",
        re.compile(
            r"\b(?P<name>[A-Z][A-Z0-9_]*(?:SECRET|PASSWORD|PASSWD|API_KEY|"
            r"APIKEY|PRIVATE_KEY|AUTH_TOKEN|ACCESS_TOKEN)[A-Z0-9_]*)[\"']?"
            r"(?::\s*[A-Za-z_][\w\[\]\. ]*)?(?:[:=]|=>)\s*[\"']?"
            r"(?P<val>[^\s\"'`,;)\]}\[(?/<.]{6,})"
        ),
        "Hardcoded secret-like assignment (entropy heuristic)",
        validator=_generic_validator,
    ),
]


def _is_allowlisted(path: str) -> bool:
    p = path.replace("\\", "/")
    return any(rx.search(p) for rx in ALLOWLIST_PATHS)


@dataclass
class Finding:
    source: str        # tracked | history | paths
    path: str
    line: int
    detector: str
    description: str
    masked_line: str


def _mask(line: str, start: int, end: int) -> str:
    masked = (line[:start] + "[REDACTED]" + line[end:]).strip()
    return masked[:140] + ("…" if len(masked) > 140 else "")


def _iter_findings(source: str, path: str, lineno: int, line: str):
    """Run the detector battery over a single line, behind the superset gate."""
    if not _PRE_FILTER.search(line):
        return
    for det in DETECTORS:
        for m in det.regex.finditer(line):
            if det.validator and not det.validator(m):
                continue
            yield Finding(
                source=source,
                path=path,
                line=lineno,
                detector=det.detector_id,
                description=det.description,
                masked_line=_mask(line, m.start(), m.end()),
            )


def _scan_text(source: str, path: str, text: str):
    if "\x00" in text[:8192]:  # binary file
        return
    for lineno, line in enumerate(text.splitlines(), start=1):
        yield from _iter_findings(source, path, lineno, line)


def _tracked_files():
    out = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files", "-z"],
        capture_output=True, check=True,
    ).stdout
    return [f.decode("utf-8", "replace") for f in out.split(b"\x00") if f]


def scan_tracked():
    findings = []
    for rel in _tracked_files():
        if _is_allowlisted(rel):
            continue
        abs_path = REPO_ROOT / rel
        if not abs_path.is_file() or abs_path.stat().st_size > MAX_FILE_BYTES:
            continue
        text = abs_path.read_bytes().decode("utf-8", "replace")
        findings.extend(_scan_text("tracked", rel, text))
    return findings


def scan_history():
    """Scan every unique blob ever created across the full git history.

    Rather than re-diffing every commit across branches and checkpoints
    (which generates >13 million lines of diffs across 2,000 commits), we
    enumerate every unique blob object in the repository via ``rev-list`` and
    stream them through a single ``git cat-file --batch`` pipeline.

    Blobs above ``MAX_FILE_BYTES`` or matching ``ALLOWLIST_PATHS`` are skipped
    before reading, and content is pre-screened with the byte-level anchor
    ``_PRE_FILTER_BYTES`` before line-by-line inspection.
    """
    revs = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-list", "--objects", "--all"],
        capture_output=True, check=True,
    ).stdout
    checked = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "cat-file",
         "--batch-check=%(objectname) %(objecttype) %(objectsize) %(rest)"],
        input=revs, capture_output=True, check=True,
    ).stdout.decode("utf-8", "replace")

    blobs_to_check = []
    seen_shas = set()
    for row in checked.splitlines():
        parts = row.split(" ", 3)
        if len(parts) >= 3 and parts[1] == "blob":
            sha = parts[0]
            if sha in seen_shas:
                continue
            seen_shas.add(sha)
            try:
                size = int(parts[2])
            except ValueError:
                continue
            path = parts[3] if len(parts) == 4 else ""
            if not path or size > MAX_FILE_BYTES or _is_allowlisted(path):
                continue
            blobs_to_check.append((sha, path, size))

    cat_proc = subprocess.Popen(
        ["git", "-C", str(REPO_ROOT), "cat-file", "--batch"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    )

    def _feed_shas():
        assert cat_proc.stdin is not None
        for sha, _, _ in blobs_to_check:
            cat_proc.stdin.write(sha.encode("ascii") + b"\n")
        cat_proc.stdin.flush()
        cat_proc.stdin.close()

    feeder = threading.Thread(target=_feed_shas, daemon=True)
    feeder.start()

    findings = []
    assert cat_proc.stdout is not None
    for sha, path, size in blobs_to_check:
        _header = cat_proc.stdout.readline()
        data = cat_proc.stdout.read(size)
        cat_proc.stdout.read(1)  # trailing newline from cat-file --batch
        if b"\x00" in data[:1024]:
            continue
        if not _PRE_FILTER_BYTES.search(data):
            continue
        text = data.decode("utf-8", "replace")
        for lineno, line in enumerate(text.splitlines(), start=1):
            if _PRE_FILTER.search(line):
                findings.extend(_iter_findings("history", path, lineno, line))

    feeder.join()
    cat_proc.wait()
    return findings


def scan_paths(paths):
    findings = []
    for raw in paths:
        root = Path(raw).resolve()
        if root.is_file():
            candidates = [root]
        elif root.is_dir():
            candidates = sorted(p for p in root.rglob("*") if p.is_file())
        else:
            print(f"warning: path not found: {raw}", file=sys.stderr)
            continue
        for f in candidates:
            try:
                rel = str(f.relative_to(REPO_ROOT))
            except ValueError:
                rel = str(f)
            if _is_allowlisted(rel):
                continue
            if f.stat().st_size > MAX_FILE_BYTES:
                continue
            try:
                text = f.read_bytes().decode("utf-8", "replace")
            except OSError:
                continue
            findings.extend(_scan_text("paths", rel, text))
    return findings


def _human_report(findings, stats):
    lines = [
        "=" * 70,
        "PHASE 8 — SECRET SCAN REPORT",
        "=" * 70,
    ]
    lines += [f"  {k}: {v}" for k, v in stats.items()]
    if not findings:
        lines.append("\nRESULT: CLEAN — no committed secrets detected.")
    else:
        lines.append(f"\nRESULT: {len(findings)} FINDING(S)\n")
        for f in findings:
            lines.append(
                f"  [{f.detector}] {f.source}:{f.path}:{f.line} — {f.description}"
            )
            lines.append(f"      {f.masked_line}")
    lines.append("=" * 70)
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Phase 8 secret scanner")
    parser.add_argument("--tracked", action="store_true",
                        help="scan all git-tracked files")
    parser.add_argument("--history", action="store_true",
                        help="scan all lines added across full git history")
    parser.add_argument("--paths", nargs="*", default=[],
                        help="scan these filesystem paths instead")
    parser.add_argument("--json", action="store_true",
                        help="emit machine-readable JSON")
    args = parser.parse_args(argv)

    if not (args.tracked or args.history or args.paths):
        parser.error("choose at least one of --tracked / --history / --paths")

    findings = []
    stats = {"repo": str(REPO_ROOT)}
    try:
        if args.tracked:
            stats["tracked_files"] = len(_tracked_files())
            findings.extend(scan_tracked())
        if args.history:
            findings.extend(scan_history())
            stats["history"] = "scanned (git log --all -p)"
        if args.paths:
            findings.extend(scan_paths(args.paths))
            stats["paths"] = args.paths
    except subprocess.CalledProcessError as exc:
        print(f"error: git command failed: {exc}", file=sys.stderr)
        return 2

    stats["findings"] = len(findings)
    if args.json:
        print(json.dumps({
            "stats": stats,
            "findings": [f.__dict__ for f in findings],
        }, indent=2))
    else:
        print(_human_report(findings, stats))

    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())




