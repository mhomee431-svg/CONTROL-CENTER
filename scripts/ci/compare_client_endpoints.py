#!/usr/bin/env python3
"""scripts/ci/compare_client_endpoints.py -- is every client endpoint live?

The companion to `collect_client_endpoints.py`, used by the release-ordering
guard.

A mobile release cannot be rolled back: once an APK reaches a user's phone,
no pipeline can take it back. So the dangerous state is not "the app is
broken" but "the app calls an endpoint the deployed backend does not serve
yet". This script answers exactly that question by comparing the endpoints the
apps call against the LIVE `/openapi.json` of a running environment.

Paths are normalised to the OpenAPI convention (`/a/{id}`) on both sides, so
a client that calls `/shops/$shopId` is compared with the server's
`/shops/{shop_id}` instead of being reported as a phantom mismatch.

Exit codes: 0 every client endpoint is live, 1 some are not, 2 could not
evaluate (network / malformed document) -- a distinct code on purpose, so a
transport failure is never mistaken for a clean pass.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

_PARAM_RE = re.compile(r"\{[^}]+\}")


def canonical(path: str) -> str:
    return _PARAM_RE.sub("{}", path.split("?")[0].rstrip("/") or "/")


def fetch_live_paths(url: str, timeout: int = 30) -> set[str]:
    endpoint = f"{url.rstrip('/')}/openapi.json"
    request = urllib.request.Request(
        endpoint,
        headers={"Accept": "application/json", "User-Agent": "release-ordering-guard"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        document = json.load(response)
    return {canonical(p) for p in (document.get("paths") or {})}


def read_client_paths(path: str) -> set[str]:
    return {
        line.strip()
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Compare client endpoints with a live API")
    ap.add_argument("--live-url", required=True, help="base URL of the running environment")
    ap.add_argument(
        "--client-paths",
        required=True,
        help="file produced by collect_client_endpoints.py",
    )
    ap.add_argument("--report", help="write a human-readable summary here")
    ap.add_argument("--timeout", type=int, default=30)
    args = ap.parse_args()

    try:
        live = fetch_live_paths(args.live_url, args.timeout)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        print(f"::error::Could not read {args.live_url}/openapi.json: {exc}")
        print("::error::The ordering check could not be evaluated; it is NOT a pass.")
        return 2

    client = {canonical(p) for p in read_client_paths(args.client_paths)}
    missing = sorted(p for p in client if p and p not in live)

    lines = [
        f"client endpoints: {len(client)}",
        f"live paths:       {len(live)}",
        f"not yet live:     {len(missing)}",
    ]
    lines += [f"  - {p}" for p in missing]
    report = "\n".join(lines) + "\n"
    if args.report:
        Path(args.report).write_text(report, encoding="utf-8")

    if missing:
        print("::error::The deployed API does not serve these endpoints yet:")
        for path in missing:
            print(f"::error::  {path}")
        print("::error::Shipping the app first would give users a broken screen, and")
        print("::error::a released APK cannot be rolled back. Deploy the backend first.")
        return 1

    print("::notice::Every endpoint the apps call is already live.")
    return 0


if __name__ == "__main__":
    sys.exit(main())