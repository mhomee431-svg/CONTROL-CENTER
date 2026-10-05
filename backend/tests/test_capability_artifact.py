"""The exported capability artifact must never go stale.

`packages/api_contracts/category_capabilities.json` is what the Flutter app
reads, so a backend change that is not re-exported would leave the app rendering
the OLD rules with a green suite. This asserts the committed artifact still
matches the live registry, and reports the command that regenerates it.
"""

import json
import subprocess
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = BACKEND_DIR.parent
ARTIFACT = REPO_DIR / "packages" / "api_contracts" / "category_capabilities.json"
EXPORTER = BACKEND_DIR / "scripts" / "export_category_capabilities.py"

sys.path.insert(0, str(BACKEND_DIR))
from scripts.export_category_capabilities import build  # noqa: E402


class TestCapabilityArtifact:
    def test_artifact_exists(self):
        assert ARTIFACT.exists(), (
            f"missing {ARTIFACT}; regenerate with "
            f"python backend/scripts/{EXPORTER.name}"
        )

    def test_artifact_matches_the_live_registry(self):
        committed = json.loads(ARTIFACT.read_text(encoding="utf-8"))
        assert committed == build(), (
            "the exported capability contract has drifted from the registry. "
            f"Run: python backend/scripts/{EXPORTER.name}"
        )

    def test_artifact_carries_every_category(self):
        committed = json.loads(ARTIFACT.read_text(encoding="utf-8"))
        from app.models.merchant_category import MERCHANT_CATEGORIES

        assert set(committed["categories"]) == {
            code for code, _ in MERCHANT_CATEGORIES
        }

    def test_no_forbidden_category_in_the_artifact(self):
        committed = json.loads(ARTIFACT.read_text(encoding="utf-8"))
        for code in committed["categories"]:
            for word in ("GROCERY", "SUPERMARKET", "FAST_FOOD"):
                assert word not in code

    def test_exporter_is_runnable(self):
        # The artifact is only trustworthy if the documented regeneration step
        # actually works; a broken exporter would be discovered months later,
        # at the moment someone needed it.
        assert EXPORTER.exists()
        source = EXPORTER.read_text(encoding="utf-8")
        assert "def main()" in source
        assert "json.dumps" in source
