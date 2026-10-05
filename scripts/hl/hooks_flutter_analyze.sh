#!/usr/bin/env bash
# Flutter analyze, scoped to the apps a staged file belongs to.
#
# WHY A WRAPPER SCRIPT INSTEAD OF A DIRECT `flutter analyze` ENTRY
# ----------------------------------------------------------------
# Two reasons, both practical:
#
#   1. Analyzers read config from the CURRENT DIRECTORY. Running
#      `flutter analyze` from the repo root does not pick up either app's
#      `analysis_options.yaml`, so it silently analyses with different rules
#      than CI applies. Each app must be analysed from its own directory.
#
#   2. A full analyze of both apps takes ~25s. On a commit that touched one
#      Dart file in one app, analysing both is slow enough that you will
#      start reaching for `--no-verify`. Analysing only the affected app keeps
#      the hook fast enough to keep.
#
# `--no-pub` is deliberate: the hook must not reach the network. Resolving
# packages is `hl pub get`'s job, and a hook that silently runs pub would make
# a commit depend on network availability.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS=("customer_app" "shopkeeper_app")

# Derive the affected apps from the staged paths passed in by pre-commit.
affected=()
for path in "$@"; do
  case "$path" in
    apps/customer_app/*)  affected+=("customer_app") ;;
    apps/shopkeeper_app/*) affected+=("shopkeeper_app") ;;
  esac
done

if [ ${#affected[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "hl: flutter is not on PATH; skipping the Dart analyze hook." >&2
  echo "    Install Flutter, or run 'git commit --no-verify' for this commit." >&2
  exit 0
fi

# Deduplicate: many staged files usually belong to the same app.
declare -A seen=()
unique=()
for app in "${affected[@]}"; do
  if [ -z "${seen[$app]:-}" ]; then
    seen[$app]=1
    unique+=("$app")
  fi
done

status=0
for app in "${unique[@]}"; do
  echo "hl: flutter analyze -> apps/$app"
  if ! (cd "$REPO_ROOT/apps/$app" && flutter analyze --no-pub); then
    status=1
  fi
done

if [ $status -ne 0 ]; then
  cat >&2 <<'EOF'

hl: flutter analyze reported problems.

  Fix them, or run `dart format` on the files you touched. If the finding is
  pre-existing and unrelated to your change, fix it in its own commit -- a
  commit that carries an unrelated fix is the one that gets reverted wholesale.
EOF
fi

exit $status
