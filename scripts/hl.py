#!/usr/bin/env python3
"""hl - the single command for this repository.

THE ONE IDEA
------------
Every quality check in this project runs through ONE function in this file.
GitHub Actions calls the same functions, with the same arguments, in the same
order. That is the whole design, and it is what stops "works on my machine"
from ever becoming a category of bug: there is no second implementation of the
gate for CI to drift away from.

    hl check          fast gate - what you run before every push
    hl test           the full suite - what CI runs
    hl ci             both, in CI order, with CI exit codes

WHAT THIS REPLACES
------------------
The repository grew 35 individual scripts (scripts/dev/test.sh, test.ps1,
stack.ps1, build_*.bat, ...) that disagree with each other and with CI:
``scripts/dev/test.sh`` requires ``backend/.venv/bin/python``, which does not
exist on a GitHub runner. Each of those is a place where "it worked for me" can
be true and the build still be red.

``hl`` does not delete them - they still work, and some are still the right
tool for their job. It is the single entry point, so there is one answer to
"how do I run the tests" instead of five.

WHY ``.py`` AND NOT AN EXTENSIONLESS ``hl``
-------------------------------------------
An extensionless executable is not executable on Windows without extra setup
(``PATHEXT`` does not cover it), and this project is developed on Windows. A
``.py`` file runs identically on all three platforms with the same command, so
the docs can give one instruction that is true everywhere.

RUNNING IT
----------
    python scripts/hl.py                  # help
    python scripts/hl.py test --scope be
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Reconfigure the console to UTF-8 BEFORE anything is printed.
#
# Windows consoles default to cp1252, and pytest's own output contains
# characters outside it (arrows in assertion output, box-drawing in diffs). The
# result is `UnicodeEncodeError` raised from inside this script while echoing a
# perfectly healthy test run - the tool crashes on success, which is the worst
# possible failure mode.
#
# `errors="replace"` means an exotic character degrades to `?` instead of
# killing the run. The log file written by run_logged is always UTF-8 regardless,
# because it opens with an explicit encoding.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        # Older interpreters, or a stream that is not reconfigurable (a pipe
        # under some CI loggers). Not worth failing over: the worst case is the
        # original encoding error, which is what we are avoiding.
        pass


ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
SHOPKEEPER = ROOT / "apps" / "shopkeeper_app"
CUSTOMER = ROOT / "apps" / "customer_app"

# The blocking Ruff rule set. Identical to `select` in backend/pyproject.toml.
# Duplicated deliberately: this is the value CI uses, and a lint gate that
# only works when run from one directory is a gate that silently does not run.
RUFF_GATE = ("E9", "F63", "F7", "F82")

# The wider set: real but noisy, mechanical, and NOT a merge blocker. Run it to
# clean up, not to gate. See the note in backend/pyproject.toml.
RUFF_BROAD = ("E4", "E7", "F401", "F841", "I", "UP", "SIM", "C4", "RUF")


class Console:
    """Minimal, zero-dependency output.

    Deliberately not `rich`/`colorama`: this file must run before any
    dependency is installed - `hl doctor` is how you find out what is missing -
    so it may only use the standard library.
    """

    def __init__(self) -> None:
        self.failed: list[str] = []

    @staticmethod
    def c(text: str, code: str) -> str:
        # Colour only on a real terminal. Red text in a CI log file is just
        # noise around the actual error.
        if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
            return text
        return f"\033[{code}m{text}\033[0m"

    def step(self, text: str) -> None:
        print(f"\n{self.c('==>', '36')} {text}")

    def ok(self, text: str) -> None:
        print(f"  {self.c('PASS', '32')} {text}")

    def bad(self, text: str) -> None:
        self.failed.append(text)
        print(f"  {self.c('FAIL', '31')} {text}")

    def warn(self, text: str) -> None:
        print(f"  {self.c('WARN', '33')} {text}")

    def info(self, text: str) -> None:
        print(f"       {text}")


C = Console()


def run(
    cmd: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    quiet: bool = False,
) -> int:
    """Run a command and return its exit code. Never raises."""
    full_env = {**os.environ, **(env or {})}
    full_env.setdefault("PYTHONIOENCODING", "utf-8")

    # Resolve the executable through PATH before handing it to the OS.
    # On Windows `flutter` is `C:\flutter\bin\flutter.BAT`, and
    # `subprocess.run(["flutter", ...])` does NOT apply PATHEXT: it raises
    # FileNotFoundError even though `shutil.which` finds it, and even though
    # the same command typed into the shell works. Resolving first makes the
    # behaviour identical on Windows, Linux and macOS, which is the entire
    # point of having one command.
    if cmd and not Path(cmd[0]).is_absolute():
        resolved = shutil.which(cmd[0])
        if resolved:
            cmd = [resolved, *cmd[1:]]

    try:
        if quiet:
            return subprocess.run(
                cmd, cwd=str(cwd or ROOT), env=full_env,
                check=False, capture_output=True,
            ).returncode
        return subprocess.run(
            cmd, cwd=str(cwd or ROOT), env=full_env, check=False
        ).returncode
    except FileNotFoundError:
        C.bad(f"command not found: {cmd[0]}")
        return 127


LOG_DIR = ROOT / "build" / "logs"


def run_logged(
    cmd: list[str],
    log_name: str,
    cwd: Path | None = None,
) -> int:
    """Run a command, echoing output live AND writing it to `build/logs/<name>`.

    A CI failure is diagnosed from a log, not from scrolling a runner's
    terminal output. Writing the log is what makes the GitHub artifact step in
    ci.yml meaningful rather than decorative.

    Output is STREAMED, line by line, rather than collected and printed at the
    end. The backend suite runs ~3 minutes and the Flutter suites ~6 each;
    buffering all of that means several minutes of a completely silent terminal,
    which is indistinguishable from a hang - and a hang you cannot distinguish
    from a slow run is a hang you sit and wait through. Streaming also means the
    log is complete even if the run is cancelled, which is exactly when you most
    want what it printed so far.

    The log lives under `build/`, which every Flutter project already
    gitignores, so these logs cannot become the committed scratch files this
    whole tool exists to prevent.
    """
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / log_name

    resolved = list(cmd)
    if resolved and not Path(resolved[0]).is_absolute():
        found = shutil.which(resolved[0])
        if found:
            resolved = [found, *resolved[1:]]

    print(f"  (full output: {log_path.relative_to(ROOT)})")
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    try:
        proc = subprocess.Popen(
            resolved,
            cwd=str(cwd or ROOT),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except FileNotFoundError:
        C.bad(f"command not found: {cmd[0]}")
        return 127

    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        assert proc.stdout is not None
        for raw_line in proc.stdout:
            line = raw_line.decode("utf-8", "replace")
            log.write(line)
            # Flush the log as well as the terminal. Python buffers file writes,
            # so without this the "cancelled runs keep their partial log"
            # property above is not actually true: the file would still be
            # empty when the run is killed, which is exactly the case it was
            # written for.
            log.flush()
            sys.stdout.write(line)
            sys.stdout.flush()
    return proc.wait()

def need(tool: str, hint: str) -> bool:
    if shutil.which(tool):
        return True
    C.bad(f"`{tool}` is not on PATH")
    C.info(hint)
    return False


def need_python_module(module: str, package: str) -> bool:
    """Check that a Python package is importable by THIS interpreter.

    Separate from `need()` because `python -m ruff` and `python -m pytest`
    work when the console script is not on PATH: both are often installed into
    the interpreter rather than exposed as an executable. Checking
    `shutil.which("ruff")` there reports a missing tool on a machine where the
    very next line succeeds - a false alarm that teaches you to ignore the
    report.
    """
    if run([sys.executable, "-c", f"import {module}"], quiet=True) == 0:
        return True
    C.bad(f"`{module}` is not importable by {sys.executable}")
    C.info(f"  pip install {package}")
    return False


# -- doctor -------------------------------------------------------------------

def cmd_doctor(_: argparse.Namespace) -> int:
    """Report what is installed and what is missing.

    Run this first when something behaves differently than it should. The most
    common cause of a local-only failure is a version mismatch, and this prints
    versions so diagnosis does not require guesswork.
    """
    C.step("Toolchain")
    if sys.version_info >= (3, 11):
        C.ok(f"python {sys.version.split()[0]}")
    else:
        C.bad(f"python {sys.version.split()[0]} (need >= 3.11)")
    C.info(f"  {sys.executable}")

    for tool, hint in (
        ("git", "Install Git for Windows: https://git-scm.com/download/win"),
        ("flutter", "Install Flutter: flutter.dev/get-started/install"),
        ("dart", "Ships with Flutter; run `flutter doctor` if missing"),
    ):
        if shutil.which(tool):
            C.ok(f"{tool} present")
        else:
            C.warn(f"{tool} is not on PATH")
            C.info(hint)

    C.step("Python packages")
    for module, extra in (
        ("pytest", "pip install -r backend/requirements.txt"),
        ("ruff", "pip install ruff"),
        ("yaml", "pip install pyyaml"),
        ("alembic", "pip install -r backend/requirements.txt"),
    ):
        if run([sys.executable, "-c", f"import {module}"], quiet=True) == 0:
            C.ok(module)
        else:
            C.warn(f"{module} is not importable")
            C.info(extra)

    C.step("Flutter apps")
    for name, path in (("shopkeeper", SHOPKEEPER), ("customer", CUSTOMER)):
        if (path / "pubspec.yaml").exists():
            C.ok(f"{name}: pubspec.yaml present")
        else:
            C.bad(f"{name}: pubspec.yaml missing at {path}")

    if C.failed:
        print("\nSome required tooling is missing. Fix the FAIL lines above.")
        return 1
    print("\nEverything required is present.")
    return 0


# -- lint ---------------------------------------------------------------------

def cmd_lint(args: argparse.Namespace) -> int:
    """The blocking lint gate."""
    C.step("Backend lint (gate rules)")
    if not need_python_module("ruff", "ruff"):
        return 127
    # `--no-fix`: a lint gate must REPORT. If it also rewrote files, the
    # developer would see a clean pass over code they never wrote, and the gate
    # would be silently editing the very diff it is supposed to judge.
    rules = RUFF_BROAD if args.broad else RUFF_GATE
    rc = run(
        [sys.executable, "-m", "ruff", "check",
         "--no-fix", "--select", ",".join(rules), "app", "tests"],
        cwd=BACKEND,
    )
    if rc == 0:
        C.ok(f"ruff {' '.join(rules)}")
    else:
        C.bad("ruff findings (see above)")
        if not args.broad:
            C.info("These block because each is a construct that fails at "
                   "import, fails at runtime, or is silently wrong.")
    return rc


def cmd_lint_fix(_: argparse.Namespace) -> int:
    """Apply the mechanical, non-blocking fixes. Never a merge gate."""
    C.step("Backend lint: mechanical autofix (optional rules)")
    if not need_python_module("ruff", "ruff"):
        return 127
    C.info("These rules are real but noisy. Review the diff before committing.")
    run(
        [sys.executable, "-m", "ruff", "check", "--fix",
         "--select", ",".join(RUFF_BROAD), "app", "tests"],
        cwd=BACKEND,
    )
    C.ok("fixable findings applied - review `git diff` before committing")
    return 0



# -- analyze / test -----------------------------------------------------------

def cmd_analyze(args: argparse.Namespace) -> int:
    """flutter analyze for one or both apps."""
    targets = []
    if args.scope in ("all", "sk"):
        targets.append(("shopkeeper", SHOPKEEPER))
    if args.scope in ("all", "cu"):
        targets.append(("customer", CUSTOMER))

    if not need("flutter", "Install Flutter: flutter.dev/get-started/install"):
        return 127

    rc = 0
    for name, path in targets:
        C.step(f"flutter analyze - {name}")
        # --no-pub: analysing must not reach the network. A check that runs pub
        # depends on the network, and a flaky network then looks like a code
        # failure. Resolving packages is `hl doctor`'s job, not the gate's.
        if run(["flutter", "analyze", "--no-pub"], cwd=path) == 0:
            C.ok(f"{name}: no issues")
        else:
            C.bad(f"{name}: analyzer issues (see above)")
            rc = 1
    return rc


def cmd_test(args: argparse.Namespace) -> int:
    """Run the test suites."""
    scope = args.scope
    rc = 0

    if scope in ("all", "be"):
        C.step("Backend tests (pytest)")
        extra: list[str] = []
        if getattr(args, "verbose", False):
            extra.append("-v")
        if getattr(args, "filter", None):
            extra += ["-k", args.filter]
        if run_logged([sys.executable, "-m", "pytest", "-q", *extra],
                     "pytest_output.txt", cwd=BACKEND) == 0:
            C.ok("backend: all tests passed")
        else:
            C.bad("backend: failures (see above)")
            rc = 1

    if scope in ("all", "sk"):
        C.step("Shopkeeper app tests (flutter test)")
        if not need("flutter", "Install Flutter"):
            return 127
        if _flutter_test(SHOPKEEPER, args.concurrency,
                             "flutter_shopkeeper_output.txt"):
            C.ok("shopkeeper: all tests passed")
        else:
            C.bad("shopkeeper: failures (see above)")
            rc = 1

    if scope in ("all", "cu"):
        C.step("Customer app tests (flutter test)")
        if not need("flutter", "Install Flutter"):
            return 127
        if _flutter_test(CUSTOMER, args.concurrency,
                             "flutter_customer_output.txt"):
            C.ok("customer: all tests passed")
        else:
            C.bad("customer: failures (see above)")
            rc = 1

    return rc


def _flutter_test(path: Path, concurrency: int, log_name: str) -> bool:
    """Run `flutter test` in one app directory.

    `--concurrency=1` by default. A higher value starves a small machine, and on
    a OneDrive checkout concurrent reads of the same files can stall forever. A
    slow-but-finite suite beats a fast one that hangs, because a hang is
    indistinguishable from a genuinely broken build - and you debug the wrong
    thing.
    """
    return run_logged(
        ["flutter", "test", "--no-pub", f"--concurrency={concurrency}"],
        log_name, cwd=path,
    ) == 0


# -- migrations ---------------------------------------------------------------

def cmd_migrations(_: argparse.Namespace) -> int:
    """Verify the Alembic chain: linear, single head, no duplicate revisions.

    This is the check that catches a merge accident. Two migrations claiming the
    same revision number is invisible until Alembic refuses to run - and on a
    deployed database that is a production incident, not a red test.
    """
    C.step("Migration chain")
    versions = BACKEND / "alembic" / "versions"
    if not versions.is_dir():
        C.warn(f"no versions directory at {versions}")
        return 0

    revisions: dict[str, str] = {}
    downs: dict[str, str | None] = {}
    for path in sorted(versions.glob("*.py")):
        text = path.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"^revision[^=]*=\s*['\"]([^'\"]+)", text, re.M)
        d = re.search(r"^down_revision[^=]*=\s*(.+)$", text, re.M)
        if m is None:
            C.bad(f"{path.name}: no `revision = ...` found")
            continue
        rev = m.group(1)
        if rev in revisions:
            C.bad(f"duplicate revision {rev}: "
                  f"{revisions[rev]} and {path.name}")
            continue
        revisions[rev] = path.name
        raw = d.group(1).strip() if d else "None"
        downs[rev] = None if raw == "None" else raw.strip("'\"")

    if C.failed:
        return 1

    children: dict[str, list[str]] = {}
    roots: list[str] = []
    for rev, down in downs.items():
        if down is None:
            roots.append(rev)
        else:
            children.setdefault(down, []).append(rev)

    for parent, kids in children.items():
        if parent not in revisions:
            C.bad(f"{revisions.get(parent, '?')} declares down_revision "
                  f"'{parent}', which does not exist")
        if len(kids) > 1:
            C.bad(f"revision {parent} has {len(kids)} children: "
                  f"{', '.join(sorted(kids))} (a branch, not a line)")

    if len(roots) > 1:
        C.bad(f"{len(roots)} roots: {', '.join(sorted(roots))} "
              "(there must be exactly one base revision)")
    elif roots:
        C.ok(f"single base revision {roots[0]}")

    heads = [r for r in revisions if r not in children]
    if len(heads) > 1:
        C.bad(f"{len(heads)} heads: {', '.join(sorted(heads))} "
              "(alembic refuses to run: 'multiple heads')")
    elif heads:
        C.ok(f"single head {heads[0]} ({revisions[heads[0]]})")

    C.ok(f"{len(revisions)} revisions, chain is linear")
    return 1 if C.failed else 0


# -- secrets ------------------------------------------------------------------

def cmd_secrets(_: argparse.Namespace) -> int:
    """Scan the working tree for credential-shaped content."""
    C.step("Secret scan")
    scanner = ROOT / "scripts" / "security" / "scan_secrets.py"
    if not scanner.exists():
        C.warn(f"scanner not found at {scanner}")
        return 0
    # `--tracked` scans exactly what git has staged/tracked, which is the
    # question that matters. The scanner requires an explicit scope.
    return run([sys.executable, str(scanner), "--tracked"])



# -- the gates ----------------------------------------------------------------

def _conflict_markers() -> bool:
    """Look for `<<<<<<<` in tracked text files.

    Scoped to `git ls-files` rather than the whole tree: this must be fast, and
    it must not depend on what happens to be lying in the working directory.
    """
    try:
        listing = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=str(ROOT), capture_output=True, check=False,
        ).stdout.decode("utf-8", "replace").split("\0")
    except OSError:
        return False

    TEXT = {".py", ".dart", ".ts", ".js", ".yml", ".yaml", ".json", ".md",
            ".sh", ".ps1", ".bat", ".cmd", ".toml", ".ini", ".cfg"}
    offenders: list[str] = []
    for rel in filter(None, listing):
        path = ROOT / rel
        if path.suffix.lower() not in TEXT or not path.is_file():
            continue
        try:
            if path.stat().st_size > 2_000_000:
                continue
            body = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for n, line in enumerate(body.splitlines(), 1):
            if line.lstrip().startswith(("<<<<<<< ", ">>>>>>> ")):
                offenders.append(f"{rel}:{n}")

    if offenders:
        C.bad(f"{len(offenders)} conflict marker(s): "
              + ", ".join(offenders[:6])
              + (" ..." if len(offenders) > 6 else ""))
        C.info("Resolve with `git status`; UU entries are the unresolved ones.")
        return True
    return False


def cmd_check(args: argparse.Namespace) -> int:
    """The fast gate. Run this before every push.

    Everything here is either seconds, or something that must never be true and
    so is cheap to verify. No test suite: a gate you skip when you are in a
    hurry is a gate that catches nothing.
    """
    started = time.time()
    rc = 0

    C.step("1/5 Lint (backend gate rules)")
    rc |= cmd_lint(argparse.Namespace(broad=False))

    C.step("2/5 Analyzer (Flutter)")
    rc |= cmd_analyze(argparse.Namespace(scope=args.scope))

    C.step("3/5 Migration chain")
    rc |= cmd_migrations(argparse.Namespace())

    C.step("4/5 Conflict markers in tracked files")
    if _conflict_markers():
        rc = 1
    else:
        C.ok("no conflict markers")

    C.step("5/5 Secrets")
    rc |= cmd_secrets(argparse.Namespace())

    C.step("Summary")
    if rc == 0:
        C.ok(f"check passed in {time.time() - started:.0f}s")
        print("\n  Next:  python scripts/hl.py test")
    else:
        C.bad("check FAILED - do not push until this is green")
    return rc


def cmd_ci(args: argparse.Namespace) -> int:
    """Exactly what CI runs, in CI's order, with CI's exit codes.

    Green here means CI cannot surprise you. Red here means you have not wasted
    a push to find out.
    """
    started = time.time()
    rc = 0

    C.step("STAGE 1 - static analysis and fast gates")
    rc |= cmd_check(args)

    C.step("STAGE 2 - full test suite")
    rc |= cmd_test(args)

    print()
    if rc == 0:
        print(f"{C.c('CI WOULD PASS', '32')}  ({time.time() - started:.0f}s total)")
    else:
        print(f"{C.c('CI WOULD FAIL', '31')}  ({time.time() - started:.0f}s total)")
    return rc



# -- hooks / clean ------------------------------------------------------------

def cmd_hooks(args: argparse.Namespace) -> int:
    """Install or verify the pre-commit hooks."""
    if args.hooks_action == "install":
        C.step("Installing pre-commit hooks")
        if not need("pre-commit", "pip install pre-commit"):
            return 127
        rc = run([sys.executable, "-m", "pre_commit", "install"])
        if rc == 0:
            C.ok("hook installed - it runs on every `git commit` from now on")
            C.info("Verify it works:  python scripts/hl.py hooks verify")
        return rc

    # verify
    C.step("Verifying the pre-commit hook is installed")
    installed = ROOT / ".git" / "hooks" / "pre-commit"
    if not installed.exists():
        C.bad(f"no hook at {installed}")
        C.info("Run:  python scripts/hl.py hooks install")
        return 1
    C.ok(f"hook present at {installed}")
    if installed.stat().st_size == 0:
        C.bad("the hook file is empty - re-run `hl hooks install`")
        return 1

    C.step("Self-test: each hook must not flag its own documentation")
    rc = 0
    for script in sorted((ROOT / "scripts" / "hl").glob("hooks_*.py")):
        if run([sys.executable, str(script), str(script)], quiet=True) == 0:
            C.ok(f"{script.name} clean on itself")
        else:
            C.bad(f"{script.name} flags its own documentation")
            rc = 1
    return rc


def cmd_clean(_: argparse.Namespace) -> int:
    """Delete generated scratch output. Never touches tracked source.

    The file list comes from `git ls-files --others --ignored` rather than a
    filesystem walk. A walk has to descend into `.dart_tool/`, `build/` and
    `node_modules/`, which on this repository is tens of thousands of files and
    takes longer than the command is worth; git already knows exactly which
    files are untracked-and-ignored, and can say so in milliseconds.

    The double guard is deliberate: the query already excludes tracked files,
    and the explicit `git ls-files --error-unmatch` re-check means that even if
    the first filter were wrong, this command still refuses to delete anything
    git is tracking. Deleting source is the one thing `hl clean` must never do.
    """
    C.step("Clean generated scratch output")
    patterns = ("pytest_*.txt", "pytest_*.log", "scoped_pytest.log",
                "backend_log.txt", "alembic_bg.txt", "analyze*.txt",
                "ruff_fmt*.txt", "*_out.txt", "*_err.txt")

    try:
        listing = subprocess.run(
            ["git", "ls-files", "--others", "--ignored",
             "--exclude-standard", "-z"],
            cwd=str(ROOT), capture_output=True, check=False,
        ).stdout.decode("utf-8", "replace").split("\0")
    except OSError as exc:
        C.bad(f"could not list untracked files: {exc}")
        return 1

    import fnmatch

    removed = skipped = 0
    for rel in filter(None, listing):
        if not any(fnmatch.fnmatch(rel, p) for p in patterns):
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        # Belt and braces: never delete something git tracks.
        if subprocess.run(
            ["git", "ls-files", "--error-unmatch", rel],
            cwd=str(ROOT), capture_output=True, check=False,
        ).returncode == 0:
            skipped += 1
            continue
        try:
            size = path.stat().st_size
            if size > 5_000_000:
                C.warn(f"skipping {rel} ({size} bytes - too large to be scratch)")
                continue
            path.unlink()
            removed += 1
        except OSError:
            pass

    C.ok(f"removed {removed} generated file(s)")
    if skipped:
        C.warn(f"{skipped} were TRACKED and were left alone")
    return 0

# -- CLI ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hl",
        description="The single command for this repository. Local and CI run "
                    "the same code, so a green `hl ci` means a green build.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Typical use:\n"
            "  hl doctor          first run: check the toolchain\n"
            "  hl hooks install   once: stop problems before they are committed\n"
            "  hl check           every time, before you push\n"
            "  hl test            before opening a pull request\n"
            "  hl ci              exactly what GitHub Actions runs\n"
        ),
    )
    sub = p.add_subparsers(dest="task", required=True)

    sub.add_parser("doctor", help="report installed tooling and what is missing"
                   ).set_defaults(func=cmd_doctor)

    lint = sub.add_parser("lint", help="blocking lint gate (backend)")
    lint.add_argument("--broad", action="store_true",
                      help="use the wider, non-blocking rule set")
    lint.set_defaults(func=cmd_lint)

    sub.add_parser("lint:fix", help="apply mechanical fixes (optional rules)"
                   ).set_defaults(func=cmd_lint_fix)

    an = sub.add_parser("analyze", help="flutter analyze")
    an.add_argument("--scope", choices=["all", "sk", "cu"], default="all")
    an.set_defaults(func=cmd_analyze)

    t = sub.add_parser("test", help="run the test suites")
    t.add_argument("--scope", choices=["all", "be", "sk", "cu"], default="all",
                   help="all | be (backend) | sk (shopkeeper) | cu (customer)")
    t.add_argument("-k", "--filter", default=None,
                   help="pytest -k expression (backend only)")
    t.add_argument("-v", "--verbose", action="store_true",
                   help="pytest -v (backend only)")
    t.add_argument("--concurrency", type=int, default=1,
                   help="flutter test concurrency (default 1: reliable)")
    t.set_defaults(func=cmd_test)

    chk = sub.add_parser(
        "check",
        help="the fast gate: lint, analyze, migrations, conflicts, secrets")
    chk.add_argument("--scope", choices=["all", "sk", "cu"], default="all")
    chk.set_defaults(func=cmd_check)

    ci = sub.add_parser("ci", help="exactly what CI runs")
    ci.add_argument("--scope", choices=["all", "be", "sk", "cu"], default="all")
    ci.add_argument("-k", "--filter", default=None)
    ci.add_argument("-v", "--verbose", action="store_true")
    ci.add_argument("--concurrency", type=int, default=1)
    ci.set_defaults(func=cmd_ci)

    sub.add_parser("migrations",
                   help="verify the Alembic chain is linear"
                   ).set_defaults(func=cmd_migrations)
    sub.add_parser("secrets", help="scan for credentials"
                   ).set_defaults(func=cmd_secrets)
    sub.add_parser("clean", help="delete generated scratch output"
                   ).set_defaults(func=cmd_clean)

    hk = sub.add_parser("hooks", help="install or verify the pre-commit hooks")
    hk.add_argument("hooks_action", choices=["install", "verify"])
    hk.set_defaults(func=cmd_hooks)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args) or 0)
    except KeyboardInterrupt:
        print("\ninterrupted")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())

