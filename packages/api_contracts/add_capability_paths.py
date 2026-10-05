"""Copy the capability routes out of the live FastAPI app into openapi.json.

`openapi.json` is normally produced by a full regeneration (`export_openapi.py`),
which rewrites thousands of unrelated lines. When only new routes were added,
regenerating wholesale buries the change in diff noise, so this copies just the
capability paths from the app's own OpenAPI — the real handler signatures, not
hand-written prose that can drift from the code.

Idempotent: an existing path is left alone, and every response that is missing
an explicit error is left as the app declares it.
"""

import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[2] / "backend"
CONTRACT = Path(__file__).resolve().parent / "openapi.json"

sys.path.insert(0, str(BACKEND))

WANTED = (
    "/api/v1/shopkeeper/businesses/categories/{category_code}/capabilities",
    "/api/v1/shopkeeper/businesses/categories/{category_code}/product-attributes",
    "/api/v1/shopkeeper/businesses/categories/{category_code}/fields",
    "/api/v1/shopkeeper/businesses/shops/{shop_id}/capability-fields",
)


def main() -> int:
    from app.main import app  # noqa: E402 - needs the path above

    live = app.openapi()
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    paths = contract.setdefault("paths", {})

    added, missing = [], []
    for path in WANTED:
        if path not in live["paths"]:
            missing.append(path)
            continue
        if path in paths:
            continue
        paths[path] = live["paths"][path]
        added.append(path)

    if added:
        CONTRACT.write_text(
            json.dumps(contract, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    print(f"added {len(added)}, missing-from-app {len(missing)}")
    for path in added:
        print(f"  + {path}")
    for path in missing:
        print(f"  ! not in the app: {path}")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())