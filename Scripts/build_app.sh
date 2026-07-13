#!/usr/bin/env bash
# Build BeCut.app via Xcode (App Store–eligible release toolchain).
#
# Icon pipeline:
#   AppIcon.icon  → (local) Scripts/sync_appicon_from_icon.sh
#                 → Assets.xcassets/AppIcon.appiconset  (committed PNGs)
# Xcode 26 actool crashes on .icon packages; release/Xcode Cloud use appiconset.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="BeCut"
DERIVED="$ROOT_DIR/build/DerivedData"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  # Prefer release Xcode for packaging that can be submitted.
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-26.6-RC.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6-RC.app/Contents/Developer
  elif [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    echo "warning: only Xcode beta found; App Store submission may reject beta builds" >&2
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  fi
fi

cd "$ROOT_DIR"

if [[ ! -d BeCut.xcodeproj ]]; then
  echo "Missing BeCut.xcodeproj — run: xcodegen generate" >&2
  exit 1
fi

if [[ ! -f Assets.xcassets/AppIcon.appiconset/Contents.json ]]; then
  echo "Missing AppIcon.appiconset — run: Scripts/sync_appicon_from_icon.sh" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "→ xcodebuild Release (DEVELOPER_DIR=${DEVELOPER_DIR:-default})"
xcodebuild -project BeCut.xcodeproj -scheme BeCut -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=- \
  build

APP_SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build product missing: $APP_SRC" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app"
cp -R "$APP_SRC" "$DIST_DIR/$APP_NAME.app"

/usr/bin/touch "$DIST_DIR/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DIST_DIR/$APP_NAME.app" 2>/dev/null || true

echo "→ ready: $DIST_DIR/$APP_NAME.app"
ls -la "$DIST_DIR/$APP_NAME.app/Contents/Resources/" || true

case "$MODE" in
  run)
    /usr/bin/open -n "$DIST_DIR/$APP_NAME.app"
    ;;
  package|build)
    ;;
  *)
    echo "usage: $0 [run|package]" >&2
    exit 2
    ;;
esac
