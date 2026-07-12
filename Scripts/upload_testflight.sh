#!/usr/bin/env bash
# Upload BeCut.pkg to App Store Connect / TestFlight (macOS).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:-$ROOT_DIR/.asc/artifacts/export/BeCut.pkg}"
APP_ID="${ASC_APP_ID:-}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ ! -f "$PKG" ]]; then
  echo "Missing package: $PKG" >&2
  echo "Build first: archive + export to .asc/artifacts/export/BeCut.pkg" >&2
  exit 1
fi

if [[ -z "$APP_ID" ]]; then
  # Resolve by bundle id if possible
  APP_ID=$(asc apps list --bundle-id "app.becut.BeCut" --output json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); data=d.get('data') or []; print(data[0]['id'] if data else '')" 2>/dev/null || true)
fi

if [[ -z "$APP_ID" ]]; then
  echo "No App Store Connect app for app.becut.BeCut yet." >&2
  echo "Create it once:" >&2
  echo "  asc web apps create --name \"BeCut\" --bundle-id \"app.becut.BeCut\" --sku \"becut-macos\" --platform MAC_OS --primary-locale en-US --apple-id YOUR@EMAIL" >&2
  echo "Then re-run with: ASC_APP_ID=<id> $0" >&2
  exit 2
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

echo "→ done. Open TestFlight in App Store Connect to assign groups."
