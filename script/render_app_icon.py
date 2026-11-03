#!/usr/bin/env python3
"""Render the app icon outputs in assets/app-icon from the SVG sources.

Run this after editing assets/app-icon/*.svg. It writes the PNGs that
script/generate_app_icon.py packages into AppIcon.icns, and the arm layer of the
Icon Composer icon (AppIcon.icon) that gives macOS 26 its light and dark variants.
It needs Google Chrome (to rasterize the SVGs) and Pillow (to downsample them);
packaging itself needs neither.
"""

import os
from pathlib import Path
import re
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


def write_icon_composer_layer():
    """Copy the arm out of app-icon.svg as a full-bleed layer; the .icon supplies the background."""
    source = (ICON_DIR / "app-icon.svg").read_text()
    start = source.index('<g id="arm"')
    depth = 0
    for tag in re.finditer(r"<g[\s>]|</g>", source[start:]):
        depth += -1 if tag.group() == "</g>" else 1
        if depth == 0:
            arm = source[start : start + tag.end()]
            break
    else:
        raise SystemExit('app-icon.svg has an unclosed <g id="arm"> group.')
    # The light icon's tile spans 100-924; Icon Composer's canvas is the whole icon shape.
    layer = ICON_DIR / "AppIcon.icon" / "Assets" / "arm.svg"
    layer.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="100 100 824 824">\n'
        f"{arm}\n</svg>\n"
    )
    print(f"Wrote {layer.relative_to(ROOT_DIR)}")


def main():
    write_icon_composer_layer()
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
