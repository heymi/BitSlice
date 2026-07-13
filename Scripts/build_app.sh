#!/usr/bin/env bash
# Build BeCut.app via Xcode (Icon Composer .icon → actool).
#
# App icon source (Apple docs):
#   https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
#   - AppIcon.icon  Icon Composer multilayer package at project root
#
# Note: Xcode 26.6 RC actool crashes compiling .icon packages. Prefer Xcode 27+
# (Xcode-beta / Xcode.app ≥ 27) so Dock/Finder get the compiled icon from .icon.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="BeCut"
DERIVED="$ROOT_DIR/build/DerivedData"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    # Xcode 27+ required for reliable .icon compilation
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-26.6-RC.app/Contents/Developer ]]; then
    echo "warning: Xcode 26.6 RC actool may crash on AppIcon.icon; prefer Xcode 27+" >&2
    export DEVELOPER_DIR=/Applications/Xcode-26.6-RC.app/Contents/Developer
  fi
fi

cd "$ROOT_DIR"

if [[ ! -d AppIcon.icon ]]; then
  echo "Missing AppIcon.icon — Icon Composer source required (no PNG appiconset)." >&2
  exit 1
fi

if [[ ! -d BeCut.xcodeproj ]]; then
  echo "Missing BeCut.xcodeproj — run: xcodegen generate && Scripts/fix_xcodegen_icon_type.sh" >&2
  exit 1
fi

# Ensure .icon is compiled by actool, not copied as a folder
"$ROOT_DIR/Scripts/fix_xcodegen_icon_type.sh"

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
