#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Pillow is required. Install with: pip3 install pillow"
    ) from exc


def make_icon(size: int, out: Path) -> None:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = int(size * 0.06)
    rrect = [margin, margin, size - margin, size - margin]
    draw.rounded_rectangle(rrect, radius=int(size * 0.22), fill=(26, 118, 255, 255))

    inner = int(size * 0.18)
    x0 = inner
    x1 = size - inner
    y0 = inner
    y1 = size - inner
    w = x1 - x0
    h = y1 - y0

    points = [
        (x0 + w * 0.00, y0 + h * 0.52),
        (x0 + w * 0.12, y0 + h * 0.22),
        (x0 + w * 0.24, y0 + h * 0.80),
        (x0 + w * 0.36, y0 + h * 0.47),
        (x0 + w * 0.48, y0 + h * 0.28),
        (x0 + w * 0.62, y0 + h * 0.72),
        (x0 + w * 0.76, y0 + h * 0.44),
        (x0 + w * 0.88, y0 + h * 0.68),
        (x0 + w * 1.00, y0 + h * 0.36),
    ]
    draw.line(points, fill=(255, 255, 255, 255), width=max(2, int(size * 0.075)), joint="curve")

    draw.rounded_rectangle(
        rrect,
        radius=int(size * 0.22),
        outline=(255, 255, 255, 72),
        width=max(1, int(size * 0.012)),
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Meeting Assistant icon PNG")
    parser.add_argument(
        "--out",
        default="apps/macos/MeetingAssistantMac/Sources/MeetingAssistantMac/Resources/Icons/app_icon_1024.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    args = parser.parse_args()
    make_icon(args.size, Path(args.out))
    print(f"Generated icon: {args.out}")


if __name__ == "__main__":
    main()
