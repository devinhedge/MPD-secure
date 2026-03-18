#!/usr/bin/env bash
set -euo pipefail

REPO="devinhedge/MPD-secure"

BRANCHES=(
  dev
  int
  test-ubuntu-debian
  test-fedora-rhel
  test-arch
  test-macos
  test-windows
  stage-ubuntu-debian
  stage-fedora-rhel
  stage-arch
  stage-macos
  stage-windows
)

MAIN_SHA=$(gh api "repos/${REPO}/git/ref/heads/main" --jq '.object.sha')

for branch in "${BRANCHES[@]}"; do
  existing=$(gh api "repos/${REPO}/git/ref/heads/${branch}" --jq '.object.sha' 2>/dev/null || echo "")
  if [ -n "$existing" ]; then
    echo "[SKIP] Branch already exists: ${branch}"
  else
    gh api "repos/${REPO}/git/refs" \
      --method POST \
      --field ref="refs/heads/${branch}" \
      --field sha="${MAIN_SHA}" \
      > /dev/null
    echo "[CREATE] Branch created: ${branch}"
  fi
done

echo ""
echo "Done. All 12 pipeline branches are present."
