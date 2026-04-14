# kakao-menu

Downloads Kakao channel menu images and posts a combined Adaptive Card to a Teams workflow webhook.

## Files

- `download_kakao_profile.sh`: downloads one Kakao image from `og:image`
- `send_kakao_menus.sh`: downloads all configured menus and posts one combined Teams card
- `example.env`: environment variable template

## Setup

1. Copy `example.env` to `.cron.env` or `.env`.
2. Replace `TEAMS_WEBHOOK_URL` with your real Teams workflow webhook.
3. Make the scripts executable.

```bash
chmod +x download_kakao_profile.sh send_kakao_menus.sh
```

## Manual run

```bash
cd /path/to/kakao-menu
. ./.cron.env
./send_kakao_menus.sh
```

## Cron example

```cron
0 8 * * 1-5 cd /path/to/kakao-menu && . ./.cron.env && ./send_kakao_menus.sh >> ./cron.log 2>&1
```
