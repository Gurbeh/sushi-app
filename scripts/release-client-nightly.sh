#!/usr/bin/env bash
# Bump pubspec patch +1, commit, push main. No tag.
# The push starts Build Sushi as nightly (the commit must not look like "Release M.m.p:").
# A v* tag would ship a stable build to everyone. Nightly stays on the nightly shelf.
#
# Usage: bash scripts/release-client-nightly.sh [--dry-run] [-y] [summary]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-common.sh
source "${SCRIPT_DIR}/release-common.sh"

REPO="Gurbeh/sushi-app"
WORKFLOW="Build Sushi"

release_nightly_help() {
  cat <<'EOF'
Usage: release-client-nightly.sh [options] [summary]

Bumps pubspec patch (1.1.200 → 1.1.201), commits, pushes main.
Does not create a v* tag. The push builds nightly, not a stable release.

Options:
  --dry-run   Show the plan only
  -y, --yes   Skip confirmation

Requires: gh auth login, clean main, not behind origin/main.
Summary defaults to "Nightly".
EOF
}

DRY=0
YES=0
SUMMARY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift ;;
    --dry-run) DRY=1; shift ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) release_nightly_help; exit 0 ;;
    -*)
      echo "error: unknown argument: $1" >&2
      release_nightly_help
      exit 1
      ;;
    *)
      if [[ -z "${SUMMARY}" ]]; then
        SUMMARY="$1"
      else
        SUMMARY="${SUMMARY} $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "${SUMMARY}" ]]; then
  SUMMARY="Nightly"
fi

cd "${SCRIPT_DIR}/.."
ROOT="$(release_root)"
cd "${ROOT}"

release_require_gh_auth
release_preflight

NEW_VERSION="$(release_client_next_version)"
VERSION_NAME="$(release_client_version_name "${NEW_VERSION}")"
TAG="v${VERSION_NAME}"
CHANGELOG="fastlane/metadata/android/en-US/changelogs/${VERSION_NAME}.txt"

if git rev-parse "${TAG}" &>/dev/null; then
  echo "error: tag ${TAG} already exists — that version is a stable release" >&2
  exit 1
fi

echo ""
echo "Nightly plan:"
echo "  version: ${VERSION_NAME}  (pubspec ${NEW_VERSION})"
echo "  tag:     none (push main only)"
echo "  summary: ${SUMMARY}"
echo "  head:    $(git log -1 --oneline)"
echo ""

if [[ "${DRY}" == "1" ]]; then
  echo "[dry-run] Would set pubspec.yaml version: ${NEW_VERSION}"
  echo "[dry-run] Would write ${CHANGELOG}"
  echo "[dry-run] Would commit and push main (no tag)"
  exit 0
fi

if [[ "${YES}" != "1" ]]; then
  read -r -p "Bump to ${VERSION_NAME} and push nightly? [y/N] " ans
  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

sed -i.bak "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
rm -f pubspec.yaml.bak

mkdir -p "$(dirname "${CHANGELOG}")"
printf '%s\n' "${SUMMARY}" >"${CHANGELOG}"

git add pubspec.yaml "${CHANGELOG}"

# Must not match CI's "Release M.m.p:" skip, or this push would not build.
SUBJECT="Nightly ${VERSION_NAME}."

git commit -m "$(cat <<EOF
${SUBJECT}

${SUMMARY}.
EOF
)"

export OX_SKIP_VERIFY=1
git push origin main

echo ""
echo "=== nightly ${VERSION_NAME} pushed ==="
echo "CI stamps the shelf as ${VERSION_NAME}-nightly.<versionCode>."
echo "Watch build:"
echo "  gh run list --repo ${REPO} --workflow='${WORKFLOW}' --limit 3"
echo "  gh run watch --repo ${REPO}"
echo ""
echo "Only admin, superadmin, and users.beta_tester see it, inside the app."
