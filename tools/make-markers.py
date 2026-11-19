#!/usr/bin/env python3
# Draws Icons/bang.png, bangline.png, ask.png, askline.png and forever.png (needs Pillow and the DejaVu fonts).
#   python3 tools/make-markers.py Icons
# Draws the addon's own quest markers (not Questie's art): a gold ! and ? with a dark border, white outline
# masks for the coloured outline, and a teal badge with an infinity sign.
import sys, math
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter
OUT = sys.argv[1]
HI, SZ = 512, 64
R = HI / 1.3                 # the icon's own square inside the canvas (the canvas is 1.3x the icon)
OFF = (HI - R) / 2
CX = HI / 2

def grow(mask, r):
    out = mask.copy()
    steps = max(16, int(r))
    for k in range(steps):
        a = 2 * math.pi * k / steps
        for rr in (r, r * 0.5):
            dx, dy = int(round(math.cos(a) * rr)), int(round(math.sin(a) * rr))
            sh = Image.new("L", mask.size); sh.paste(mask, (dx, dy)); out = ImageChops.lighter(out, sh)
    return out

def bang():
    m = Image.new("L", (HI, HI)); d = ImageDraw.Draw(m)
    top, bot = OFF + 0.06 * R, OFF + 0.62 * R
    wt, wb = 0.40 * R, 0.23 * R
    d.polygon([(CX - wt / 2, top + wt / 2), (CX + wt / 2, top + wt / 2), (CX + wb / 2, bot - wb / 2), (CX - wb / 2, bot - wb / 2)], fill=255)
    d.ellipse([CX - wt / 2, top, CX + wt / 2, top + wt], fill=255)
    d.ellipse([CX - wb / 2, bot - wb, CX + wb / 2, bot], fill=255)
    r, cy = 0.145 * R, OFF + 0.83 * R
    d.ellipse([CX - r, cy - r, CX + r, cy + r], fill=255)
    return m

def ask():
    f = ImageFont.truetype("DejaVuSans-Bold.ttf", int(R * 1.1))
    m = Image.new("L", (HI * 2, HI * 2)); d = ImageDraw.Draw(m)
    d.text((HI, HI), "?", fill=255, font=f, anchor="mm")
    box = m.getbbox(); g = m.crop(box)
    h = 0.86 * R; w = g.width * h / g.height
    g = g.resize((int(w), int(h)), Image.LANCZOS)
    out = Image.new("L", (HI, HI)); out.paste(g, (int(CX - w / 2), int(OFF + 0.07 * R)))
    return out

def glyph(mask):
    border = grow(mask, 0.065 * R)
    img = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    dark = Image.new("RGBA", (HI, HI), (28, 20, 8, 255)); dark.putalpha(border); img.alpha_composite(dark)
    grad = Image.new("RGBA", (HI, HI))
    gd = ImageDraw.Draw(grad)
    y0, y1 = OFF, OFF + R
    for y in range(HI):
        t = min(1, max(0, (y - y0) / (y1 - y0)))
        c = (int(255 - 15 * t), int(232 - 90 * t), int(96 - 76 * t), 255)
        gd.line([(0, y), (HI, y)], fill=c)
    grad.putalpha(mask); img.alpha_composite(grad)
    # a soft light along the upper left edge of the shape
    shine = Image.new("L", (HI, HI)); sd = ImageDraw.Draw(shine)
    sd.ellipse([CX - 0.20 * R, OFF + 0.02 * R, CX + 0.02 * R, OFF + 0.55 * R], fill=110)
    shine = ImageChops.multiply(shine.filter(ImageFilter.GaussianBlur(R * 0.03)), mask)
    light = Image.new("RGBA", (HI, HI), (255, 250, 220, 0)); light.putalpha(shine); img.alpha_composite(light)
    return img.resize((SZ, SZ), Image.LANCZOS), border

def outline(border):
    a = grow(border, 0.12 * R).filter(ImageFilter.GaussianBlur(R * 0.008))
    img = Image.new("RGBA", (HI, HI), (255, 255, 255, 0)); img.putalpha(a)
    return img.resize((SZ, SZ), Image.LANCZOS)

def badge():
    img = Image.new("RGBA", (HI, HI), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.ellipse([16, 16, HI - 16, HI - 16], fill=(20, 42, 48, 255))
    d.ellipse([52, 52, HI - 52, HI - 52], fill=(150, 228, 240, 255))
    f = ImageFont.truetype("DejaVuSans-Bold.ttf", int(HI * 0.62))
    d.text((HI / 2, HI / 2 + 4), "∞", fill=(14, 60, 72, 255), font=f, anchor="mm")
    return img.resize((SZ, SZ), Image.LANCZOS)

for name, mask in (("bang", bang()), ("ask", ask())):
    g, border = glyph(mask)
    g.save(f"{OUT}/{name}.png"); outline(border).save(f"{OUT}/{name}line.png")
badge().save(f"{OUT}/forever.png")
print("ok")
