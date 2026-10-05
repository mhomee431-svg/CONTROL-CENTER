"""DEPENDENCY DECLARATION — the app must never import a package that a fresh
environment does not install.

`POST /shopkeeper/auth/profile-create` imported `slugify` inside the handler to
build `Shop.slug`, but `python-slugify` was never in `requirements.txt`. On a
clean install — CI, the container image, the Lambda zip — that import raised
`ModuleNotFoundError`, the endpoint returned 500, and **no shopkeeper could
finish onboarding**. The whole suite still passed, because no test exercised
that line.

A dependency imported only inside a function is invisible to module import and
to the rest of the suite, so it is checked here against the declared
requirements instead.
"""

import ast
import re
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]

# PyPI distribution name -> importable module name.
REQUIREMENT_TO_MODULE = {
    "python-slugify": "slugify",
    "python-jose": "jose",
    "pydantic-settings": "pydantic_settings",
    "python-multipart": "multipart",
    "email-validator": "email_validator",
}


def _declared_requirements() -> set:
    text = (BACKEND_DIR / "requirements.txt").read_text(encoding="utf-8")
    names = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        # The distribution name is whatever precedes any version/extras marker.
        name = re.split(r"[<>=!~\[; ]", line, maxsplit=1)[0].strip().lower()
        if name:
            names.add(name)
    return names


def _imported_top_level_modules() -> set:
    """Every top-level module imported anywhere under `app/`.

    Parsed with `ast` rather than grepped, so a name inside a string or a
    comment cannot masquerade as a real dependency.
    """
    modules = set()
    for path in (BACKEND_DIR / "app").rglob("*.py"):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        except SyntaxError:  # pragma: no cover - other suites cover this
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    modules.add(alias.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom):
                # level > 0 is a relative import ("from .x import y").
                if node.level == 0 and node.module:
                    modules.add(node.module.split(".")[0])
    return modules


def test_every_mapped_third_party_import_is_declared():
    """Every import that maps to a known distribution must be in requirements.

    Only distributions that map unambiguously are checked — an unmapped import
    produces silence rather than a false alarm, which is the right trade for a
    guard like this.
    """
    declared = _declared_requirements()
    imported = _imported_top_level_modules()

    missing = sorted(
        f"{distribution} (imported as '{module}')"
        for distribution, module in REQUIREMENT_TO_MODULE.items()
        if module in imported and distribution not in declared
    )
    assert not missing, (
        "these packages are imported by app/ but are NOT declared in "
        "requirements.txt — a clean install will crash at runtime:\n"
        + "\n".join(missing)
    )


def test_slugify_is_importable_and_declared():
    """The specific dependency that broke onboarding.

    Named explicitly instead of being left to the generic scan, because this is
    the one that already shipped broken — and its failure mode is not a wrong
    answer, it is a 500 on the endpoint every first-time shopkeeper must pass
    through.
    """
    import slugify

    assert callable(slugify.slugify), "slugify must expose slugify()"
    assert "python-slugify" in _declared_requirements(), (
        "python-slugify must stay declared so a clean install keeps working"
    )
    # `Shop.slug` is built from this, so it has to be URL-safe.
    assert slugify.slugify("Ramesh Kirana Store") == "ramesh-kirana-store"


def _enum_definitions():
    """Every `enum.Enum` subclass defined under `app/models`, with its members."""
    import ast
    import enum as enum_mod

    enums = {}
    for path in sorted((BACKEND_DIR / "app" / "models").rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        module = str(path.relative_to(BACKEND_DIR)).replace("\\", "/")
        module = module[: -len(".py")].replace("/", ".")
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            if not any("Enum" in ast.unparse(b) for b in node.bases):
                continue
            # Only true `enum.Enum` subclasses, not plain classes or StrEnum
            # lookalikes that would give false members.
            resolved = getattr(
                __import__(module, fromlist=[node.name]), node.name, None
            )
            if not (isinstance(resolved, type) and issubclass(resolved, enum_mod.Enum)):
                continue
            enums[(module, node.name)] = {m.name for m in resolved}
    return enums


def test_no_debug_or_probe_scripts_were_left_behind():
    """Scratch files must not ship.

    Debug probes written to investigate an issue are easy to leave behind: a
    `_probe_*.py` under `backend/` or a `probe_test.dart` at an app ROOT (not
    under `test/`) both escape the usual `flutter analyze lib test` and the
    pytest run, so they sit in the repo looking like harmless noise while
    carrying untyped stubs and `print()` calls. One shipped that way.

    The candidate set is `git status --untracked-files=all`, which is exactly
    the right one: it already excludes tracked files (someone committed
    `_debug_dio_test.dart` on purpose, and flagging that would be
    second-guessing a prior decision) and excludes anything `.gitignore` covers
    (so `storage/chrome_run.log.err` is not flagged — it cannot ship anyway).
    What remains is precisely "a new file that would be committed".
    """
    import subprocess
    from pathlib import Path

    repo = Path(__file__).resolve().parents[2]

    scratch_names = {
        "_enumscan.py",
        "probe_test.dart",
    }
    scratch_prefixes = ("_probe", "_check_", "_debug_", "_tmp_")
    # PowerShell redirection leaves `foo.out` / `foo.err` behind when a command
    # is piped, and those land in the repo as permanently as a stray probe.
    scratch_suffixes = (".out", ".err")

    result = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:  # git unavailable / not a repo — cannot judge
        print("git unavailable; skipping the scratch-file sweep")
        return

    offenders = []
    for line in result.stdout.splitlines():
        if not line.startswith("??"):
            continue
        rel = line[3:].strip().replace("\\", "/")
        name = rel.rsplit("/", 1)[-1]
        if (
            name in scratch_names
            or name.startswith(scratch_prefixes)
            or name.endswith(scratch_suffixes)
        ):
            offenders.append(rel)

    assert not offenders, (
        "scratch/debug files are present in the repo and WOULD be committed — "
        "delete them:\n" + "\n".join(sorted(offenders))
    )


def test_pyright_keeps_the_rules_that_catch_real_defects():
    """The lint config must not silence the checks that earned their keep.

    `pyrightconfig.json` runs `strict` over a short include list, but VS Code
    applies the mode workspace-wide — which buried ~60 `reportUnknown*`
    ergonomics hints in `shopkeeper_auth.py`. Those are switched off, which is
    correct: none of them ever identified a defect here.

    Two rules are NOT switched off, because between them they found the two
    release-blocking bugs that made `/shopkeeper/auth/profile-create` return 500
    for every new shopkeeper:

      reportMissingImports       — `slugify` was never in requirements.txt
      reportAttributeAccessIssue — `LocationStatus.PENDING` does not exist

    Silencing the whole report to make the Problems panel look clean would have
    hidden exactly those two. This pins the split so a future tidy-up cannot
    trade the two valuable rules away for a quieter IDE.
    """
    import json
    import re
    from pathlib import Path

    # The config lives at the repo root, not next to this file.
    config_path = Path(__file__).resolve().parents[2] / "pyrightconfig.json"
    assert config_path.exists(), "pyrightconfig.json disappeared"

    raw = config_path.read_text(encoding="utf-8")
    # It is JSONC, so comments must be stripped before parsing.
    config = json.loads(re.sub(r"^\s*//.*$", "", raw, flags=re.MULTILINE))

    assert config.get("typeCheckingMode") == "strict", (
        "the author's strictness choice was silently downgraded"
    )

    # The sign-in surface must stay tracked, so its valuable checks run on it.
    assert any("shopkeeper_auth" in p for p in config["include"]), (
        "shopkeeper_auth.py must stay in the tracked include list"
    )

    for rule in ("reportMissingImports", "reportAttributeAccessIssue"):
        assert config.get(rule) != "none", (
            f"{rule} must stay enabled — it caught a shipped production defect"
        )


def test_no_code_references_an_enum_member_that_does_not_exist():
    """Referencing a missing enum member raises AttributeError at runtime.

    That is how `/shopkeeper/auth/profile-create` shipped three of them —
    `LocationStatus.PENDING`, `LocationSource.UNKNOWN` and
    `LocationType.UNKNOWN` — so the endpoint returned 500 for every new
    shopkeeper. Nothing caught it: the names are valid Python, so a linter that
    cannot resolve the enum (or a test that never builds a `Shop`) passes.

    This resolves each enum for real and compares the member names, so a typo
    fails here instead of in production.
    """
    import ast

    enums = _enum_definitions()
    assert len(enums) > 10, (
        f"sanity: expected the model's enums to be discovered, found {len(enums)}"
    )

    offenders = []
    for path in sorted((BACKEND_DIR / "app").rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))

        # Map local alias -> (module, class) for from-imports only. Attribute
        # access on an unknown name cannot be resolved without executing code.
        imported = {}
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
                for alias in node.names:
                    imported[alias.asname or alias.name] = (node.module, alias.name)

        for node in ast.walk(tree):
            if not (isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name)):
                continue
            key = imported.get(node.value.id)
            if key is None or key not in enums:
                continue
            if node.attr not in enums[key]:
                # `__members__` is a real class-level mapping on Enum, not a
                # member — `ShopCategory.__members__` is the standard way to
                # test membership, so flagging it would be a false alarm.
                if node.attr.startswith("__"):
                    continue
                rel = path.relative_to(BACKEND_DIR)
                offenders.append(
                    f"{rel}:{node.lineno}: `{node.value.id}.{node.attr}` is not a "
                    f"member of {key[1]} (has: {', '.join(sorted(enums[key]))})"
                )

    assert not offenders, (
        "these enum members do not exist and would raise AttributeError:\n"
        + "\n".join(sorted(set(offenders)))
    )
