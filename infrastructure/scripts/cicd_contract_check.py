#!/usr/bin/env python3
"""Post-deploy E2E battery for a *deployed* environment (pipeline step 10b).

`cicd_smoke_test.sh` answers "is the box alive?". This script answers the
harder, release-blocking question: "is the deployed API really the code we
just shipped, and does it still serve the committed contract?" It is the
staging E2E gate that must pass before a human is asked to approve production.

Checks (all against the live URL, no credentials required):

  0. reachability   - /health answers 200 within --wait seconds
  1. liveness       - /health.status == "healthy"
  2. identity       - /health.environment == --expect-env (staging|production)
                      /health.deployment.commit == --sha (when not "unknown")
  3. readiness      - /ready: 200, or 503 while still reporting the hard
                      dependencies (database, redis, postgis) as true.
                      storage / background_queue may be offline in a minimal
                      environment and only produce a warning.
  4. contract       - /openapi.json matches packages/api_contracts/openapi.json
                      (path + method + schema-name parity). A deployed API that
                      is missing documented endpoints FAILS the release;
                      undocumented extra endpoints FAIL too unless --subset-ok.
  5. version        - /health.version matches the contract's info.version.

Dependency-free by design (stdlib only) so it can run in any CI job without
pip install, and locally against any environment:

    python infrastructure/scripts/cicd_contract_check.py \
        --url https://staging-api.hyperlocal.in --expect-env staging

Exit codes: 0 = pass, 1 = check failed, 2 = usage / transport error.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = REPO_ROOT / "packages" / "api_contracts" / "openapi.json"

# Path-item keys that are not HTTP operations.
_NON_METHOD_KEYS = {"parameters", "summary", "description", "servers", "$ref"}
_HTTP_METHODS = {
    "get",
    "put",
    "post",
    "delete",
    "options",
    "head",
    "patch",
    "trace",
}
# Readiness components that MUST be true for a release to proceed.
_HARD_COMPONENTS = ("database", "redis", "postgis")
_USER_AGENT = "hyperlocal-cicd-contract-check/1.0"


class CheckFailed(Exception):
    """A release-blocking check failed."""


def pass_(message: str) -> None:
    print(f"  [ok] {message}")


def warn(message: str) -> None:
    print(f"  [warn] {message}")


def fail(message: str) -> None:
    raise CheckFailed(message)


def section(title: str) -> None:
    print(f"\n== {title}")


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib only)
# ---------------------------------------------------------------------------
def request_json(url: str, timeout: float) -> tuple[int, object]:
    """GET *url* and return (status, parsed-json). Never raises for 4xx/5xx."""
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as exc:  # still a response: body matters
        status = exc.code
        raw = exc.read()
    except urllib.error.URLError as exc:
        fail(f"{url} unreachable: {exc.reason}")
    except OSError as exc:  # pragma: no cover - socket level failures
        fail(f"{url} transport error: {exc}")

    text = raw.decode("utf-8", errors="replace").strip()
    if not text:
        return status, None
    try:
        return status, json.loads(text)
    except json.JSONDecodeError:
        return status, text


def wait_for_health(url: str, wait_seconds: int, timeout: float) -> dict:
    """Poll /health until it answers 200 (a deploy restarts the container)."""
    deadline = time.time() + wait_seconds
    last = ""
    while True:
        try:
            status, body = request_json(f"{url}/health", timeout)
        except CheckFailed as exc:  # keep polling until the deadline
            last = str(exc)
            status, body = 0, None
        if status == 200 and isinstance(body, dict):
            return body
        last = last or f"/health returned {status}"
        if time.time() >= deadline:
            fail(f"/health never became reachable within {wait_seconds}s ({last})")
        time.sleep(5)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def check_health(health: dict, expect_env: str | None, sha: str | None) -> None:
    section("liveness + deployment identity (/health)")
    print(f"  payload: {json.dumps(health, sort_keys=True)}")

    if health.get("status") != "healthy":
        fail(f"health.status != healthy (got {health.get('status')!r})")
    pass_("status=healthy")

    environment = health.get("environment")
    if expect_env:
        if not environment:
            fail("/health does not report an environment (deployment identity missing)")
        if environment != expect_env:
            fail(f"health.environment={environment!r} != expected {expect_env!r}")
        pass_(f"environment={environment}")

    deployment = health.get("deployment") or {}
    commit = (deployment.get("commit") or "").strip()
    if sha:
        short = sha[:12]
        if not commit or commit == "unknown":
            warn("deployment.commit is unknown - skipping SHA match (set GIT_COMMIT)")
        elif not (short.startswith(commit) or commit.startswith(short)):
            fail(
                f"deployment.commit={commit!r} != expected {short!r} (wrong build is live)"
            )
        else:
            pass_(f"deployment.commit={commit}")

    version = health.get("version")
    if not version:
        fail("/health.version is empty")
    pass_(f"version={version}")


def check_ready(url: str, timeout: float) -> dict:
    section("readiness (/ready)")
    status, body = request_json(f"{url}/ready", timeout)
    if not isinstance(body, dict):
        fail(f"/ready returned {status} with a non-JSON body")
    checks = body.get("checks") or {}
    print(f"  checks: {json.dumps(checks, sort_keys=True)}")

    for component in _HARD_COMPONENTS:
        if component not in checks:
            fail(f"/ready does not report the {component!r} component")
        if checks[component] is not True:
            fail(f"/ready.{component} is false - the deployed stack is unhealthy")
    pass_("database + redis + postgis reachable")

    for component, value in sorted(checks.items()):
        if component not in _HARD_COMPONENTS and value is not True:
            warn(f"{component} is offline (allowed in a minimal environment)")

    if status not in (200, 503):
        fail(f"/ready returned an unexpected status {status}")
    if status == 503:
        warn("/ready is 503 (soft components offline) - hard dependencies are green")
    else:
        pass_("status=ready (200)")
    return body


def _operation_signatures(spec: dict) -> dict[str, list[str]]:
    """Map path -> sorted HTTP methods (lower-cased) from an OpenAPI document."""
    signatures: dict[str, list[str]] = {}
    for path, item in (spec.get("paths") or {}).items():
        if not isinstance(item, dict):
            continue
        methods = sorted(
            key.lower()
            for key in item
            if key.lower() in _HTTP_METHODS and key.lower() not in _NON_METHOD_KEYS
        )
        signatures[path] = methods
    return signatures


def _schema_names(spec: dict) -> set[str]:
    return set(((spec.get("components") or {}).get("schemas") or {}).keys())


def check_contract(
    url: str, contract_path: Path, timeout: float, subset_ok: bool
) -> None:
    section(f"contract parity (/openapi.json vs {contract_path.name})")
    if not contract_path.is_file():
        fail(f"contract file not found: {contract_path}")
    try:
        expected = json.loads(contract_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"committed contract is not valid JSON: {exc}")

    status, live = request_json(f"{url}/openapi.json", timeout)
    if status != 200 or not isinstance(live, dict):
        fail(f"/openapi.json returned {status} (the API must serve its contract)")
    pass_("openapi.json served (200)")

    expected_ops = _operation_signatures(expected)
    live_ops = _operation_signatures(live)
    print(
        f"  operations: contract {len(expected_ops)} paths / live {len(live_ops)} paths"
    )

    missing = sorted(set(expected_ops) - set(live_ops))
    extra = sorted(set(live_ops) - set(expected_ops))
    if missing:
        fail(
            "deployed API is MISSING documented endpoints: "
            + ", ".join(missing[:10])
            + (" ..." if len(missing) > 10 else "")
        )
    pass_(f"all {len(expected_ops)} documented paths are served")

    if extra:
        message = (
            "deployed API serves undocumented endpoints: "
            + ", ".join(extra[:10])
            + (" ..." if len(extra) > 10 else "")
        )
        if subset_ok:
            warn(message)
        else:
            fail(message + " (re-export the contract, or pass --subset-ok)")
    else:
        pass_("no undocumented endpoints")

    method_drift = [
        f"{path} (contract {expected_ops[path]}, live {live_ops[path]})"
        for path in sorted(set(expected_ops) & set(live_ops))
        if expected_ops[path] != live_ops[path]
    ]
    if method_drift:
        fail("method drift: " + "; ".join(method_drift[:10]))
    pass_("HTTP methods match")

    expected_schemas, live_schemas = _schema_names(expected), _schema_names(live)
    missing_schemas = sorted(expected_schemas - live_schemas)
    if missing_schemas:
        fail(
            "deployed API is missing documented schemas: "
            + ", ".join(missing_schemas[:10])
            + (" ..." if len(missing_schemas) > 10 else "")
        )
    extra_schemas = sorted(live_schemas - expected_schemas)
    if extra_schemas:
        warn(
            f"{len(extra_schemas)} schema(s) exist only in the deployed API: "
            + ", ".join(extra_schemas[:10])
        )
    pass_(f"schemas match ({len(expected_schemas)} documented)")

    expected_version = ((expected.get("info") or {}).get("version") or "").strip()
    live_version = ((live.get("info") or {}).get("version") or "").strip()
    if expected_version and live_version and expected_version != live_version:
        fail(
            f"info.version drift: contract {expected_version!r} vs live {live_version!r}"
        )
    pass_(f"info.version={live_version or 'unset'}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="E2E contract battery for a deployed Hyperlocal environment.",
    )
    parser.add_argument(
        "--url", required=True, help="Base URL (scheme + host, no /api/v1)"
    )
    parser.add_argument("--expect-env", default=None, help="staging | production")
    parser.add_argument("--sha", default=None, help="Expected git SHA (short or long)")
    parser.add_argument(
        "--contract",
        default=str(DEFAULT_CONTRACT),
        help=f"Committed OpenAPI file (default: {DEFAULT_CONTRACT.name})",
    )
    parser.add_argument(
        "--timeout", type=float, default=20.0, help="Per-request timeout (s)"
    )
    parser.add_argument(
        "--wait", type=int, default=300, help="Seconds to wait for /health"
    )
    parser.add_argument(
        "--subset-ok",
        action="store_true",
        help="Allow the deployed API to serve endpoints missing from the contract",
    )
    args = parser.parse_args(argv)

    url = args.url.rstrip("/")
    if not url.startswith(("http://", "https://")):
        print("ERR: --url must start with http:// or https://", file=sys.stderr)
        return 2
    if args.expect_env and args.expect_env.startswith("http"):
        # Classic foot-gun: --url and --expect-env swapped.
        print(
            "ERR: --expect-env looks like a URL; expected 'staging' or 'production'",
            file=sys.stderr,
        )
        return 2

    print(f"E2E contract battery against {url}")
    try:
        health = wait_for_health(url, args.wait, args.timeout)
        check_health(health, args.expect_env, args.sha)
        check_ready(url, args.timeout)
        check_contract(url, Path(args.contract), args.timeout, args.subset_ok)
    except CheckFailed as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        return 1
    print("\nPASSED: E2E contract battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
