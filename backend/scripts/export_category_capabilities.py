"""Export the category capability registry as the cross-language contract.

The Dart app must know the same capability names and per-category sets as the
backend, but Dart cannot import a Python enum and regex-parsing a Python SOURCE
FILE is fragile — a formatting change silently breaks the check rather than
failing it. So the registry is exported here into a committed JSON artifact that
both sides read:

  * `test_capability_artifact.py`  asserts this file matches the live registry,
    so it can never go stale.
  * `capability_contract_test.dart` asserts the Dart table matches the file.

Either side drifting therefore fails the build, with no parsing in the way.
"""

import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from app.models.merchant_category import (  # noqa: E402
    BUSINESS_TYPES,
    MERCHANT_CATEGORIES,
    MERCHANT_CATEGORY_CAPABILITIES,
    resolve_capabilities,
)

OUTPUT = BACKEND_DIR.parent / "packages" / "api_contracts" / "category_capabilities.json"


def build() -> dict:
    categories = {}
    for code, name in MERCHANT_CATEGORIES:
        categories[code] = {
            "name": name,
            # The RAW table, matching what the Dart mirror stores. `_ALWAYS`
            # (CONTACT / LOCATION) is appended at resolve time on both sides.
            "capabilities": sorted(
                c.value for c in MERCHANT_CATEGORY_CAPABILITIES[code]
            ),
        }

    return {
        "_comment": (
            "Generated from backend/app/models/merchant_category.py. Do not edit "
            "by hand — run python scripts/export_category_capabilities.py. "
            "Regenerated fixtures are the contract both languages read, so "
            "neither has to parse the other's source."
        ),
        "business_types": sorted(BUSINESS_TYPES),
        "categories": categories,
        "serving_only_exclusions": sorted(
            ["PRODUCT_CATALOG", "INVENTORY", "BARCODE", "IMPORT", "POS"]
        ),
        "always_present": ["CONTACT", "LOCATION"],
        "resolution_samples": {
            f"{code}|{business_type}": sorted(
                c.value for c in (resolve_capabilities(code, business_type) or ())
            )
            for code, _ in MERCHANT_CATEGORIES
            for business_type in ("Retail", "Service")
        },
    }


def main() -> int:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(build(), indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
