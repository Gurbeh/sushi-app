#!/usr/bin/env bash
# Post release APKs to the Sushi Telegram channel via Bot API sendDocument.
# Telegram cloud bots cap uploads at 50 MiB. Larger files are skipped with a warning.
#
# Required env: APP_BOT_TOKEN, APP_CHANNEL, VERSION
# APP_CHANNEL: -100…  or  name|-100…  or  @username
set -euo pipefail

TOKEN="${APP_BOT_TOKEN:?APP_BOT_TOKEN missing}"
RAW="${APP_CHANNEL:?APP_CHANNEL missing}"
VERSION="${VERSION:?VERSION missing}"

CHAT="$RAW"
if [[ "$CHAT" == *"|"* ]]; then
  CHAT="${CHAT##*|}"
fi

MAX=$((50 * 1024 * 1024))
posted=0

abi_label() {
  case "$1" in
    *arm64-v8a*) echo "Android arm64-v8a" ;;
    *armeabi-v7a*) echo "Android armeabi-v7a" ;;
    *x86_64*) echo "Android x86_64" ;;
    *) echo "Android" ;;
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
  if (( size >= MAX )); then
    echo "::warning::skip ${file} (${size} bytes >= 50MiB Telegram cap)"
    return 0
  fi

  local cap="Sushi ${VERSION} · $(abi_label "$file")"
  echo "Uploading $(basename "$file") (${size} bytes)"

  local tmp http
  tmp="$(mktemp)"
  http="$(curl -sS -o "$tmp" -w "%{http_code}" --max-time 300 \
    -F "chat_id=${CHAT}" \
    -F "document=@${file}" \
    -F "caption=${cap}" \
    -F "disable_notification=true" \
    "https://api.telegram.org/bot${TOKEN}/sendDocument")" || true

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
  echo "::error::no files posted (all missing or over 50MiB)"
  exit 1
fi
echo "Posted ${posted} file(s) to Sushi channel"
