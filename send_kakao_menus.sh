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
home_dir="${HOME:-$(cd "${script_dir}/.." && pwd)}"
local_bin_dir="${home_dir}/.local/bin"
fnm_default_bin="${home_dir}/.local/share/fnm/aliases/default/bin"

if [[ -d "$local_bin_dir" ]]; then
  export PATH="${local_bin_dir}:${PATH}"
fi

if [[ -d "$fnm_default_bin" ]]; then
  export PATH="${fnm_default_bin}:${PATH}"
fi

cleanup() {
  rm -rf "$work_dir"
}

trap cleanup EXIT

if [[ -z "$teams_webhook_url" ]]; then
  echo "TEAMS_WEBHOOK_URL is not set; skipping Teams notification." >&2
fi

has_valid_teams_webhook_url() {
  local url="$1"

  if [[ -z "$url" ]]; then
    return 1
  fi

  if [[ ! "$url" =~ ^https:// ]]; then
    return 1
  fi

  if [[ "$url" == *"example.invalid"* || "$url" == *"replace-with-your-teams-webhook"* ]]; then
    return 1
  fi

  return 0
}

json_escape() {
  perl -MJSON::PP -MEncode=decode -e 'binmode STDOUT, ":utf8"; print encode_json(decode("UTF-8", $ARGV[0]))' "$1"
}

json_or_null() {
  local value="${1:-}"

  if [[ -n "$value" ]]; then
    json_escape "$value"
  else
    printf 'null'
  fi
}

resolve_published_menu_board_url() {
  local explicit_url="${PUBLISHED_MENU_BOARD_URL:-}"
  local base_url="${PUBLISHED_BASE_URL:-}"
  local remote_url=""
  local owner=""
  local repo=""

  if [[ -n "$explicit_url" ]]; then
    printf '%s\n' "$explicit_url"
    return
  fi

  if [[ -n "$base_url" ]]; then
    printf '%s/images/menu-board.jpg\n' "${base_url%/}"
    return
  fi

  remote_url="$(git -C "$script_dir" remote get-url origin 2>/dev/null || true)"
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"

    if [[ "$repo" == "${owner}.github.io" ]]; then
      printf 'https://%s.github.io/images/menu-board.jpg\n' "$owner"
    else
      printf 'https://%s.github.io/%s/images/menu-board.jpg\n' "$owner" "$repo"
    fi
    return
  fi

  echo "Could not determine a public URL for docs/images/menu-board.jpg." >&2
  echo "Set PUBLISHED_MENU_BOARD_URL or PUBLISHED_BASE_URL." >&2
  exit 1
}

resolve_published_site_url() {
  local explicit_site_url="${PUBLISHED_SITE_URL:-}"
  local explicit_image_url="${PUBLISHED_MENU_BOARD_URL:-}"
  local base_url="${PUBLISHED_BASE_URL:-}"
  local remote_url=""
  local owner=""
  local repo=""

  if [[ -n "$explicit_site_url" ]]; then
    printf '%s\n' "${explicit_site_url%/}/"
    return
  fi

  if [[ -n "$base_url" ]]; then
    printf '%s/\n' "${base_url%/}"
    return
  fi

  if [[ "$explicit_image_url" =~ ^(https?://.+)/images/menu-board\.jpg(\?.*)?$ ]]; then
    printf '%s/\n' "${BASH_REMATCH[1]%/}"
    return
  fi

  remote_url="$(git -C "$script_dir" remote get-url origin 2>/dev/null || true)"
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"

    if [[ "$repo" == "${owner}.github.io" ]]; then
      printf 'https://%s.github.io/\n' "$owner"
    else
      printf 'https://%s.github.io/%s/\n' "$owner" "$repo"
    fi
    return
  fi

  echo "Could not determine a public site URL for the published menu board." >&2
  echo "Set PUBLISHED_SITE_URL, PUBLISHED_BASE_URL, or PUBLISHED_MENU_BOARD_URL." >&2
  exit 1
}

get_previous_source_image() {
  local target_id="$1"
  local json_file="${docs_dir}/data/latest.json"
  local today="$(date +%F)"

  if [[ ! -f "$json_file" ]]; then
    return
  fi

  perl -MJSON::PP -e '
    my ($id, $today) = @ARGV;
    my $json = do { local $/; <STDIN> };
    eval {
      my $data = decode_json($json);
      # Only return previous URL if the record is from a different day
      if ($data->{date} ne $today) {
        for my $menu (@{$data->{menus}}) {
          if ($menu->{id} eq $id && defined $menu->{sourceImage}) {
            print $menu->{sourceImage};
            last;
          }
        }
      }
    };
  ' "$target_id" "$today" < "$json_file"
}

add_cache_bust() {
  local url="$1"
  local separator='?'

  if [[ "$url" == *\?* ]]; then
    separator='&'
  fi

  printf '%s%sv=%s\n' "$url" "$separator" "$(date +%s)"
}

wait_for_deployment() {
  local site_url="$1"
  local expected_date="$2"
  local attempts="${3:-30}"
  local sleep_seconds="${4:-10}"
  local attempt=1
  local latest_json_url="${site_url%/}/data/latest.json"

  printf "Waiting for deployment to finish at %s (expecting date %s)...\n" "$latest_json_url" "$expected_date" >&2

  while (( attempt <= attempts )); do
    local bust_url
    bust_url="$(add_cache_bust "$latest_json_url")"
    local current_json
    current_json="$(curl -fsSL "$bust_url" 2>/dev/null || true)"

    if [[ -n "$current_json" ]]; then
      local current_date
      current_date="$(printf '%s' "$current_json" | perl -MJSON::PP -e '
        my $json = do { local $/; <STDIN> };
        eval {
          my $data = decode_json($json);
          print $data->{date};
        };
      ')"
      if [[ "$current_date" == "$expected_date" ]]; then
        printf "Deployment confirmed (date: %s).\n" "$current_date" >&2
        return 0
      fi
      printf "Current deployment date: %s (attempt %d/%d)\n" "${current_date:-unknown}" "$attempt" "$attempts" >&2
    else
      printf "Failed to fetch latest.json (attempt %d/%d)\n" "$attempt" "$attempts" >&2
    fi

    if (( attempt < attempts )); then
      sleep "$sleep_seconds"
    fi

    (( attempt += 1 ))
  done

  return 1
}

extract_source_url() {
  local log_file="$1"
  perl -ne 'if (/^Source image URL: (.+)$/) { $last = $1 } END { print $last if defined $last }' "$log_file"
}

copy_menu_image_if_present() {
  local source_file="$1"
  local target_file="$2"
  local label="$3"

  if [[ -f "$source_file" ]]; then
    cp "$source_file" "$target_file"
    return 0
  fi

  printf 'No menu image for %s; removing old asset and publishing placeholder state.\n' "$label" >&2
  rm -f "$target_file"
  return 1
}

published_image_json() {
  local source_file="$1"
  local published_path="$2"

  if [[ -f "$source_file" ]]; then
    json_escape "$published_path"
  else
    printf 'null'
  fi
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

  copy_menu_image_if_present "$theeats_file" "${docs_images_dir}/theeatsfood.jpg" "더이츠푸드" || true
  copy_menu_image_if_present "$hanshin_file" "${docs_images_dir}/hanshin-it-cafeteria.jpg" "한신 IT 카페테리아" || true
  copy_menu_image_if_present "$foodfocus_file" "${docs_images_dir}/foodfocus.jpg" "푸드포커스" || true
  copy_menu_image_if_present "$onjeong_file" "${docs_images_dir}/onjeong-hansik-buffet.jpg" "온정 한식 뷔페" || true
  copy_menu_image_if_present "$yoonchef_kolon_file" "${docs_images_dir}/yoonchef-kolon.jpg" "윤쉐프 코오롱" || true
  copy_menu_image_if_present "$byeoksan_theeroom_file" "${docs_images_dir}/byeoksan-theeroom.jpg" "벽산더이룸" || true

  theeats_image_json="$(published_image_json "$theeats_file" "./images/theeatsfood.jpg")"
  hanshin_image_json="$(published_image_json "$hanshin_file" "./images/hanshin-it-cafeteria.jpg")"
  foodfocus_image_json="$(published_image_json "$foodfocus_file" "./images/foodfocus.jpg")"
  onjeong_image_json="$(published_image_json "$onjeong_file" "./images/onjeong-hansik-buffet.jpg")"
  yoonchef_kolon_image_json="$(published_image_json "$yoonchef_kolon_file" "./images/yoonchef-kolon.jpg")"
  byeoksan_theeroom_image_json="$(published_image_json "$byeoksan_theeroom_file" "./images/byeoksan-theeroom.jpg")"

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
      "displayName": "더이츠푸드",
      "sourcePage": "https://pf.kakao.com/_xeVwxnn",
      "sourceImage": ${theeats_url_json},
      "image": ${theeats_image_json},
      "naverMap": "https://map.naver.com/v5/search/더이츠푸드",
      "lat": 37.4849,
      "lng": 126.8958
    },
    {
      "id": "hanshin-it-cafeteria",
      "name": "Hanshin IT Cafeteria",
      "displayName": "한신IT 구내식당",
      "sourcePage": "https://pf.kakao.com/_QRALxb",
      "sourceImage": ${hanshin_url_json},
      "image": ${hanshin_image_json},
      "naverMap": "https://map.naver.com/v5/search/한신IT구내식당",
      "lat": 37.4837,
      "lng": 126.8955
    },
    {
      "id": "foodfocus",
      "name": "FoodFocus",
      "displayName": "푸드포커스",
      "sourcePage": "https://pf.kakao.com/_uxfhjG/113021355",
      "sourceImage": ${foodfocus_url_json},
      "image": ${foodfocus_image_json},
      "naverMap": "https://map.naver.com/v5/search/푸드포커스",
      "lat": 37.4843,
      "lng": 126.8963
    },
    {
      "id": "onjeong-hansik-buffet",
      "name": "온정 한식 뷔페",
      "displayName": "온정 한식 뷔페",
      "sourcePage": "https://pf.kakao.com/_BdwNn/posts",
      "sourceImage": ${onjeong_url_json},
      "image": ${onjeong_image_json},
      "naverMap": "https://map.naver.com/v5/search/온정한식뷔페",
      "lat": 37.4850,
      "lng": 126.8970
    },
    {
      "id": "yoonchef-kolon",
      "name": "윤쉐프 코오롱",
      "displayName": "윤쉐프 코오롱",
      "sourcePage": "https://pf.kakao.com/_Xxhxkhs",
      "sourceImage": ${yoonchef_kolon_url_json},
      "image": ${yoonchef_kolon_image_json},
      "naverMap": "https://map.naver.com/v5/search/윤쉐프코오롱",
      "lat": 37.4853,
      "lng": 126.8931
    },
    {
      "id": "byeoksan-theeroom",
      "name": "벽산더이룸",
      "displayName": "벽산더이룸",
      "sourcePage": "https://pf.kakao.com/_xdLzxgG",
      "sourceImage": ${byeoksan_theeroom_url_json},
      "image": ${byeoksan_theeroom_image_json},
      "naverMap": "https://map.naver.com/v5/search/벽산더이룸",
      "lat": 37.4856,
      "lng": 126.8942
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
  local previous_url="${6:-}"

  PREVIOUS_URL="$previous_url" SKIP_TEAMS_WEBHOOK=1 "$download_script" "$channel_url" "$output_file" "$label" "$css_selector" | tee "$log_file"
}

download_menu_if_available() {
  local channel_url="$1"
  local output_file="$2"
  local label="$3"
  local log_file="$4"
  local css_selector="${5:-}"
  local id="$6"

  local prev_url
  prev_url="$(get_previous_source_image "$id")"

  if run_download "$channel_url" "$output_file" "$label" "$log_file" "$css_selector" "$prev_url"; then
    return 0
  fi

  rm -f "$output_file"
  printf 'Menu image unavailable or not updated for %s; continuing with a placeholder.\n' "$label" >&2
  return 1
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

download_menu_if_available "https://pf.kakao.com/_xeVwxnn" "$theeats_file" "TheEatsFood" "$theeats_log" "" "theeatsfood" || true
download_menu_if_available "https://pf.kakao.com/_QRALxb" "$hanshin_file" "HanshinITCafeteria" "$hanshin_log" "" "hanshin-it-cafeteria" || true
download_menu_if_available "https://pf.kakao.com/_uxfhjG/113021355" "$foodfocus_file" "FoodFocus" "$foodfocus_log" "" "foodfocus" || true
download_menu_if_available "https://pf.kakao.com/_BdwNn/posts" "$onjeong_file" "온정한식뷔페" "$onjeong_log" "#mArticle > div.wrap_webview > div:nth-child(2) > div.wrap_archive_content > div > div > a > div" "onjeong-hansik-buffet" || true
download_menu_if_available "https://pf.kakao.com/_Xxhxkhs" "$yoonchef_kolon_file" "윤쉐프코오롱" "$yoonchef_kolon_log" "#mArticle > div.wrap_webview > div.area_card.card_profile > div > div.item_profile_head > button > span > img" "yoonchef-kolon" || true
download_menu_if_available "https://pf.kakao.com/_xdLzxgG" "$byeoksan_theeroom_file" "벽산더이룸" "$byeoksan_theeroom_log" "#mArticle > div.wrap_webview > div.area_card.card_profile > div > div.item_profile_head > button > span > img" "byeoksan-theeroom" || true

theeats_url="$(extract_source_url "$theeats_log")"
hanshin_url="$(extract_source_url "$hanshin_log")"
foodfocus_url="$(extract_source_url "$foodfocus_log")"
onjeong_url="$(extract_source_url "$onjeong_log")"
yoonchef_kolon_url="$(extract_source_url "$yoonchef_kolon_log")"
byeoksan_theeroom_url="$(extract_source_url "$byeoksan_theeroom_log")"

theeats_url_json="$(json_or_null "$theeats_url")"
hanshin_url_json="$(json_or_null "$hanshin_url")"
foodfocus_url_json="$(json_or_null "$foodfocus_url")"
onjeong_url_json="$(json_or_null "$onjeong_url")"
yoonchef_kolon_url_json="$(json_or_null "$yoonchef_kolon_url")"
byeoksan_theeroom_url_json="$(json_or_null "$byeoksan_theeroom_url")"

publish_web_assets

if [[ -n "$dry_run" ]]; then
  printf 'Dry run enabled; skipping Teams webhook post.\n'
  exit 0
fi

maybe_push_web_updates

if ! has_valid_teams_webhook_url "$teams_webhook_url"; then
  printf 'No valid TEAMS_WEBHOOK_URL set; skipping Teams notification.\n'
  exit 0
fi

published_site_url="$(resolve_published_site_url)"

if ! wait_for_deployment "$published_site_url" "$default_date"; then
  echo "Deployment to GitHub Pages did not complete within the timeout." >&2
  exit 1
fi

menu_board_url="$(resolve_published_menu_board_url)"
menu_board_url="$(add_cache_bust "$menu_board_url")"

payload_file="${work_dir}/teams-payload.json"

cat > "$payload_file" <<EOF
{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"\$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":$(json_escape "${default_date} cafeteria menu board"),"wrap":true,"weight":"Bolder"},{"type":"Image","url":$(json_escape "$menu_board_url"),"size":"Stretch"},{"type":"TextBlock","text":$(json_escape "[Open menu board](${published_site_url})"),"wrap":true,"isSubtle":true,"spacing":"Small"}]}}]}
EOF

curl -fsSL -X POST \
  -H 'Content-Type: application/json' \
  --data-binary @"$payload_file" \
  "$teams_webhook_url" >/dev/null

printf 'Posted combined payload to Teams workflow webhook.\n'
