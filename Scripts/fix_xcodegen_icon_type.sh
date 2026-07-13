#!/usr/bin/env bash
# XcodeGen marks *.icon as lastKnownFileType = folder (plain copy).
# actool only compiles Icon Composer packages when the type is
# folder.iconcomposer.icon. Patch after every `xcodegen generate`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT_DIR/BeCut.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "Missing $PBXPROJ — run xcodegen generate first" >&2
  exit 1
fi

python3 - "$PBXPROJ" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
# Only fix AppIcon.icon (or any *.icon) file references that are plain folders.
pattern = re.compile(
    r"(/\* ([^*/]+\.icon) \*/ = \{isa = PBXFileReference; lastKnownFileType = )folder(; path = \2;)"
)
new_text, n = pattern.subn(r"\1folder.iconcomposer.icon\3", text)
# Also handle already-correct or alternate ordering of keys
if n == 0:
    pattern2 = re.compile(
        r"(lastKnownFileType = )folder(; path = [^;]+\.icon;)"
    )
    new_text, n = pattern2.subn(r"\1folder.iconcomposer.icon\2", text)
if n == 0 and "folder.iconcomposer.icon" in text and ".icon" in text:
    print("AppIcon.icon already typed as folder.iconcomposer.icon")
    sys.exit(0)
if n == 0:
    print("warning: no AppIcon.icon PBXFileReference found to patch", file=sys.stderr)
    sys.exit(1)
path.write_text(new_text)
print(f"Patched {n} .icon file type(s) → folder.iconcomposer.icon")
PY
