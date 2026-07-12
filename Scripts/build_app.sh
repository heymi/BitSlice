#!/usr/bin/env bash
# Build BeCut.app via Xcode (official App Icon pipeline).
#
# App icon sources (Apple docs):
#   https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
#   - AppIcon.icon          Icon Composer multilayer source (project root)
#   - Assets.xcassets/AppIcon  Flattened macOS sizes for Dock (actool → Assets.car + AppIcon.icns)
#
# Note: Xcode 26.6 RC's actool currently crashes when compiling .icon packages on this
# machine. Until that is fixed, Dock uses the AppIcon asset catalog. Keep AppIcon.icon
# in the project for Icon Composer editing and for when actool can compile it.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="BeCut"
DERIVED="$ROOT_DIR/build/DerivedData"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-26.6-RC.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6-RC.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

cd "$ROOT_DIR"

if [[ ! -d BeCut.xcodeproj ]]; then
  echo "Missing BeCut.xcodeproj — run: xcodegen generate" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "→ xcodebuild Release"
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

# Also copy Icon Composer source into the app for reference / future OS support
if [[ -d "$ROOT_DIR/AppIcon.icon" ]]; then
  mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"
  rm -rf "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icon"
  cp -R "$ROOT_DIR/AppIcon.icon" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icon"
fi

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
