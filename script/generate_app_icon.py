#!/usr/bin/env python3
"""Generate the FTC Event Scout icon with only the Python standard library."""

from pathlib import Path
import struct
import sys
import zlib


def _inside_rounded_rect(x, y, bounds, radius):
    x0, y0, x1, y1 = bounds
    if not (x0 <= x < x1 and y0 <= y < y1):
        return False
    if x0 + radius <= x < x1 - radius or y0 + radius <= y < y1 - radius:
        return True
    center_x = x0 + radius if x < x0 + radius else x1 - radius - 1
    center_y = y0 + radius if y < y0 + radius else y1 - radius - 1
    return (x - center_x) ** 2 + (y - center_y) ** 2 <= radius ** 2


def _set_pixel(pixels, size, x, y, color):
    if 0 <= x < size and 0 <= y < size:
        offset = (y * size + x) * 4
        pixels[offset : offset + 4] = bytes(color)


def _fill_rounded_rect(pixels, size, bounds, radius, color):
    x0, y0, x1, y1 = bounds
    for y in range(max(y0, 0), min(y1, size)):
        for x in range(max(x0, 0), min(x1, size)):
            if _inside_rounded_rect(x, y, bounds, radius):
                _set_pixel(pixels, size, x, y, color)


def _fill_circle(pixels, size, center_x, center_y, radius, color):
    radius_squared = radius * radius
    for y in range(max(center_y - radius, 0), min(center_y + radius + 1, size)):
        for x in range(max(center_x - radius, 0), min(center_x + radius + 1, size)):
            if (x - center_x) ** 2 + (y - center_y) ** 2 <= radius_squared:
                _set_pixel(pixels, size, x, y, color)


def _scaled(value, size):
    return round(value * size / 1024)


def draw_icon(size):
    pixels = bytearray(size * size * 4)
    tile = tuple(_scaled(value, size) for value in (56, 56, 968, 968))
    tile_radius = _scaled(216, size)

    for y in range(size):
        amount = y / max(size - 1, 1)
        color = (
            round(56 * (1 - amount)),
            round(160 * (1 - amount) + 102 * amount),
            round(255 * (1 - amount) + 214 * amount),
            255,
        )
        for x in range(size):
            if _inside_rounded_rect(x, y, tile, tile_radius):
                _set_pixel(pixels, size, x, y, color)

    white = (255, 255, 255, 255)
    blue = (10, 132, 255, 255)
    _fill_rounded_rect(
        pixels,
        size,
        tuple(_scaled(value, size) for value in (232, 262, 792, 702)),
        _scaled(112, size),
        white,
    )
    _fill_circle(pixels, size, _scaled(380, size), _scaled(468, size), _scaled(48, size), blue)
    _fill_circle(pixels, size, _scaled(644, size), _scaled(468, size), _scaled(48, size), blue)
    _fill_rounded_rect(
        pixels,
        size,
        tuple(_scaled(value, size) for value in (344, 575, 680, 613)),
        _scaled(19, size),
        blue,
    )
    _fill_rounded_rect(
        pixels,
        size,
        tuple(_scaled(value, size) for value in (494, 188, 530, 284)),
        _scaled(18, size),
        white,
    )
    _fill_circle(pixels, size, _scaled(512, size), _scaled(174, size), _scaled(36, size), white)

    for bounds, radius in [
        ((284, 760, 388, 852), 16),
        ((460, 682, 564, 852), 16),
        ((636, 724, 740, 852), 16),
    ]:
        _fill_rounded_rect(
            pixels,
            size,
            tuple(_scaled(value, size) for value in bounds),
            _scaled(radius, size),
            white,
        )
    return pixels


def write_png(path, size, pixels):
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    scanlines = b"".join(
        b"\x00" + bytes(pixels[row * size * 4 : (row + 1) * size * 4])
        for row in range(size)
    )
    payload = b"\x89PNG\r\n\x1a\n"
    payload += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    payload += chunk(b"IDAT", zlib.compress(scanlines, level=9))
    payload += chunk(b"IEND", b"")
    path.write_bytes(payload)


def main():
    if len(sys.argv) not in {2, 3}:
        raise SystemExit("usage: generate_app_icon.py <output.iconset> [output.icns]")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    entries = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, pixels in entries.items():
        write_png(output / name, pixels, draw_icon(pixels))

    if len(sys.argv) == 3:
        icns_entries = [
            (b"icp4", "icon_16x16.png"),
            (b"icp5", "icon_32x32.png"),
            (b"icp6", "icon_32x32@2x.png"),
            (b"ic07", "icon_128x128.png"),
            (b"ic08", "icon_256x256.png"),
            (b"ic09", "icon_512x512.png"),
            (b"ic10", "icon_512x512@2x.png"),
        ]
        chunks = []
        for chunk_type, filename in icns_entries:
            png = (output / filename).read_bytes()
            chunks.append(chunk_type + struct.pack(">I", len(png) + 8) + png)
        payload = b"".join(chunks)
        Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)


if __name__ == "__main__":
    main()
