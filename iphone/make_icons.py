#!/usr/bin/env python3
"""Generate PNG Home Screen icons using only the Python standard library."""
from pathlib import Path
import math
import struct
import zlib

DEST = Path(__file__).resolve().parent

def line_distance(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx == dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def rgba(x, y):
    # Co-ordinates are normalized to a 180 x 180 grid.
    cx = max(12 + 37, min(x, 168 - 37))
    cy = max(12 + 37, min(y, 168 - 37))
    if math.hypot(x - cx, y - cy) > 37:
        return (10, 17, 25, 255)
    alpha = (x + y) / 360.0
    bg = (round(71 - 41 * alpha), round(239 - 70 * alpha), round(187 - 11 * alpha), 255)
    parts = [
        (90, 42, 90, 114, 7),
        (60, 91, 90, 121, 7),
        (90, 121, 120, 91, 7),
        (50, 133, 50, 147, 7),
        (50, 147, 130, 147, 7),
        (130, 147, 130, 133, 7),
    ]
    for ax, ay, bx, by, stroke in parts:
        if line_distance(x, y, ax, ay, bx, by) < stroke:
            return (8, 49, 51, 255)
    return bg

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

def make(size, filename):
    rows = bytearray()
    for y in range(size):
        rows.append(0)  # PNG filter type: none
        for x in range(size):
            rows.extend(rgba((x + .5) * 180 / size, (y + .5) * 180 / size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    (DEST / filename).write_bytes(png)
    print(f"Generated {filename} ({len(png)} bytes)")

if __name__ == "__main__":
    make(180, "apple-touch-icon.png")
    make(512, "icon-512.png")
