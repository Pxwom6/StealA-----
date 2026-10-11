"""Builds store art (game icon 512x512, thumbnails 1920x1080) from Studio captures.

usage: python3 tools/store_art.py <kind> <src> <out> [x0 y0 x1 y1]
  kind: map | lineup | icon
The optional box crops the source first (in source pixels).
"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

BOLD = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
YELLOW = (255, 214, 60)
INK = (45, 25, 70)


def font(size):
    return ImageFont.truetype(BOLD, size)


def punch(im, sat=1.25, con=1.08):
    im = ImageEnhance.Color(im).enhance(sat)
    return ImageEnhance.Contrast(im).enhance(con)


def fit(im, w, h):
    """Center-crop to the w:h aspect, then resize."""
    sw, sh = im.size
    target = w / h
    if sw / sh > target:
        nw = int(sh * target)
        x0 = (sw - nw) // 2
        im = im.crop((x0, 0, x0 + nw, sh))
    else:
        nh = int(sw / target)
        y0 = (sh - nh) // 2
        im = im.crop((0, y0, sw, y0 + nh))
    return im.resize((w, h), Image.LANCZOS)


def outlined(draw, xy, text, size, fill, stroke=INK, sw=None, anchor="mm"):
    sw = sw if sw is not None else max(4, size // 9)
    draw.text(xy, text, font=font(size), fill=fill, stroke_width=sw, stroke_fill=stroke, anchor=anchor)


def shadowed_text(im, xy, text, size, fill, anchor="mm"):
    """Outlined text with a soft drop shadow so it reads on any background."""
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sw = max(4, size // 9)
    sd.text((xy[0] + size // 18, xy[1] + size // 12), text, font=font(size), fill=(0, 0, 0, 150),
            stroke_width=sw, stroke_fill=(0, 0, 0, 150), anchor=anchor)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size // 20))
    im.alpha_composite(shadow)
    outlined(ImageDraw.Draw(im), xy, text, size, fill, sw=sw, anchor=anchor)


def title_block(im, y, big, sub=None):
    w = im.size[0]
    shadowed_text(im, (w // 2, y), big, int(w * 0.075), YELLOW)
    if sub:
        shadowed_text(im, (w // 2, y + int(w * 0.068)), sub, int(w * 0.036), (255, 255, 255))


def main():
    kind, src, out = sys.argv[1:4]
    im = Image.open(src).convert("RGB")
    if len(sys.argv) == 8:
        im = im.crop(tuple(int(v) for v in sys.argv[4:8]))
    im = punch(im)
    if kind == "icon":
        im = fit(im, 512, 512).convert("RGBA")
        shadowed_text(im, (256, 418), "STEAL A", 54, (255, 255, 255))
        shadowed_text(im, (256, 468), "SNACKLING", 58, YELLOW)
    else:
        im = fit(im, 1920, 1080).convert("RGBA")
        if kind == "map":
            title_block(im, 120, "STEAL A SNACKLING", "BUY  •  EARN  •  STEAL  •  PROTECT")
        else:
            title_block(im, 120, "60+ SNACKLINGS", "COLLECT THEM ALL  •  FIND RARE MUTATIONS")
    im.convert("RGB").save(out, quality=92)
    print("wrote", out, im.size)


if __name__ == "__main__":
    main()
