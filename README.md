# kakao-menu

Downloads Kakao and Instagram menu images, posts a combined Adaptive Card to a Teams workflow
webhook, and publishes a static web view under `docs/`.

## Files

- `download_kakao_profile.sh`: downloads one Kakao image from `og:image` or an
  optional rendered CSS selector
- `send_kakao_menus.sh`: downloads all configured menus, posts one combined
  Teams card, refreshes `docs/`, and pushes web updates when the repo is clean
- `download_instagram_menu.py`: finds the latest verified menu board from
  `kjfo_od` using Instaloader, with a public embed fallback
- `example.env`: environment variable template
- `docs/`: static frontend and latest published menu assets

## Setup

1. Copy `example.env` to `.cron.env` or `.env`.
2. Replace `TEAMS_WEBHOOK_URL` with your real Teams workflow webhook.
3. Make the scripts executable.
4. For selector-based sources, ensure Node.js and Playwright's CLI runtime are
   available through `npx`.

```bash
chmod +x download_kakao_profile.sh send_kakao_menus.sh
```

## Manual run

```bash
cd /path/to/kakao-menu
. ./.cron.env
./send_kakao_menus.sh
```

## Dry run

Use this when you want to verify downloads and web data generation without
sending a Teams card or pushing web updates.

```bash
cd /path/to/kakao-menu
. ./.cron.env
DRY_RUN=1 ./send_kakao_menus.sh
```

## Cron example

```cron
0 8 * * 1-5 cd /path/to/kakao-menu && . ./.cron.env && ./send_kakao_menus.sh >> ./cron.log 2>&1
```

## Web view

The latest menu board is published to `docs/`:

- `docs/data/latest.json`: latest metadata
- `docs/images/*.jpg`: current menu images, including `menu-board.jpg`
- `docs/index.html`: static UI

If GitHub Pages is enabled for the repository, the site can be served directly
from the `docs/` directory on the `main` branch.

## Instagram: kjfo_od

The scheduled run includes https://www.instagram.com/kjfo_od/ as the seventh
source in both the web view and the combined Teams menu board. It searches the
first 12 profile entries by publication time (to account for pinned posts),
skipping videos, food photos, and advertisements. Every still image in each
carousel is checked, not just the cover. Only verified menu boards from the
newest matching post are combined vertically; food photos are never used as a
fallback. The public embed fallback uses the same filtering.

The image check is specific to this account's current template: a portrait board
with a predominantly light peach background and multiple rows of both red and
blue menu text. It runs locally using Pillow, without OCR or external AI APIs.
If the restaurant changes its template, the detector must be updated; unknown
layouts are rejected conservatively. Captions alone are not trusted because food
photos can also mention menus.

The web card shows the original publication date and links to the selected post.
This is the latest verified menu, not necessarily today's menu: an 08:00 run may
find an older board if today's has not been posted yet. No new freshness cutoff
is imposed. The account handle is used as the label until its restaurant name
is verified.

`uv` installs Instaloader 4.15.3 and Pillow in its cache, without a project venv.
Anonymous access is attempted by default. If Instagram requires login, export
these settings in `.cron.env` using an existing, trusted Instaloader session:

```bash
export INSTAGRAM_USERNAME="your-instagram-login"
export INSTAGRAM_SESSION_FILE="/absolute/path/to/session-your-instagram-login"
```

Keep the session file outside this repository. Never commit login sessions.
The Instagram step has a 180-second timeout. On login/network/download failure,
or when no matching menu board is found, its image is cleared and a placeholder
is generated while other sources continue.
To check just this source without publication or notification:

```bash
uv run --with instaloader==4.15.3 --with pillow python download_instagram_menu.py \
  kjfo_od /tmp/kjfood.jpg /tmp/kjfood.json
```

Run the detector and feed-selection regression tests (no network required):

```bash
uv run --with instaloader==4.15.3 --with pillow python -m unittest discover -s tests -v
```
