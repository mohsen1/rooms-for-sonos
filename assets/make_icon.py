#!/usr/bin/env python3
"""Draws the app icon: two rooms, with the music in the overlap.

Writes assets/icon.svg, then renders the PNGs in app/www with rsvg-convert.
"""

import math
import subprocess
from pathlib import Path

SIZE = 1024
BACKGROUND = "#0b0b0d"
FOREGROUND = "#f4f1ea"
RADIUS = 250
OFFSET = 150
STROKE = 56
PNGS = {"apple-touch-icon.png": 180, "icon-192.png": 192, "icon-512.png": 512}

ROOT = Path(__file__).resolve().parent.parent
center = SIZE / 2
left = center - OFFSET
right = center + OFFSET
rise = math.sqrt(RADIUS**2 - OFFSET**2)
top = center - rise
bottom = center + rise

svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">
  <rect width="{SIZE}" height="{SIZE}" fill="{BACKGROUND}"/>
  <path d="M {center} {top} A {RADIUS} {RADIUS} 0 0 1 {center} {bottom} A {RADIUS} {RADIUS} 0 0 1 {center} {top} Z" fill="{FOREGROUND}"/>
  <circle cx="{left}" cy="{center}" r="{RADIUS}" fill="none" stroke="{FOREGROUND}" stroke-width="{STROKE}"/>
  <circle cx="{right}" cy="{center}" r="{RADIUS}" fill="none" stroke="{FOREGROUND}" stroke-width="{STROKE}"/>
</svg>
"""

source = ROOT / "assets" / "icon.svg"
source.write_text(svg)

for name, size in PNGS.items():
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(ROOT / "app" / "www" / name), str(source)],
        check=True,
    )
