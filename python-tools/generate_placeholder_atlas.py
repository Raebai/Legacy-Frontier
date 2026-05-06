"""
Generate a 64x32 placeholder tile atlas using stdlib only.
Two 32x32 tiles laid horizontally: tile 0 = grass (green), tile 1 = stone (grey).
Output: godot-project/assets/tilesets/placeholder_atlas.png
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

TILE_SIZE = 32
GRASS = (78, 138, 64)
STONE = (118, 118, 122)
TILES = [GRASS, STONE]


def write_png(path: Path, tiles: list[tuple[int, int, int]], tile_size: int) -> None:
    width = tile_size * len(tiles)
    height = tile_size

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # PNG filter type "None" per scanline
        for x in range(width):
            r, g, b = tiles[x // tile_size]
            # 1px darker checker so 32px boundaries are visible at runtime
            if (x // 4 + y // 4) % 2 == 0:
                r = max(0, r - 8)
                g = max(0, g - 8)
                b = max(0, b - 8)
            raw.extend([r, g, b])

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    idat = zlib.compress(bytes(raw), 9)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "tilesets" / "placeholder_atlas.png"
    write_png(out, TILES, TILE_SIZE)
    print(f"Wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
