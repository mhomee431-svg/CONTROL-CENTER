#!/usr/bin/env bash
#
# Build the Customer Flutter app for PRODUCTION (Android release APK).
#
# Usage:
#   API_BASE_URL=https://api.yourdomain.com/v1  \
#   MAPS_API_KEY=<your maps key>                 \
#   ./scripts/build_customer_prod.sh
#
# Ensures API_BASE_URL is set (fails fast) and injects keys at compile time —
# they never live in the repository or runtime configuration.
set -euo pipefail

cd "$(dirname "$0")/../Frontend"

: "${API_BASE_URL:?API_BASE_URL is required (e.g. https://api.example.com/v1)}"
: "${MAPS_API_KEY:?MAPS_API_KEY is required for maps in production}"

flutter pub get
flutter analyze
flutter test

flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=MAPS_API_KEY="$MAPS_API_KEY"

echo "✅ APK: Frontend/build/app/outputs/flutter-apk/app-release.apk"