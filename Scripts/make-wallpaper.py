#!/usr/bin/env python3
"""Draws the desktop picture used on the website: a calm sea at dusk.

It is made here, from noise, so the site carries no photograph that belongs
to anyone else.

    python3 Scripts/make-wallpaper.py            # writes docs/desk.jpg

Needs numpy and Pillow.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 1920, 1200
HORIZON = 0.52
rng = np.random.default_rng(7)


def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(u, v, seed):
    """Smooth noise at the given coordinates (arrays of the same shape)."""
    table = np.random.default_rng(seed).random((256, 256), dtype=np.float32)
    x0 = np.floor(u).astype(np.int64)
    y0 = np.floor(v).astype(np.int64)
    fx = smooth((u - x0).astype(np.float32))
    fy = smooth((v - y0).astype(np.float32))
    a = table[y0 & 255, x0 & 255]
    b = table[y0 & 255, (x0 + 1) & 255]
    c = table[(y0 + 1) & 255, x0 & 255]
    d = table[(y0 + 1) & 255, (x0 + 1) & 255]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fractal(u, v, seed, octaves=4):
    total = np.zeros_like(u, dtype=np.float32)
    weight, scale, norm = 1.0, 1.0, 0.0
    for octave in range(octaves):
        total += weight * value_noise(u * scale, v * scale, seed + octave)
        norm += weight
        weight *= 0.5
        scale *= 2.03
    return total / norm


def main(out: Path) -> None:
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    x = xs / W
    y = ys / H
    horizon = HORIZON
    light_x = 0.66  # where the last of the light sits on the horizon

    # Sky: dark overhead, paling towards the horizon, with slow cloud.
    up = np.clip((horizon - y) / horizon, 0, 1)  # 0 at the horizon, 1 at the top
    sky = 0.60 - 0.44 * up ** 0.72
    cloud = fractal(x * 3.2 + 4, y * 9.0, seed=11, octaves=5)
    band = np.exp(-((up - 0.34) / 0.22) ** 2)
    sky += (cloud - 0.5) * (0.20 * band + 0.035)
    glow = np.exp(-((x - light_x) / 0.34) ** 2) * np.exp(-(up / 0.30) ** 1.4)
    sky += 0.24 * glow

    # Sea: a plane seen in perspective. Depth runs from 0 at the horizon.
    depth = np.clip((y - horizon) / (1 - horizon), 1e-4, 1)
    distance = 1.0 / (depth + 0.045)
    u = (x - 0.5) * distance * 5.0
    v = distance * 7.0
    swell = fractal(u * 0.55, v * 2.3, seed=23, octaves=4)
    ripple = fractal(u * 2.4, v * 9.5, seed=31, octaves=3)
    waves = 0.62 * swell + 0.38 * ripple
    sea = 0.27 - 0.20 * depth ** 0.6
    sea += (waves - 0.5) * (0.085 + 0.10 * depth)
    # Light lying on the water under the bright part of the sky.
    path = np.exp(-((x - light_x) / (0.050 + 0.20 * depth)) ** 2)
    glitter = np.clip(waves - 0.50, 0, 1) * 3.0
    sea += path * (0.07 + glitter * 0.24) * (1 - depth) ** 1.3
    # Haze: the water meets the sky softly.
    sea += 0.20 * np.exp(-depth / 0.05) * (0.45 + 0.55 * np.exp(-((x - light_x) / 0.42) ** 2))

    image = np.where(y < horizon, sky, sea)

    # A lens: darker corners, a little grain.
    vignette = 1 - 0.34 * (((x - 0.5) / 0.74) ** 2 + ((y - 0.48) / 0.80) ** 2)
    image = image * np.clip(vignette, 0, 1)
    image += rng.normal(0, 0.008, image.shape).astype(np.float32)
    image = np.clip(image, 0, 1) ** 1.08

    # Toned like a print rather than neutral grey: cool shadows, warm lights.
    shadow = np.array([0.050, 0.060, 0.078], dtype=np.float32)
    light = np.array([1.000, 0.925, 0.810], dtype=np.float32)
    rgb = shadow + image[..., None] * (light - shadow)
    pixels = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(pixels, "RGB").save(out, "JPEG", quality=74, progressive=True, optimize=True)
    print(f"wrote {out} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else root / "docs" / "desk.jpg")
