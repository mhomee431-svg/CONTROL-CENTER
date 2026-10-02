"""Report pre-existing vs newly-touched error lines."""
from __future__ import annotations

import json
from typing import Any

TOUCHED: dict[str, set[int]] = {
    "base.py": {58, 61, 70, 89, 132, 152, 189, 196, 232},
    "models\\pos.py": {3, 44, 162},
    "shop_service.py": {6, 125, 278, 306},
    "audit_service.py": {24, 93, 94},
    "inventory_service.py": {4, 156, 217},
    "entitlements.py": {198, 245, 318, 333},
    "upload_security.py": {32, 33, 34},
    "security.py": {28, 54, 64},
    "exceptions.py": {3, 5, 22},
    "otp_store.py": {55, 59, 73, 96, 99, 135, 145},
    "otp_service.py": {6, 7, 10, 15, 43, 148},
    "rate_limit.py": {16, 36, 52, 57},
    "analytics_system.py": {25, 236, 308, 340, 392, 420},
    "excel_import_service.py": {426},
}

try:
    with open("pyright_support.json", encoding="utf-8-sig") as f:
        data: dict[str, Any] = json.load(f)
    rows: list[tuple[str, int, str, str]] = []
    diagnostics: list[dict[str, Any]] = data.get("generalDiagnostics", [])
    for d in diagnostics:
        f_path: str = str(d.get("file", "")).replace("/", "\\")
        start_dict: dict[str, Any] = d.get("range", {}).get("start", {})
        line: int = int(start_dict.get("line", 0)) + 1
        matched_key: str | None = next((k for k in TOUCHED if f_path.endswith(k)), None)
        if matched_key and line in TOUCHED[matched_key]:
            msg: str = str(d.get("message", "")).splitlines()[0]
            rule: str = str(d.get("rule", ""))
            rows.append((matched_key, line, rule, msg))

    if not rows:
        print("no diagnostics on touched lines")
    sorted_rows: list[tuple[str, int, str, str]] = sorted(set(rows))
    for r in sorted_rows:
        print(" | ".join(str(x) for x in r))
except Exception:
    pass
