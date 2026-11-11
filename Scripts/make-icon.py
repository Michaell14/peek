#!/usr/bin/env python3
"""Draws the app icon and writes Resources/AppIcon.icns.

Needs Pillow (`pip install pillow`). The icon is three tiles on a dark
rounded square: a board in flow layout, with one tile lit.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # supersample for smooth edges


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle([v * SCALE for v in box], radius=radius * SCALE, fill=fill)


def main():
    canvas = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))

    # Background: macOS-style rounded square with a soft vertical gradient.
    margin, radius = 100, 185
    gradient = Image.new("RGBA", canvas.size)
    pixels = ImageDraw.Draw(gradient)
    top, bottom = (58, 62, 78), (20, 22, 30)
    for y in range(canvas.size[1]):
        t = y / canvas.size[1]
        colour = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        pixels.line([(0, y), (canvas.size[0], y)], fill=colour)
    mask = Image.new("L", canvas.size, 0)
    rounded(ImageDraw.Draw(mask), (margin, margin, SIZE - margin, SIZE - margin), radius, 255)
    canvas.paste(gradient, (0, 0), mask)

    # Tiles.
    left, top_edge, right, bottom_edge = 232, 262, 792, 762
    gap, split = 36, 430

    # Translucent shapes go on their own layer so they blend with the
    # background instead of replacing it.
    dim = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dim_draw = ImageDraw.Draw(dim)
    rounded(dim_draw, (left, top_edge, split, top_edge + 150), 34, (255, 255, 255, 60))
    rounded(dim_draw, (left, top_edge + 150 + gap, split, bottom_edge), 34, (255, 255, 255, 60))
    canvas.alpha_composite(dim)

    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    rounded(ImageDraw.Draw(glow), (split + gap, top_edge, right, bottom_edge), 34, (255, 196, 84, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(26 * SCALE))
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", canvas.size, 0), mask))
    canvas.alpha_composite(glow)
    rounded(ImageDraw.Draw(canvas), (split + gap, top_edge, right, bottom_edge), 34, (255, 204, 102, 255))

    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    out = Path(__file__).resolve().parent.parent / "Resources"
    out.mkdir(exist_ok=True)
    icon.save(out / "AppIcon.icns", format="ICNS",
              sizes=[(s, s) for s in (16, 32, 64, 128, 256, 512, 1024)])
    # The website uses the same picture as its icon.
    site = out.parent / "docs"
    if site.is_dir():
        icon.resize((256, 256), Image.LANCZOS).save(site / "icon.png")
    print("wrote", out / "AppIcon.icns")


if __name__ == "__main__":
    main()
