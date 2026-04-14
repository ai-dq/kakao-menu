#!/usr/bin/env bash

set -euo pipefail

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <kakao-channel-url> [output-file] [label]" >&2
  exit 1
fi

channel_url="$1"
default_date="$(date +%F)"
default_label="${3:-MenuImage}"
output_file="${2:-${default_date}-${default_label}.jpg}"
teams_webhook_url="${TEAMS_WEBHOOK_URL:-}"
skip_teams_webhook="${SKIP_TEAMS_WEBHOOK:-}"

json_escape() {
  perl -MJSON::PP -MEncode=decode -e 'binmode STDOUT, ":utf8"; print encode_json(decode("UTF-8", $ARGV[0]))' "$1"
}

html="$(curl -fsSL "$channel_url")"

image_url="$(
  printf '%s' "$html" \
    | perl -ne 'if (/<meta property="og:image" content="([^"]+)"/) { print $1; exit }'
)"

if [[ -z "$image_url" ]]; then
  echo "Could not find og:image in: $channel_url" >&2
  exit 1
fi

image_url="${image_url/http:\/\//https://}"

candidate_urls=("$image_url")

if [[ "$image_url" =~ /img_[a-z]+\.jpg$ ]]; then
  xl_url="$(printf '%s' "$image_url" | sed 's#/img_[a-z]\+\.jpg$#/img_xl.jpg#')"
  if [[ "$xl_url" != "$image_url" ]]; then
    candidate_urls=("$xl_url" "$image_url")
  fi
fi

downloaded_url=""

for candidate_url in "${candidate_urls[@]}"; do
  if curl -fsI "$candidate_url" >/dev/null 2>&1; then
    curl -fsSL "$candidate_url" -o "$output_file"
    downloaded_url="$candidate_url"
    break
  fi
done

if [[ -z "$downloaded_url" ]]; then
  echo "Found image URL but failed to download it." >&2
  exit 1
fi

printf 'Saved profile image to %s\n' "$output_file"
printf 'Source image URL: %s\n' "$downloaded_url"

if [[ -n "$teams_webhook_url" && -z "$skip_teams_webhook" ]]; then
  payload="$(
    cat <<EOF
{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"\$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":$(json_escape "${default_date} ${default_label} menu image"),"wrap":true,"weight":"Bolder"},{"type":"Image","url":$(json_escape "$downloaded_url"),"size":"Stretch"},{"type":"TextBlock","text":$(json_escape "$downloaded_url"),"wrap":true,"isSubtle":true,"spacing":"Small"}]}}]}
EOF
  )"

  curl -fsSL -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$teams_webhook_url" >/dev/null

  printf 'Posted payload to Teams workflow webhook.\n'
fi
