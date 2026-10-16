#!/usr/bin/env python3
"""Assemble the PNG frames tests/capture_gif.gd leaves behind into one
GIF, scaled to a readable width and palette-optimised. Pillow only; no
other dependency.

    python3 tools/make_gif.py /tmp/gifframes docs/media/app.gif [width]
"""
import os
import sys

from PIL import Image, ImageStat


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: make_gif.py <frames-dir> <out.gif> [width]")
    src, dst = sys.argv[1], sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 400

    names = sorted(n for n in os.listdir(src) if n.endswith(".png"))
    if not names:
        sys.exit("no frames in %s" % src)

    frames = []
    skipped = 0
    for name in names:
        image = Image.open(os.path.join(src, name)).convert("RGB")
        # The camera can start one frame before the first draw: a leading
        # black frame would flash in the film, so leading dark frames are
        # dropped until the page is on the screen.
        if not frames and ImageStat.Stat(image.convert("L")).mean[0] < 40:
            skipped += 1
            continue
        height = round(image.height * width / image.width)
        frames.append(image.resize((width, height), Image.LANCZOS))
    if not frames:
        sys.exit("every frame in %s is dark" % src)

    frames[0].save(
        dst,
        save_all=True,
        append_images=frames[1:],
        duration=100,
        loop=0,
        optimize=True,
    )
    print(
        "gif: %d frame(s) at %dpx -> %s (%d KB)"
        % (len(frames), width, dst, os.path.getsize(dst) // 1024)
    )


if __name__ == "__main__":
    main()
