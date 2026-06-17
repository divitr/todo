#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/AppIcon-source.png}"
DEST="$ROOT/todo/Assets.xcassets/AppIcon.appiconset"
VENV_PY="$ROOT/.venv-icon/bin/python3"
SCALE_PY="$ROOT/scripts/scale-icon-fill.py"

if [[ ! -f "$SRC" ]]; then
  echo "Missing source image: $SRC"
  exit 1
fi

if [[ -x "$VENV_PY" && -f "$SCALE_PY" ]]; then
  "$VENV_PY" "$SCALE_PY" "$SRC" "$ROOT/AppIcon-source.png"
  SRC="$ROOT/AppIcon-source.png"
fi

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRC" --out "$DEST/icon_${size}x${size}.png" >/dev/null
  s2=$((size * 2))
  sips -z "$s2" "$s2" "$SRC" --out "$DEST/icon_${size}x${size}@2x.png" >/dev/null
done

echo "Updated icons in $DEST"
