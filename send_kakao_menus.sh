#!/usr/bin/env bash

set -euo pipefail

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
download_script="${script_dir}/download_kakao_profile.sh"
compose_script="${script_dir}/compose_menu_board.py"
teams_webhook_url="${TEAMS_WEBHOOK_URL:-}"
default_date="$(date +%F)"
docs_dir="${script_dir}/docs"
docs_images_dir="${docs_dir}/images"
docs_data_dir="${docs_dir}/data"
dry_run="${DRY_RUN:-}"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$work_dir"
}

trap cleanup EXIT

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

build_combined_menu_board() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required to build the combined menu board image." >&2
    exit 1
  fi

  uv run --with pillow python "$compose_script" \
    "${docs_images_dir}/menu-board.jpg" \
    "더이츠푸드" \
    "$theeats_file" \
    "한신 IT 카페테리아" \
    "$hanshin_file" \
    "푸드포커스" \
    "$foodfocus_file" \
    "온정 한식 뷔페" \
    "$onjeong_file" \
    "윤쉐프 코오롱" \
    "$yoonchef_kolon_file" \
    "벽산더이룸" \
    "$byeoksan_theeroom_file" >/dev/null
}

publish_web_assets() {
  mkdir -p "$docs_images_dir" "$docs_data_dir"

  cp "$theeats_file" "${docs_images_dir}/theeatsfood.jpg"
  cp "$hanshin_file" "${docs_images_dir}/hanshin-it-cafeteria.jpg"
  cp "$foodfocus_file" "${docs_images_dir}/foodfocus.jpg"
  cp "$onjeong_file" "${docs_images_dir}/onjeong-hansik-buffet.jpg"
  cp "$yoonchef_kolon_file" "${docs_images_dir}/yoonchef-kolon.jpg"
  cp "$byeoksan_theeroom_file" "${docs_images_dir}/byeoksan-theeroom.jpg"

  build_combined_menu_board

  cat > "${docs_data_dir}/latest.json" <<EOF
{
  "date": "${default_date}",
  "updatedAt": "$(date -Iseconds)",
  "combinedImage": "./images/menu-board.jpg",
  "menus": [
    {
      "id": "theeatsfood",
      "name": "TheEatsFood",
      "sourcePage": "https://pf.kakao.com/_xeVwxnn",
      "sourceImage": ${theeats_url_json},
      "image": "./images/theeatsfood.jpg"
    },
    {
      "id": "hanshin-it-cafeteria",
      "name": "Hanshin IT Cafeteria",
      "sourcePage": "https://pf.kakao.com/_QRALxb",
      "sourceImage": ${hanshin_url_json},
      "image": "./images/hanshin-it-cafeteria.jpg"
    },
    {
      "id": "foodfocus",
      "name": "FoodFocus",
      "sourcePage": "https://pf.kakao.com/_uxfhjG/113021355",
      "sourceImage": ${foodfocus_url_json},
      "image": "./images/foodfocus.jpg"
    },
    {
      "id": "onjeong-hansik-buffet",
      "name": "온정 한식 뷔페",
      "sourcePage": "https://pf.kakao.com/_BdwNn/posts",
      "sourceImage": ${onjeong_url_json},
      "image": "./images/onjeong-hansik-buffet.jpg"
    },
    {
      "id": "yoonchef-kolon",
      "name": "윤쉐프 코오롱",
      "sourcePage": "https://pf.kakao.com/_Xxhxkhs",
      "sourceImage": ${yoonchef_kolon_url_json},
      "image": "./images/yoonchef-kolon.jpg"
    },
    {
      "id": "byeoksan-theeroom",
      "name": "벽산더이룸",
      "sourcePage": "https://pf.kakao.com/_xdLzxgG",
      "sourceImage": ${byeoksan_theeroom_url_json},
      "image": "./images/byeoksan-theeroom.jpg"
    }
  ]
}
EOF
}

maybe_push_web_updates() {
  if [[ -n "$dry_run" ]]; then
    printf 'Dry run enabled; skipping git push.\n'
    return
  fi

  if ! git -C "$script_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  if [[ -z "$(git -C "$script_dir" status --short -- docs)" ]]; then
    return
  fi

  git -C "$script_dir" add docs
  git -C "$script_dir" commit -m "Update menu site for ${default_date}" >/dev/null
  git -C "$script_dir" push origin main >/dev/null
  printf 'Pushed web updates to origin/main.\n'
}

run_download() {
  local channel_url="$1"
  local output_file="$2"
  local label="$3"
  local log_file="$4"
  local css_selector="${5:-}"

  SKIP_TEAMS_WEBHOOK=1 "$download_script" "$channel_url" "$output_file" "$label" "$css_selector" | tee "$log_file"
}

theeats_file="${work_dir}/${default_date}-theeatsfood.jpg"
hanshin_file="${work_dir}/${default_date}-hanshin-it-cafeteria.jpg"
foodfocus_file="${work_dir}/${default_date}-foodfocus.jpg"
onjeong_file="${work_dir}/${default_date}-onjeong-hansik-buffet.jpg"
yoonchef_kolon_file="${work_dir}/${default_date}-yoonchef-kolon.jpg"
byeoksan_theeroom_file="${work_dir}/${default_date}-byeoksan-theeroom.jpg"

theeats_log="${work_dir}/theeats.log"
hanshin_log="${work_dir}/hanshin.log"
foodfocus_log="${work_dir}/foodfocus.log"
onjeong_log="${work_dir}/onjeong.log"
yoonchef_kolon_log="${work_dir}/yoonchef-kolon.log"
byeoksan_theeroom_log="${work_dir}/byeoksan-theeroom.log"

cd "$script_dir"

run_download "https://pf.kakao.com/_xeVwxnn" "$theeats_file" "TheEatsFood" "$theeats_log"
run_download "https://pf.kakao.com/_QRALxb" "$hanshin_file" "HanshinITCafeteria" "$hanshin_log"
run_download "https://pf.kakao.com/_uxfhjG/113021355" "$foodfocus_file" "FoodFocus" "$foodfocus_log"
run_download "https://pf.kakao.com/_BdwNn/posts" "$onjeong_file" "온정한식뷔페" "$onjeong_log" "#mArticle > div.wrap_webview > div:nth-child(2) > div.wrap_archive_content > div > div > a > div"
run_download "https://pf.kakao.com/_Xxhxkhs" "$yoonchef_kolon_file" "윤쉐프코오롱" "$yoonchef_kolon_log" "#mArticle > div.wrap_webview > div.area_card.card_profile > div > div.item_profile_head > button > span > img"
run_download "https://pf.kakao.com/_xdLzxgG" "$byeoksan_theeroom_file" "벽산더이룸" "$byeoksan_theeroom_log" "#mArticle > div.wrap_webview > div.area_card.card_profile > div > div.item_profile_head > button > span > img"

theeats_url="$(extract_source_url "$theeats_log")"
hanshin_url="$(extract_source_url "$hanshin_log")"
foodfocus_url="$(extract_source_url "$foodfocus_log")"
onjeong_url="$(extract_source_url "$onjeong_log")"
yoonchef_kolon_url="$(extract_source_url "$yoonchef_kolon_log")"
byeoksan_theeroom_url="$(extract_source_url "$byeoksan_theeroom_log")"

if [[ -z "$theeats_url" || -z "$hanshin_url" || -z "$foodfocus_url" || -z "$onjeong_url" || -z "$yoonchef_kolon_url" || -z "$byeoksan_theeroom_url" ]]; then
  echo "Failed to extract one or more image URLs from download logs." >&2
  exit 1
fi

theeats_url_json="$(json_escape "$theeats_url")"
hanshin_url_json="$(json_escape "$hanshin_url")"
foodfocus_url_json="$(json_escape "$foodfocus_url")"
onjeong_url_json="$(json_escape "$onjeong_url")"
yoonchef_kolon_url_json="$(json_escape "$yoonchef_kolon_url")"
byeoksan_theeroom_url_json="$(json_escape "$byeoksan_theeroom_url")"

publish_web_assets

menu_board_data_uri="data:image/jpeg;base64,$(base64 "${docs_images_dir}/menu-board.jpg" | tr -d '\n')"

if [[ -n "$dry_run" ]]; then
  printf 'Dry run enabled; skipping Teams webhook post.\n'
  exit 0
fi

maybe_push_web_updates

payload_file="${work_dir}/teams-payload.json"

cat > "$payload_file" <<EOF
{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"\$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":$(json_escape "${default_date} cafeteria menu board"),"wrap":true,"weight":"Bolder"},{"type":"Image","url":"${menu_board_data_uri}","size":"Stretch"}]}}]}
EOF

curl -fsSL -X POST \
  -H 'Content-Type: application/json' \
  --data-binary @"$payload_file" \
  "$teams_webhook_url" >/dev/null

printf 'Posted combined payload to Teams workflow webhook.\n'
