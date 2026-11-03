#!/usr/bin/env python3
"""Assemble the FTC Event Scout iconset and .icns with only the Python standard library.

The artwork lives in assets/app-icon as SVG; script/render_app_icon.py renders it to
the PNGs this script packages.
"""

from pathlib import Path
import shutil
import struct
import sys

ICON_PNGS = Path(__file__).resolve().parent.parent / "assets" / "app-icon" / "png"


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
        source = ICON_PNGS / f"icon_{pixels}.png"
        if not source.is_file():
            raise SystemExit(f"Missing {source}. Run script/render_app_icon.py to render the app icon.")
        shutil.copyfile(source, output / name)

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
