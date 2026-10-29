#!/usr/bin/env python3
"""Composes the per-platform pictures on the download page (site/assets/shots/dl-<platform>.png), 1200x900:
a desktop window or a framed phone on the brand's soft gradient. Inputs are raw screenshots; see usage."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
W, H = 1200, 900

def background():
    bg = Image.new("RGB", (W, H), (244, 244, 250))
    glow = Image.new("RGB", (W, H), (244, 244, 250))
    d = ImageDraw.Draw(glow)
    d.ellipse([-200, -300, 900, 500], fill=(222, 220, 252))
    d.ellipse([500, 300, 1500, 1200], fill=(226, 232, 252))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.blend(bg, glow, 0.9).convert("RGBA")

def shadowed(im, radius, blur=28, offset=18, alpha=70):
    """A rounded picture with a soft drop shadow, on a transparent canvas."""
    pad = blur * 3
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    mask = Image.new("L", im.size, 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0)); sh.paste((20, 20, 60, alpha), (pad, pad + offset), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh)
    pic = Image.new("RGBA", im.size, (0, 0, 0, 0)); pic.paste(im.convert("RGBA"), (0, 0), mask)
    canvas.alpha_composite(pic, (pad, pad))
    return canvas, pad

def desktop(src, box, out, radius):
    """A window cropped from a desktop screenshot (box = left, top, right, bottom), centred."""
    win = Image.open(src).convert("RGB").crop(box)
    maxw, maxh = int(W * 0.82), int(H * 0.86)
    s = min(maxw / win.width, maxh / win.height)
    win = win.resize((int(win.width * s), int(win.height * s)), Image.LANCZOS)
    card, pad = shadowed(win, int(radius * s))
    bg = background(); bg.alpha_composite(card, ((W - win.width) // 2 - pad, (H - win.height) // 2 - pad))
    bg.convert("RGB").save(out, optimize=True); print(out, win.size)

def phone(framed_src, out, screen_top_frac=0.0):
    """A framed phone (Tools: frame_phone.py) sitting at the bottom edge, bleeding off it, keyboard in view."""
    ph = Image.open(framed_src).convert("RGBA")
    target_w = int(W * 0.40); s = target_w / ph.width
    ph = ph.resize((target_w, int(ph.height * s)), Image.LANCZOS)
    # shadow
    pad = 90; canvas = Image.new("RGBA", (ph.width + pad * 2, ph.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0)); sh.paste((20, 20, 60, 80), (pad, pad + 20), ph.split()[3])
    sh = sh.filter(ImageFilter.GaussianBlur(30)); canvas.alpha_composite(sh); canvas.alpha_composite(ph, (pad, pad))
    bg = background()
    top = int(H * 0.045)   # the whole phone from its top; only the bottom bezel runs off the picture
    bg.alpha_composite(canvas, ((W - ph.width) // 2 - pad, top - pad))
    bg.convert("RGB").save(out, optimize=True); print(out, ph.size)

if __name__ == "__main__":
    kind = sys.argv[1]
    if kind == "desktop": desktop(sys.argv[2], tuple(map(int, sys.argv[3].split(","))), sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 14)
    elif kind == "phone": phone(sys.argv[2], sys.argv[3])
