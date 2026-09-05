#!/usr/bin/env bash
# Post release binaries to APP_CHANNEL via Bot API sendDocument.
#
# Cloud Bot API caps uploads at 50 MiB. CI runs a local telegram-bot-api (--local)
# and sets APP_BOT_API_BASE=http://127.0.0.1:8081 so Windows/macOS (~70–100 MiB) fit.
#
# Required env: APP_BOT_TOKEN, APP_CHANNEL, VERSION
# Optional env: APP_BOT_API_BASE (default https://api.telegram.org)
# APP_CHANNEL: -100…  or  name|-100…  or  @username
set -euo pipefail

TOKEN="${APP_BOT_TOKEN:?APP_BOT_TOKEN missing}"
RAW="${APP_CHANNEL:?APP_CHANNEL missing}"
VERSION="${VERSION:?VERSION missing}"
BASE="${APP_BOT_API_BASE:-https://api.telegram.org}"
BASE="${BASE%/}"

CHAT="$RAW"
if [[ "$CHAT" == *"|"* ]]; then
  CHAT="${CHAT##*|}"
fi

CLOUD_MAX=$((50 * 1024 * 1024))
local_api=0
if [[ "$BASE" != "https://api.telegram.org" ]]; then
  local_api=1
fi

posted=0

file_label() {
  case "$1" in
    *arm64-v8a*.apk) echo "Android arm64-v8a" ;;
    *armeabi-v7a*.apk) echo "Android armeabi-v7a" ;;
    *x86_64*.apk) echo "Android x86_64" ;;
    *-Setup.exe) echo "Windows installer" ;;
    *Windows*.zip) echo "Windows portable" ;;
    *.ipa) echo "iOS" ;;
    *.dmg) echo "macOS" ;;
    *.flatpak) echo "Linux Flatpak" ;;
    *.AppImage.zsync) echo "Linux AppImage zsync" ;;
    *.AppImage) echo "Linux AppImage" ;;
    *Linux*.zip) echo "Linux bundle" ;;
    *) echo "$(basename "$1")" ;;
  esac
}

post_one() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "::warning::skip missing ${file}"
    return 0
  fi
  local size
  size="$(stat -c%s "$file")"
  if (( local_api == 0 && size >= CLOUD_MAX )); then
    echo "::error::${file} is ${size} bytes; cloud Bot API cap is 50 MiB. Run local telegram-bot-api (APP_BOT_API_BASE)."
    return 1
  fi

  local cap="Sushi ${VERSION} · $(file_label "$file")"
  echo "Uploading $(basename "$file") (${size} bytes) via ${BASE}"

  local tmp http
  tmp="$(mktemp)"
  http="$(curl -sS -o "$tmp" -w "%{http_code}" --max-time 900 \
    -F "chat_id=${CHAT}" \
    -F "document=@${file}" \
    -F "caption=${cap}" \
    -F "disable_notification=true" \
    "${BASE}/bot${TOKEN}/sendDocument")" || true

  if ! jq -e '.ok == true' "$tmp" >/dev/null 2>&1; then
    local desc
    desc="$(jq -r '.description // empty' "$tmp" 2>/dev/null || true)"
    echo "::error::sendDocument HTTP ${http}: ${desc:-upload failed}"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  echo "Posted $(basename "$file")"
  posted=$((posted + 1))
}

if [[ $# -lt 1 ]]; then
  echo "::error::no files passed"
  exit 1
fi

for f in "$@"; do
  post_one "$f"
done

if (( posted == 0 )); then
  echo "::error::no files posted"
  exit 1
fi
echo "Posted ${posted} file(s) to APP_CHANNEL"
