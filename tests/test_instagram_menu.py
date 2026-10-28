import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image

import download_instagram_menu as menu


FIXTURES = Path(__file__).parent / "fixtures" / "instagram"


def response_for(name, **kwargs):
    return SimpleNamespace(
        content=(FIXTURES / name).read_bytes(), raise_for_status=lambda: None,
    )


def post(urls, shortcode="menu", posted_at="2026-10-28T00:00:00Z"):
    return menu.ImagePost(urls, shortcode, posted_at)


class MenuBoardTests(unittest.TestCase):
    def test_real_boards_and_non_menu_images(self):
        for name, expected in [
            ("menu-board.jpg", True), ("menu-board-alternate.jpg", True),
            ("food-photo.jpg", False), ("sandwich-ad.jpg", False),
        ]:
            with self.subTest(name=name), Image.open(FIXTURES / name) as image:
                self.assertEqual(menu.is_menu_board(image), expected)

    def test_recompressed_and_resized_board(self):
        with Image.open(FIXTURES / "menu-board.jpg") as image:
            buffer = io.BytesIO()
            image.resize((720, 960)).save(buffer, "JPEG", quality=65)
        buffer.seek(0)
        with Image.open(buffer) as image:
            self.assertTrue(menu.is_menu_board(image))

    def test_background_alone_is_not_a_menu(self):
        self.assertFalse(menu.is_menu_board(Image.new("RGB", (600, 800), (255, 216, 170))))

    @patch.object(menu, "select_via_instaloader")
    @patch.object(menu.requests, "get")
    def test_skips_newer_food_and_filters_carousel(self, get, select):
        select.return_value = [
            post(["food-photo.jpg"], "new-food"),
            post(["food-photo.jpg", "menu-board.jpg", "sandwich-ad.jpg"], "actual-menu"),
            post(["menu-board-alternate.jpg"], "older-menu"),
        ]
        get.side_effect = response_for
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "menu.jpg"
            result = menu.download_menu("kjfo_od", output)
            with Image.open(output) as image:
                self.assertEqual(image.size, (341, 455))
            self.assertEqual(result, {
                "sourceImage": "menu-board.jpg",
                "sourcePost": "https://www.instagram.com/p/actual-menu/",
                "sourcePostedAt": "2026-10-28T00:00:00Z",
            })
        self.assertEqual(get.call_count, 4)

    @patch.object(menu, "select_via_instaloader")
    @patch.object(menu.requests, "get")
    def test_keeps_multiple_verified_boards_only(self, get, select):
        select.return_value = [post(["menu-board.jpg", "food-photo.jpg", "menu-board-alternate.jpg"])]
        get.side_effect = response_for
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "menu.jpg"
            menu.download_menu("kjfo_od", output)
            with Image.open(output) as image:
                self.assertEqual(image.size, (341, 910))

    @patch.object(menu, "select_via_instaloader")
    @patch.object(menu.requests, "get")
    def test_food_only_feed_does_not_create_output(self, get, select):
        select.return_value = [post(["food-photo.jpg", "sandwich-ad.jpg"])]
        get.side_effect = response_for
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "menu.jpg"
            with self.assertRaisesRegex(ValueError, "No verified"):
                menu.download_menu("kjfo_od", output)
            self.assertFalse(output.exists())

    @patch.object(menu, "select_via_instaloader")
    @patch.object(menu.requests, "get")
    def test_failed_image_does_not_hide_later_board(self, get, select):
        select.return_value = [post(["broken", "menu-board.jpg"])]
        get.side_effect = [menu.requests.Timeout(), response_for("menu-board.jpg")]
        with tempfile.TemporaryDirectory() as directory:
            result = menu.download_menu("kjfo_od", Path(directory) / "menu.jpg")
            self.assertEqual(result["sourceImage"], "menu-board.jpg")

    @patch.object(menu, "select_via_instaloader", side_effect=RuntimeError())
    @patch.object(menu, "select_via_embed")
    @patch.object(menu.requests, "get", return_value=response_for("menu-board.jpg"))
    def test_embed_fallback_uses_same_filter(self, get, embed, select):
        embed.return_value = [post(["board"])]
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(menu.download_menu("kjfo_od", Path(directory) / "menu.jpg")["sourceImage"], "board")

    @patch.object(menu, "download_menu", side_effect=ValueError("No verified menu"))
    def test_main_clears_previous_assets_when_no_board_is_found(self, download):
        with tempfile.TemporaryDirectory() as directory:
            output, metadata = Path(directory) / "menu.jpg", Path(directory) / "menu.json"
            output.write_bytes(b"stale food photo")
            metadata.write_text("{}")
            with patch.object(menu.sys, "argv", ["script", "kjfo_od", str(output), str(metadata)]):
                self.assertEqual(menu.main(), 1)
            self.assertFalse(output.exists())
            self.assertFalse(metadata.exists())


class FeedTests(unittest.TestCase):
    @patch.object(menu.requests, "get")
    def test_embed_sorts_pins_and_collects_all_candidates(self, get):
        nodes = [
            {"shortcode": "pinned", "taken_at_timestamp": 1, "display_url": "old"},
            {"shortcode": "video", "taken_at_timestamp": 5, "is_video": True},
            {"shortcode": "new-food", "taken_at_timestamp": 4, "display_url": "food"},
            {"shortcode": "menu", "taken_at_timestamp": 3, "edge_sidecar_to_children": {"edges": [
                {"node": {"is_video": True}}, {"node": {"display_url": "board"}},
            ]}},
        ]
        get.return_value = SimpleNamespace(
            text='"contextJSON":' + json.dumps(json.dumps({"context": {"graphql_media": [
                {"shortcode_media": node} for node in nodes
            ]}})),
            raise_for_status=lambda: None,
        )
        posts = menu.select_via_embed("kjfo_od")
        self.assertEqual([p.shortcode for p in posts], ["new-food", "menu", "pinned"])
        self.assertEqual(posts[1].urls, ["board"])
        self.assertEqual(posts[0].posted_at, "1970-01-01T00:00:04Z")

    @patch.dict(menu.os.environ, {}, clear=True)
    @patch.object(menu.instaloader.Profile, "from_username")
    @patch.object(menu.instaloader, "Instaloader")
    def test_instaloader_sorts_pins_and_does_not_reuse_video_urls(self, loader, profile):
        import datetime

        def entry(code, timestamp, video=False):
            return SimpleNamespace(
                shortcode=code, date_utc=datetime.datetime(2026, 10, timestamp),
                typename="GraphImage", is_video=video, url=code,
            )

        profile.return_value.get_posts.return_value = iter([
            entry("pinned", 1), entry("new-food", 28), entry("video", 27, True), entry("menu", 26),
        ])
        posts = menu.select_via_instaloader("kjfo_od")
        self.assertEqual([p.shortcode for p in posts], ["new-food", "menu", "pinned"])
        self.assertEqual([p.urls for p in posts], [["new-food"], ["menu"], ["pinned"]])


if __name__ == "__main__":
    unittest.main()
