#!/usr/bin/env bash
# Rasterize AppIcon.icon (Icon Composer) → Assets.xcassets/AppIcon.appiconset
# for Xcode 26 / App Store–eligible builds. Requires Icon Composer (Xcode 27+).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT_DIR/AppIcon.icon"
OUT="$ROOT_DIR/Assets.xcassets/AppIcon.appiconset"
MASTER="$ROOT_DIR/build/icon-from-composer/AppIcon-1024.png"

if [[ ! -d "$ICON" ]]; then
  echo "Missing $ICON" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

ICTOOL="${DEVELOPER_DIR}/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  # Also check sibling apps
  for c in \
    "/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
    "/Applications/Icon Composer.app/Contents/Executables/ictool"; do
    if [[ -x "$c" ]]; then ICTOOL="$c"; break; fi
  done
fi
if [[ ! -x "$ICTOOL" ]]; then
  echo "ictool not found — install Icon Composer / Xcode with Icon Composer." >&2
  exit 1
fi

mkdir -p "$(dirname "$MASTER")" "$OUT"
echo "→ export 1024 from AppIcon.icon"
"$ICTOOL" "$ICON" --export-image \
  --output-file "$MASTER" \
  --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1

resize() {
  local name="$1" px="$2"
  /usr/bin/sips -z "$px" "$px" "$MASTER" --out "$OUT/$name" >/dev/null
}

resize "appicon_16.png" 16
resize "appicon_16@2x.png" 32
resize "appicon_32.png" 32
resize "appicon_32@2x.png" 64
resize "appicon_128.png" 128
resize "appicon_128@2x.png" 256
resize "appicon_256.png" 256
resize "appicon_256@2x.png" 512
resize "appicon_512.png" 512
resize "appicon_512@2x.png" 1024
# Do not put unreferenced files in the appiconset (actool: "unassigned child").

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "appicon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "appicon_16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "appicon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "appicon_32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "appicon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "appicon_128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "appicon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "appicon_256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "appicon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "appicon_512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "→ ready: $OUT (from AppIcon.icon)"
