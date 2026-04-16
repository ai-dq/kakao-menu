#!/usr/bin/env bash

set -euo pipefail

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "Usage: $0 <kakao-channel-url> [output-file] [label] [css-selector]" >&2
  exit 1
fi

channel_url="$1"
default_date="$(date +%F)"
default_label="${3:-MenuImage}"
output_file="${2:-${default_date}-${default_label}.jpg}"
css_selector="${4:-}"
teams_webhook_url="${TEAMS_WEBHOOK_URL:-}"
skip_teams_webhook="${SKIP_TEAMS_WEBHOOK:-}"

json_escape() {
  perl -MJSON::PP -MEncode=decode -e 'binmode STDOUT, ":utf8"; print encode_json(decode("UTF-8", $ARGV[0]))' "$1"
}

decode_json_string() {
  perl -MJSON::PP -e 'my $input = do { local $/; <STDIN> }; print decode_json($input)'
}

extract_og_image_url() {
  local html="$1"

  printf '%s' "$html" \
    | perl -ne 'if (/<meta property="og:image" content="([^"]+)"/) { print $1; exit }'
}

extract_selector_image_url() {
  local selector="$1"
  local session_name="kakao-menu-$$-$RANDOM"
  local raw_output=""
  local eval_script=""
  local selector_json=""

  if ! command -v npx >/dev/null 2>&1; then
    echo "npx is required for selector-based downloads." >&2
    return 1
  fi

  selector_json="$(json_escape "$selector")"
  eval_script="$(cat <<'EOF'
() => {
  const selector = __SELECTOR__;
  const el = document.querySelector(selector);
  if (!el) {
    return "";
  }

  if (el instanceof HTMLImageElement) {
    return el.currentSrc || el.src || "";
  }

  const nestedImg = el.querySelector("img");
  if (nestedImg instanceof HTMLImageElement) {
    return nestedImg.currentSrc || nestedImg.src || "";
  }

  const backgroundImage = getComputedStyle(el).backgroundImage || "";
  const match = backgroundImage.match(/^url\((["']?)(.*?)\1\)$/);
  return match ? match[2] : "";
}
EOF
)"
  eval_script="${eval_script/__SELECTOR__/$selector_json}"

  if ! npx --yes --package @playwright/cli playwright-cli --session "$session_name" open "$channel_url" >/dev/null 2>&1; then
    echo "Failed to open page for selector extraction: $channel_url" >&2
    return 1
  fi

  raw_output="$(
    npx --yes --package @playwright/cli playwright-cli --session "$session_name" --raw eval "$eval_script"
  )" || {
    npx --yes --package @playwright/cli playwright-cli --session "$session_name" close >/dev/null 2>&1 || true
    return 1
  }

  npx --yes --package @playwright/cli playwright-cli --session "$session_name" close >/dev/null 2>&1 || true
  printf '%s' "$raw_output" | decode_json_string
}

if [[ -n "$css_selector" ]]; then
  image_url="$(extract_selector_image_url "$css_selector")"
  if [[ -z "$image_url" ]]; then
    html="$(curl -fsSL "$channel_url")"
    image_url="$(extract_og_image_url "$html")"
  fi

  if [[ -z "$image_url" ]]; then
    echo "Could not resolve selector or og:image in: $channel_url" >&2
    exit 1
  fi
else
  html="$(curl -fsSL "$channel_url")"
  image_url="$(extract_og_image_url "$html")"

  if [[ -z "$image_url" ]]; then
    echo "Could not find og:image in: $channel_url" >&2
    exit 1
  fi
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
