#!/usr/bin/env python3

from __future__ import annotations

import datetime
import io
import itertools
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import instaloader
import requests
from PIL import Image, ImageOps


@dataclass(frozen=True)
class ImagePost:
    urls: list[str]
    shortcode: str
    posted_at: str


def select_via_instaloader(username: str) -> list[ImagePost]:
    loader = instaloader.Instaloader(
        quiet=True, max_connection_attempts=1, request_timeout=20,
        iphone_support=False,
    )
    session_file = os.environ.get("INSTAGRAM_SESSION_FILE")
    login_username = os.environ.get("INSTAGRAM_USERNAME")
    if session_file:
        if not login_username:
            raise ValueError("INSTAGRAM_USERNAME is required with INSTAGRAM_SESSION_FILE.")
        loader.load_session_from_file(login_username, session_file)

    profile = instaloader.Profile.from_username(loader.context, username)
    # Pinned posts can precede the newest post in the profile feed.
    posts = sorted(
        itertools.islice(profile.get_posts(), 12),
        key=lambda post: post.date_utc,
        reverse=True,
    )
    candidates = []
    for post in posts:
        if post.typename == "GraphSidecar":
            urls = [node.display_url for node in post.get_sidecar_nodes() if not node.is_video]
        elif not post.is_video:
            urls = [post.url]
        else:
            urls = []
        if urls:
            candidates.append(ImagePost(urls, post.shortcode, post.date_utc.isoformat() + "Z"))
    return candidates


def select_via_embed(username: str) -> list[ImagePost]:
    """Login-free fallback: the public profile embed page lists recent posts."""
    response = requests.get(
        f"https://www.instagram.com/{username}/embed/",
        headers={"User-Agent": "Mozilla/5.0"},
        timeout=30,
    )
    response.raise_for_status()
    marker = '"contextJSON":'
    index = response.text.find(marker)
    if index < 0:
        raise ValueError("Embed page has no profile data.")
    context_json, _ = json.JSONDecoder().raw_decode(response.text[index + len(marker):])
    posts = json.loads(context_json)["context"].get("graphql_media") or []
    nodes = sorted(
        (post.get("shortcode_media", post) for post in posts),
        key=lambda node: node.get("taken_at_timestamp", 0),
        reverse=True,
    )
    candidates = []
    for node in nodes[:12]:
        children = [edge["node"] for edge in (node.get("edge_sidecar_to_children") or {}).get("edges", [])]
        if children:
            urls = [child["display_url"] for child in children if not child.get("is_video")]
        elif not node.get("is_video"):
            urls = [node["display_url"]]
        else:
            urls = []
        if urls:
            posted_at = datetime.datetime.fromtimestamp(
                node["taken_at_timestamp"], datetime.timezone.utc
            ).replace(tzinfo=None)
            candidates.append(ImagePost(urls, node["shortcode"], posted_at.isoformat() + "Z"))
    return candidates


def is_menu_board(image: Image.Image) -> bool:
    """Recognize kjfo_od's peach board with rows of red AND blue menu text.

    Deliberately account-specific and conservative: captions/hashtags also occur
    on food photos. Color coverage alone also matches some food/advertisements,
    so require several separate text-colored bands in the center of the board.
    No OCR service, credentials or additional runtime dependencies are needed.
    """
    if not 0.5 <= image.width / image.height <= 1.1:
        return False
    sample = image.convert("RGB").resize((240, 320), Image.Resampling.LANCZOS)
    pixels = sample.load()
    background = 0
    red_rows, blue_rows = [], []
    for y in range(320):
        red, blue = 0, 0
        for x in range(240):
            r, g, b = pixels[x, y]
            background += (
                r >= 225 and 180 <= g <= 235 and 130 <= b <= 200
                and 20 <= r - g <= 70 and 25 <= g - b <= 75
            )
            if 36 <= x < 204:
                red += r > 150 and r > g * 1.5 and r > b * 1.4
                blue += b > 90 and b > r * 1.15 and g > r * 1.1
        # Ignore the logo/title and footer; inspect the menu list itself.
        if 60 <= y < 294:
            red_rows.append(red >= 14)
            blue_rows.append(blue >= 14)

    def bands(rows: list[bool]) -> int:
        return sum(active and (i == 0 or not rows[i - 1]) for i, active in enumerate(rows))

    return background / (240 * 320) >= 0.4 and bands(red_rows) >= 4 and bands(blue_rows) >= 3


def download_menu(username: str, output: Path) -> dict:
    try:
        posts = select_via_instaloader(username)
    except Exception as error:
        print(f"Instaloader failed ({type(error).__name__}); trying public embed.", file=sys.stderr)
        posts = select_via_embed(username)

    # Search past food-photo posts, and inspect every still image in a carousel.
    # Stop at the newest post containing a verified board, not the newest image.
    for post in posts:
        images, urls = [], []
        for url in post.urls:
            try:
                response = requests.get(url, timeout=15)
                response.raise_for_status()
                with Image.open(io.BytesIO(response.content)) as source:
                    converted = ImageOps.exif_transpose(source).convert("RGB")
            except (requests.RequestException, OSError, ValueError) as error:
                print(f"Skipping image in {post.shortcode} ({type(error).__name__}).", file=sys.stderr)
                continue
            if not is_menu_board(converted):
                continue
            width = min(converted.width, 1440)
            height = max(1, round(converted.height * width / converted.width))
            images.append(converted.resize((width, height), Image.Resampling.LANCZOS))
            urls.append(url)
        if images:
            break
        print(f"Skipping {post.shortcode}: no verified menu board.", file=sys.stderr)
    else:
        raise ValueError("No verified kjfo_od menu board found in recent posts.")

    width = max(image.width for image in images)
    canvas = Image.new("RGB", (width, sum(image.height for image in images)), "white")
    y = 0
    for image in images:
        canvas.paste(image, ((width - image.width) // 2, y))
        y += image.height
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = output.with_suffix(".tmp.jpg")
    try:
        canvas.save(temporary_output, "JPEG", quality=90)
        temporary_output.replace(output)
    finally:
        temporary_output.unlink(missing_ok=True)

    return {
        "sourceImage": urls[0],
        "sourcePost": f"https://www.instagram.com/p/{post.shortcode}/",
        "sourcePostedAt": post.posted_at,
    }


def main() -> int:
    if len(sys.argv) != 4 or not re.fullmatch(r"[A-Za-z0-9_.]+", sys.argv[1]):
        print("Usage: download_instagram_menu.py <username> <output.jpg> <metadata.json>", file=sys.stderr)
        return 1
    output, metadata = Path(sys.argv[2]), Path(sys.argv[3])
    output.unlink(missing_ok=True)
    metadata.unlink(missing_ok=True)
    try:
        result = download_menu(sys.argv[1], output)
        metadata.write_text(json.dumps(result), encoding="utf-8")
    except Exception as error:
        output.unlink(missing_ok=True)
        metadata.unlink(missing_ok=True)
        print(f"Instagram menu unavailable ({type(error).__name__}). "
              "A matching menu board and accessible images are required. "
              "If login is required, configure INSTAGRAM_USERNAME and INSTAGRAM_SESSION_FILE.",
              file=sys.stderr)
        return 1
    print(f"Saved Instagram menu to {output}")
    print(f"Source image URL: {result['sourceImage']}")
    print(f"Source post URL: {result['sourcePost']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
