#!/usr/bin/env python3

from __future__ import annotations

import datetime
import io
import itertools
import json
import os
import re
import sys
from pathlib import Path

import instaloader
import requests
from PIL import Image


def select_via_instaloader(username: str) -> tuple[list[str], str, str]:
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
    selected_post = None
    urls = []
    for post in posts:
        if post.typename == "GraphSidecar":
            urls = [node.display_url for node in post.get_sidecar_nodes() if not node.is_video]
        elif not post.is_video:
            urls = [post.url]
        if urls:
            selected_post = post
            break
    if selected_post is None:
        raise ValueError("No image posts found among the 12 most recent profile entries.")

    return urls, selected_post.shortcode, selected_post.date_utc.isoformat() + "Z"


def select_via_embed(username: str) -> tuple[list[str], str, str]:
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
    for node in nodes:
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
            return urls, node["shortcode"], posted_at.isoformat() + "Z"
    raise ValueError("No image posts found in the profile embed.")


def download_menu(username: str, output: Path) -> dict:
    try:
        urls, shortcode, posted_at = select_via_instaloader(username)
    except Exception as error:
        print(f"Instaloader failed ({type(error).__name__}); trying public embed.", file=sys.stderr)
        urls, shortcode, posted_at = select_via_embed(username)

    images = []
    for url in urls:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        with Image.open(io.BytesIO(response.content)) as source:
            converted = source.convert("RGB")
        width = min(converted.width, 1440)
        height = max(1, round(converted.height * width / converted.width))
        images.append(converted.resize((width, height), Image.Resampling.LANCZOS))

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
        "sourcePost": f"https://www.instagram.com/p/{shortcode}/",
        "sourcePostedAt": posted_at,
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
              "If login is required, configure INSTAGRAM_USERNAME and INSTAGRAM_SESSION_FILE.",
              file=sys.stderr)
        return 1
    print(f"Saved Instagram menu to {output}")
    print(f"Source image URL: {result['sourceImage']}")
    print(f"Source post URL: {result['sourcePost']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
