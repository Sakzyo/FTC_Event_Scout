#!/usr/bin/env python3
"""Render the app icon PNGs in assets/app-icon/png from the SVG sources.

Run this after editing assets/app-icon/*.svg. It needs Google Chrome (to rasterize
the SVGs) and Pillow (to downsample them); packaging itself needs neither, because
script/generate_app_icon.py only assembles the committed PNGs.
"""

import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

ROOT_DIR = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT_DIR / "assets" / "app-icon"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
MASTER_SIZE = 1024

# 16 and 32 px use the simplified artwork, whose thicker arm and plain bearing stay legible.
SIZES = {
    16: "app-icon-small.svg",
    32: "app-icon-small.svg",
    64: "app-icon.svg",
    128: "app-icon.svg",
    256: "app-icon.svg",
    512: "app-icon.svg",
    1024: "app-icon.svg",
}


def rasterize(svg, output):
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            "--force-device-scale-factor=1",
            f"--window-size={MASTER_SIZE},{MASTER_SIZE}",
            f"--screenshot={output}",
            svg.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def main():
    output_dir = ICON_DIR / "png"
    output_dir.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        masters = {}
        for source in sorted(set(SIZES.values())):
            master = Path(scratch) / f"{source}.png"
            rasterize(ICON_DIR / source, master)
            masters[source] = Image.open(master).convert("RGBA")
        for size, source in SIZES.items():
            image = masters[source]
            if size != MASTER_SIZE:
                image = image.resize((size, size), Image.LANCZOS)
            image.save(output_dir / f"icon_{size}.png", optimize=True)
            print(f"Rendered icon_{size}.png from {source}")


if __name__ == "__main__":
    main()
