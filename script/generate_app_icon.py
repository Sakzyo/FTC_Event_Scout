#!/usr/bin/env python3
"""Generate a macOS iconset for FTC Event Scout."""

import sys
import struct
from pathlib import Path

from PIL import Image, ImageDraw


def draw_icon(size=1024):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    scale = size / 1024

    def box(values):
        return tuple(round(value * scale) for value in values)

    # A padded macOS-style tile with a restrained blue gradient.
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box((56, 56, 968, 968)), radius=round(216 * scale), fill=255)
    gradient = Image.new("RGBA", (size, size))
    pixels = gradient.load()
    for y in range(size):
        amount = y / max(size - 1, 1)
        color = (
            round(56 * (1 - amount) + 0 * amount),
            round(160 * (1 - amount) + 102 * amount),
            round(255 * (1 - amount) + 214 * amount),
            255,
        )
        for x in range(size):
            pixels[x, y] = color
    image.alpha_composite(Image.composite(gradient, Image.new("RGBA", image.size), mask))
    draw = ImageDraw.Draw(image)

    white = (255, 255, 255, 255)
    blue = (10, 132, 255, 255)
    draw.rounded_rectangle(box((232, 262, 792, 702)), radius=round(112 * scale), fill=white)
    draw.ellipse(box((332, 420, 428, 516)), fill=blue)
    draw.ellipse(box((596, 420, 692, 516)), fill=blue)
    draw.line(box((344, 594, 680, 594)), fill=blue, width=round(38 * scale))
    draw.line(box((512, 188, 512, 262)), fill=white, width=round(36 * scale))
    draw.ellipse(box((476, 138, 548, 210)), fill=white)

    draw.rounded_rectangle(box((284, 760, 388, 852)), radius=round(16 * scale), fill=white)
    draw.rounded_rectangle(box((460, 682, 564, 852)), radius=round(16 * scale), fill=white)
    draw.rounded_rectangle(box((636, 724, 740, 852)), radius=round(16 * scale), fill=white)
    return image


def main():
    if len(sys.argv) not in {2, 3}:
        raise SystemExit("usage: generate_app_icon.py <output.iconset> [output.icns]")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    base = draw_icon()
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
        base.resize((pixels, pixels), Image.Resampling.LANCZOS).save(output / name)

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
