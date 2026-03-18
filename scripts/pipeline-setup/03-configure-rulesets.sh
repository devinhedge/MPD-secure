#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <INSTALLATION_ID> [SAST_CHECK] [CVE_CHECK] [SECRETS_CHECK]"
  echo ""
  echo "  INSTALLATION_ID  — GitHub App installation ID"
  echo "  SAST_CHECK       — status check context for SAST (default: sast)"
  echo "  CVE_CHECK        — status check context for CVE scan (default: cve-scan)"
  echo "  SECRETS_CHECK    — status check context for secret detection (default: secret-detection)"
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
fi

INSTALLATION_ID="$1"

if ! [[ "$INSTALLATION_ID" =~ ^[0-9]+$ ]]; then
  echo "[FAIL] INSTALLATION_ID must be a positive integer, got: ${INSTALLATION_ID}" >&2
  exit 1
fi

SAST_CHECK="${2:-sast}"
CVE_CHECK="${3:-cve-scan}"
SECRETS_CHECK="${4:-secret-detection}"

REPO="devinhedge/MPD-secure"
OWNER="devinhedge"
REPO_NAME="MPD-secure"

# --- Helper: check whether a Ruleset with the given name already exists ---
ruleset_exists() {
  local name="$1"
  gh api "repos/${REPO}/rulesets" --jq '.[].name' 2>/dev/null | grep -qxF "$name"
}

# --- Helper: create a Ruleset and print result ---
create_ruleset() {
  local name="$1"
  local payload="$2"
  if ruleset_exists "$name"; then
    echo "[SKIP] Ruleset already exists: ${name}"
    return
  fi
  response=$(gh api "repos/${REPO}/rulesets" \
    --method POST \
    --input - <<< "$payload")
  local id
  id=$(echo "$response" | jq -r '.id')
  echo "[CREATE] Ruleset created: ${name} (id=${id})"
}

# === Pattern 1: dev ===
create_ruleset "pipeline-dev-protection" "$(cat <<JSON
{
  "name": "pipeline-dev-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/dev"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          {"context": "${SAST_CHECK}"},
          {"context": "${CVE_CHECK}"},
          {"context": "${SECRETS_CHECK}"}
        ]
      }
    },
    {
      "type": "non_fast_forward"
    }
  ]
}
JSON
)"

# === Pattern 2: int + test-* + stage-* ===
PATTERN2_BRANCHES=(
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

for branch in "${PATTERN2_BRANCHES[@]}"; do
  create_ruleset "pipeline-${branch}-protection" "$(cat <<JSON
{
  "name": "pipeline-${branch}-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/${branch}"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "creation"},
    {"type": "update"},
    {"type": "non_fast_forward"}
  ],
  "bypass_actors": [
    {
      "actor_id": ${INSTALLATION_ID},
      "actor_type": "Integration",
      "bypass_mode": "always"
    }
  ]
}
JSON
  )"
done

# === Pattern 3: main ===
create_ruleset "pipeline-main-protection" "$(cat <<JSON
{
  "name": "pipeline-main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          {"context": "pipeline/stage-ubuntu-debian"},
          {"context": "pipeline/stage-fedora-rhel"},
          {"context": "pipeline/stage-arch"},
          {"context": "pipeline/stage-macos"},
          {"context": "pipeline/stage-windows"}
        ]
      }
    },
    {
      "type": "non_fast_forward"
    }
  ]
}
JSON
)"

echo ""
echo "Done. All 13 Rulesets applied."
