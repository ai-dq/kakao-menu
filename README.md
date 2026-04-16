# kakao-menu

Downloads Kakao menu images, posts a combined Adaptive Card to a Teams workflow
webhook, and publishes a static web view under `docs/`.

## Files

- `download_kakao_profile.sh`: downloads one Kakao image from `og:image` or an
  optional rendered CSS selector
- `send_kakao_menus.sh`: downloads all configured menus, posts one combined
  Teams card, refreshes `docs/`, and pushes web updates when the repo is clean
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
