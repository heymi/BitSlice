#!/usr/bin/env bash
# Upload BeCut.pkg to App Store Connect / TestFlight (macOS).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:-$ROOT_DIR/.asc/artifacts/export/BeCut.pkg}"
APP_ID="${ASC_APP_ID:-6790153670}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ ! -f "$PKG" ]]; then
  echo "Missing package: $PKG" >&2
  echo "Build first: archive + export to .asc/artifacts/export/BeCut.pkg" >&2
  exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER=$(asc builds next-build-number --app "$APP_ID" --version "$VERSION" --platform MAC_OS 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextBuildNumber') or '1')" 2>/dev/null || echo "1")
fi

echo "→ upload $PKG to app $APP_ID (v$VERSION build $BUILD_NUMBER)"
asc builds upload \
  --app "$APP_ID" \
  --pkg "$PKG" \
  --platform MAC_OS \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --wait \
  --pretty

echo "→ mark export compliance (no non-exempt encryption)"
asc builds update --app "$APP_ID" --latest --uses-non-exempt-encryption=false --pretty || true

echo "→ done. Assign testers / beta groups in App Store Connect or via asc testflight."
