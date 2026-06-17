#!/usr/bin/env python3
"""Scale artwork to fill a 1024×1024 app icon canvas. Requires: pip install Pillow"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: python3 -m venv .venv-icon && .venv-icon/bin/pip install Pillow", file=sys.stderr)
    sys.exit(1)

FILL = 0.98
SIZE = 1024


def content_bounds(img: Image.Image) -> tuple[int, int, int, int]:
    w, h = img.size
    px = img.load()
    min_x, min_y = w, h
    max_x, max_y = 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16 or (r > 245 and g > 245 and b > 245):
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    return min_x, min_y, max_x + 1, max_y + 1


def scale_to_fill(src_path: Path, out_path: Path, fill: float = FILL) -> None:
    img = Image.open(src_path).convert("RGBA")
    box = content_bounds(img)
    content = img.crop(box)
    target = int(SIZE * fill)
    cw, ch = content.size
    scale = target / max(cw, ch)
    nw, nh = int(cw * scale), int(ch * scale)
    content = content.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    canvas.paste(content, ((SIZE - nw) // 2, (SIZE - nh) // 2), content)
    canvas.convert("RGB").save(out_path, "PNG")
    print(f"Wrote {out_path} ({nw}×{nh} artwork, {fill:.0%} fill)")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "AppIcon-source.png"
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else src
    scale_to_fill(src, out)
