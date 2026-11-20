#!/usr/bin/env python3
# Draws Icons/zones.png, the map bar's "neighbouring zones" button (needs Pillow).
#   python3 tools/make-zones-icon.py Icons
import sys
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]
S = 512
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
def tile(x0, x1, fill, edge, width):
    d.rounded_rectangle([x0, 130, x1, 382], radius=34, fill=fill, outline=edge, width=width)
    # a few mountain strokes so it reads as a map piece
    for k in range(3):
        cx = x0 + (x1 - x0) * (0.25 + 0.25 * k); cy = 290 - (k % 2) * 40
        d.line([(cx - 28, cy + 24), (cx, cy - 22), (cx + 28, cy + 24)], fill=(120, 78, 36, 255), width=10, joint="curve")
tile(250, 480, (196, 168, 112, 255), (28, 20, 8, 255), 16)    # the neighbour: plainer, behind
tile(32, 262, (236, 204, 128, 255), (255, 205, 60, 255), 22)  # the zone you look at: gold border, in front
im = im.filter(ImageFilter.GaussianBlur(0.8)).resize((64, 64), Image.LANCZOS)
im.save(f"{OUT}/zones.png")
print("ok")
