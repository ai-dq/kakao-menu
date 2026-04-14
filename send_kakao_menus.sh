#!/usr/bin/env bash

set -euo pipefail

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
download_script="${script_dir}/download_kakao_profile.sh"
teams_webhook_url="${TEAMS_WEBHOOK_URL:-}"
default_date="$(date +%F)"

if [[ -z "$teams_webhook_url" ]]; then
  echo "TEAMS_WEBHOOK_URL is not set." >&2
  exit 1
fi

json_escape() {
  perl -MJSON::PP -MEncode=decode -e 'binmode STDOUT, ":utf8"; print encode_json(decode("UTF-8", $ARGV[0]))' "$1"
}

extract_source_url() {
  local log_file="$1"
  perl -ne 'if (/^Source image URL: (.+)$/) { $last = $1 } END { print $last if defined $last }' "$log_file"
}

run_download() {
  local channel_url="$1"
  local output_file="$2"
  local label="$3"
  local log_file="$4"

  SKIP_TEAMS_WEBHOOK=1 "$download_script" "$channel_url" "$output_file" "$label" | tee "$log_file"
}

theeats_log="$(mktemp)"
hanshin_log="$(mktemp)"
foodfocus_log="$(mktemp)"
trap 'rm -f "$theeats_log" "$hanshin_log" "$foodfocus_log"' EXIT

cd "$script_dir"

run_download "https://pf.kakao.com/_xeVwxnn" "${default_date}-theeatsfood.jpg" "TheEatsFood" "$theeats_log"
run_download "https://pf.kakao.com/_QRALxb" "${default_date}-hanshin-it-cafeteria.jpg" "HanshinITCafeteria" "$hanshin_log"
run_download "https://pf.kakao.com/_uxfhjG/113021355" "${default_date}-foodfocus.jpg" "FoodFocus" "$foodfocus_log"

theeats_url="$(extract_source_url "$theeats_log")"
hanshin_url="$(extract_source_url "$hanshin_log")"
foodfocus_url="$(extract_source_url "$foodfocus_log")"

if [[ -z "$theeats_url" || -z "$hanshin_url" || -z "$foodfocus_url" ]]; then
  echo "Failed to extract one or more image URLs from download logs." >&2
  exit 1
fi

payload="$(
  cat <<EOF
{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"\$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":$(json_escape "${default_date} cafeteria menu images"),"wrap":true,"weight":"Bolder"},{"type":"TextBlock","text":"TheEatsFood","wrap":true,"spacing":"Medium"},{"type":"Image","url":$(json_escape "$theeats_url"),"size":"Stretch"},{"type":"TextBlock","text":"HanshinITCafeteria","wrap":true,"spacing":"Medium"},{"type":"Image","url":$(json_escape "$hanshin_url"),"size":"Stretch"},{"type":"TextBlock","text":"FoodFocus","wrap":true,"spacing":"Medium"},{"type":"Image","url":$(json_escape "$foodfocus_url"),"size":"Stretch"}]}}]}
EOF
)"

curl -fsSL -X POST \
  -H 'Content-Type: application/json' \
  -d "$payload" \
  "$teams_webhook_url" >/dev/null

printf 'Posted combined payload to Teams workflow webhook.\n'
