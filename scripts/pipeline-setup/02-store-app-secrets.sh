#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <APP_ID> <INSTALLATION_ID> <path-to-private-key.pem>"
  echo ""
  echo "  APP_ID           — numeric GitHub App ID"
  echo "  INSTALLATION_ID  — numeric installation ID (from 'gh api /repos/{owner}/{repo}/installation --jq .id')"
  echo "  path-to-private-key.pem  — path to the downloaded .pem file"
  exit 1
}

if [ "$#" -ne 3 ]; then
  usage
fi

APP_ID="$1"
INSTALLATION_ID="$2"
PEM_PATH="$3"

if [ ! -f "$PEM_PATH" ]; then
  echo "[FAIL] Private key file not found: ${PEM_PATH}"
  exit 1
fi

REPO="devinhedge/MPD-secure"

echo "[OK] Storing PIPELINE_APP_ID..."
echo -n "${APP_ID}" | gh secret set PIPELINE_APP_ID --repo "${REPO}"

echo "[OK] Storing PIPELINE_APP_INSTALLATION_ID..."
echo -n "${INSTALLATION_ID}" | gh secret set PIPELINE_APP_INSTALLATION_ID --repo "${REPO}"

echo "[OK] Storing PIPELINE_APP_PRIVATE_KEY..."
gh secret set PIPELINE_APP_PRIVATE_KEY --repo "${REPO}" < "${PEM_PATH}"

echo ""
echo "Done. Three secrets stored:"
echo "  PIPELINE_APP_ID"
echo "  PIPELINE_APP_INSTALLATION_ID"
echo "  PIPELINE_APP_PRIVATE_KEY"
