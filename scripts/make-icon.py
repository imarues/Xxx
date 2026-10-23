#!/usr/bin/env python3
"""Generate the ipastore icon for classic iOS icons and Icon Composer."""

import json
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RESOURCES = os.path.join(ROOT, "Feather", "Resources")
APPICON = os.path.join(RESOURCES, "Assets.xcassets", "AppIcon.appiconset")
COMPOSER = os.path.join(RESOURCES, "AppIcon.icon")
EXTENSION_ICON = os.path.join(RESOURCES, "feather_extension.png")

NORMAL_TOP = (92, 84, 255)
NORMAL_BOTTOM = (34, 179, 228)
DARK_TOP = (31, 29, 76)
DARK_BOTTOM = (10, 72, 105)
TINT_TOP = (165, 165, 172)
TINT_BOTTOM = (72, 72, 78)


def gradient(size, top, bottom):
    strip = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        strip.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize((size, size), Image.Resampling.BILINEAR).convert("RGBA")


def store_mask(size):
    """Shopping-bag mark with a download arrow cut out of its centre."""
    scale = size / 1024.0
    layer = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(layer)

    def box(values):
        return tuple(int(v * scale) for v in values)

    # Handle first, then the body overlaps its lower edge for one clean mark.
    d.rounded_rectangle(box((347, 214, 677, 507)), radius=int(150 * scale), fill=255)
    d.rounded_rectangle(box((421, 286, 603, 480)), radius=int(91 * scale), fill=0)
    d.rounded_rectangle(box((238, 378, 786, 818)), radius=int(132 * scale), fill=255)

    # Download arrow as transparent negative space.
    d.rounded_rectangle(box((477, 482, 547, 640)), radius=int(30 * scale), fill=0)
    d.polygon([
        (int(409 * scale), int(611 * scale)),
        (int(512 * scale), int(719 * scale)),
        (int(615 * scale), int(611 * scale)),
        (int(563 * scale), int(611 * scale)),
        (int(563 * scale), int(570 * scale)),
        (int(461 * scale), int(570 * scale)),
        (int(461 * scale), int(611 * scale)),
    ], fill=0)

    return layer


def mark(size, colour=(255, 255, 255, 255)):
    mask = store_mask(size)
    image = Image.new("RGBA", (size, size), colour)
    image.putalpha(mask)
    return image


def classic_icon(size, top, bottom):
    scale = SS
    canvas = gradient(size * scale, top, bottom)
    glyph = mark(size * scale)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.alpha_composite(glyph, (0, int(12 * scale)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(22 * scale)))
    shadow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.24)))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(glyph)

    # Small upper-left glow keeps the icon from looking flat without adding a logo.
    glow = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        (int(-180 * scale), int(-290 * scale), int(720 * scale), int(610 * scale)),
        fill=(255, 255, 255, 32),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(95 * scale)))
    canvas.alpha_composite(glow)

    return canvas.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def write_icon_composer():
    assets = os.path.join(COMPOSER, "Assets")
    os.makedirs(assets, exist_ok=True)
    mark(SIZE).save(os.path.join(assets, "feather.png"))

    spec_path = os.path.join(COMPOSER, "icon.json")
    with open(spec_path, encoding="utf-8") as f:
        spec = json.load(f)

    spec["fill"] = {
        "linear-gradient": [
            "srgb:0.36078,0.32941,1.00000,1.00000",
            "srgb:0.13333,0.70196,0.89412,1.00000",
        ],
        "orientation": {
            "start": {"x": 0.5, "y": 0},
            "stop": {"x": 0.5, "y": 1},
        },
    }
    for group in spec.get("groups", []):
        group["layers"] = [{
            "image-name": "feather.png",
            "name": "ipastore",
            "glass": False,
            "opacity": 1,
        }]

    with open(spec_path, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=2)
        f.write("\n")


def main():
    os.makedirs(APPICON, exist_ok=True)
    classic_icon(SIZE, NORMAL_TOP, NORMAL_BOTTOM).save(os.path.join(APPICON, "feather.png"))
    classic_icon(SIZE, DARK_TOP, DARK_BOTTOM).save(os.path.join(APPICON, "feather_dark.png"))
    classic_icon(SIZE, TINT_TOP, TINT_BOTTOM).save(os.path.join(APPICON, "feather_tint.png"))
    classic_icon(512, NORMAL_TOP, NORMAL_BOTTOM).save(EXTENSION_ICON)
    write_icon_composer()

    for filename in ("feather.png", "feather_dark.png", "feather_tint.png"):
        image = Image.open(os.path.join(APPICON, filename))
        print(f"{filename}: {image.size[0]}x{image.size[1]} {image.mode}")
    print("Generated new ipastore shopping-bag/download icon.")


if __name__ == "__main__":
    main()
