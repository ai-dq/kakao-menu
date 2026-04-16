#!/usr/bin/env python3

from __future__ import annotations

import io
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BACKGROUND = (245, 245, 245)
PADDING = 24
GAP = 24
COLUMNS = 2
TILE_WIDTH = 900
LABEL_HEIGHT = 76
LABEL_PADDING_X = 24
LABEL_FONT_SIZE = 42
TILE_BACKGROUND = (255, 255, 255)
LABEL_BACKGROUND = (238, 238, 238)
LABEL_TEXT = (32, 32, 32)
JPEG_QUALITIES = (88, 84, 80, 76, 72, 68, 64)
TARGET_BYTES = 1_000_000
FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/nanum/NanumSquareB.ttf",
    "/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
)


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in FONT_CANDIDATES:
        font_path = Path(candidate)
        if font_path.exists():
            return ImageFont.truetype(str(font_path), size=size)
    return ImageFont.load_default()


def resize_to_width(image: Image.Image, width: int) -> Image.Image:
    scale = width / image.width
    height = max(1, round(image.height * scale))
    return image.resize((width, height), Image.Resampling.LANCZOS)


def fit_font(label: str, max_width: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for size in range(LABEL_FONT_SIZE, 17, -2):
        font = load_font(size)
        bbox = font.getbbox(label)
        if bbox[2] - bbox[0] <= max_width:
            return font
    return load_font(18)


def build_labeled_tile(image: Image.Image, label: str) -> Image.Image:
    tile = Image.new("RGB", (image.width, image.height + LABEL_HEIGHT), TILE_BACKGROUND)
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, image.width, LABEL_HEIGHT), fill=LABEL_BACKGROUND)

    font = fit_font(label, image.width - LABEL_PADDING_X * 2)
    bbox = draw.textbbox((0, 0), label, font=font)
    text_height = bbox[3] - bbox[1]
    x = LABEL_PADDING_X
    y = max(0, (LABEL_HEIGHT - text_height) // 2 - bbox[1])
    draw.text((x, y), label, fill=LABEL_TEXT, font=font)

    tile.paste(image, (0, LABEL_HEIGHT))
    return tile


def save_with_size_budget(canvas: Image.Image, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    selected_bytes: bytes | None = None
    for quality in JPEG_QUALITIES:
        buffer = io.BytesIO()
        canvas.save(buffer, format="JPEG", quality=quality, optimize=True, progressive=True)
        data = buffer.getvalue()
        selected_bytes = data
        if len(data) <= TARGET_BYTES:
            break

    if selected_bytes is None:
        raise RuntimeError("Failed to encode combined menu board.")

    output_path.write_bytes(selected_bytes)


def build_board(output_path: Path, items: list[tuple[str, Path]]) -> None:
    resized_images: list[Image.Image] = []
    row_heights = []

    for index, (label, image_path) in enumerate(items):
        with Image.open(image_path) as source:
            converted = source.convert("RGB")
        resized = resize_to_width(converted, TILE_WIDTH)
        tile = build_labeled_tile(resized, label)
        resized_images.append(tile)

        row_index = index // COLUMNS
        if row_index == len(row_heights):
            row_heights.append(tile.height)
        else:
            row_heights[row_index] = max(row_heights[row_index], tile.height)

    canvas_width = PADDING * 2 + TILE_WIDTH * COLUMNS + GAP * (COLUMNS - 1)
    canvas_height = PADDING * 2 + sum(row_heights) + GAP * (len(row_heights) - 1)
    canvas = Image.new("RGB", (canvas_width, canvas_height), BACKGROUND)

    y = PADDING
    for row_index in range(len(row_heights)):
        row_start = row_index * COLUMNS
        row_images = resized_images[row_start : row_start + COLUMNS]
        x = PADDING

        for image in row_images:
            canvas.paste(image, (x, y))
            x += TILE_WIDTH + GAP

        y += row_heights[row_index] + GAP

    save_with_size_budget(canvas, output_path)


def main() -> int:
    if len(sys.argv) < 4 or (len(sys.argv) - 2) % 2 != 0:
        print(
            "Usage: compose_menu_board.py <output-file> <label> <image> [<label> <image> ...]",
            file=sys.stderr,
        )
        return 1

    output_path = Path(sys.argv[1])
    items = [(sys.argv[index], Path(sys.argv[index + 1])) for index in range(2, len(sys.argv), 2)]

    if not items:
        print("No input images were provided.", file=sys.stderr)
        return 1

    build_board(output_path, items)
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
