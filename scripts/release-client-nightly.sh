#!/usr/bin/env bash
# Dispatch a sushi-app nightly of origin/main. No version bump, no tag.
# Stable releases stay on release-client.sh (tag v* → build_type=release).
# Nightly binaries are posted to APP_CHANNEL but only beta testers see them, and only in the app.
#
# Usage: bash scripts/release-client-nightly.sh [--dry-run] [-y]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-common.sh
source "${SCRIPT_DIR}/release-common.sh"

REPO="Gurbeh/sushi-app"
WORKFLOW="Build Sushi"

release_nightly_help() {
  cat <<'EOF'
Usage: release-client-nightly.sh [options]

Dispatches Build Sushi with build_type=nightly on origin/main.
Does not bump pubspec or create a tag.

Options:
  --dry-run   Show the plan only
  -y, --yes   Skip confirmation

Requires: gh auth login, clean main, even with origin/main.
If local main is ahead, push first. A non-release push already starts nightly.
EOF
}

DRY=0
YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) release_nightly_help; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      release_nightly_help
      exit 1
      ;;
  esac
done

cd "${SCRIPT_DIR}/.."
ROOT="$(release_root)"
cd "${ROOT}"

release_require_gh_auth
release_preflight

ahead="$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
if [[ "${ahead}" -gt 0 ]]; then
  echo "error: local main is ${ahead} commit(s) ahead of origin/main — push first" >&2
  echo "A non-release push to main already starts the nightly workflow." >&2
  exit 1
fi

echo ""
echo "Nightly plan:"
echo "  repo:     ${REPO}"
echo "  ref:      origin/main ($(git log origin/main -1 --oneline))"
echo "  workflow: ${WORKFLOW}  build_type=nightly"
echo ""

if [[ "${DRY}" == "1" ]]; then
  echo "[dry-run] Would run: gh workflow run \"${WORKFLOW}\" --repo ${REPO} --ref main -f build_type=nightly"
  exit 0
fi

if [[ "${YES}" != "1" ]]; then
  read -r -p "Dispatch nightly? [y/N] " ans
  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

gh workflow run "${WORKFLOW}" --repo "${REPO}" --ref main -f build_type=nightly

echo ""
echo "=== nightly dispatched ==="
echo "Watch build:"
echo "  gh run list --repo ${REPO} --workflow='${WORKFLOW}' --limit 3"
echo "  gh run watch --repo ${REPO}"
echo ""
echo "CI posts binaries to @sushiMovieNews. Only users.beta_tester see them, inside the app."
