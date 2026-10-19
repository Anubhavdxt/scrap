#!/usr/bin/env python3
"""Turns the frames written by `make demo` into the README's images (needs Pillow: pip3 install pillow).

Usage: scripts/make_demo.py <frames-dir> <docs-dir>
"""
import glob
import os
import sys

from PIL import Image

frames_dir, docs = sys.argv[1], sys.argv[2]
WIDTH = 760


def scaled(path, width):
    image = Image.open(path).convert("RGBA")
    return image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)


for name in ("hero", "search", "light"):
    scaled(os.path.join(frames_dir, f"{name}.png"), WIDTH).save(os.path.join(docs, f"screenshot-{name}.png"), optimize=True)

# The GIF: transparent shadows become the README's white/dark by flattening on a neutral grey that suits both.
paths = sorted(glob.glob(os.path.join(frames_dir, "frame-*.png")))
frames = []
for path in paths:
    image = scaled(path, 640)
    flat = Image.new("RGBA", image.size, (246, 246, 248, 255))
    flat.alpha_composite(image)
    frames.append(flat.convert("RGB").quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE))
durations = [110] * len(frames)
durations[0] = 700
durations[-1] = 2200
frames[0].save(os.path.join(docs, "demo.gif"), save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(f"wrote {len(paths)} frames, {os.path.getsize(os.path.join(docs, 'demo.gif')) // 1024} KB")
