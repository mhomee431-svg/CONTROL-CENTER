#!/usr/bin/env bash
#
# Build the Shopkeeper Flutter app for PRODUCTION (Android release APK).
#
# Usage:
#   API_BASE_URL=https://api.yourdomain.com/v1  \
#   ./scripts/build_shopkeeper_prod.sh
#
# Demo login is forced OFF for production builds.
set -euo pipefail

cd "$(dirname "$0")/../apps/shopkeeper_app"

: "${API_BASE_URL:?API_BASE_URL is required (e.g. https://api.example.com/v1)}"

flutter pub get
flutter analyze
flutter test

flutter build apk --release \
  --dart-define=SHOPKEEPER_API_BASE_URL="$API_BASE_URL" \
  --dart-define=SHOPKEEPER_ENABLE_DEMO_LOGIN=false

echo "✅ APK: apps/shopkeeper_app/build/app/outputs/flutter-apk/app-release.apk"