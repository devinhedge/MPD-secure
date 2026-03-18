#!/usr/bin/env bash
set -euo pipefail

REPO="devinhedge/MPD-secure"
FAILED=0

pass() { echo "[OK]   $1"; }
fail() { echo "[FAIL] $1"; FAILED=$((FAILED + 1)); }

# === 1. Verify branches ===
echo "=== Branches ==="
EXPECTED_BRANCHES=(
  dev int
  test-ubuntu-debian test-fedora-rhel test-arch test-macos test-windows
  stage-ubuntu-debian stage-fedora-rhel stage-arch stage-macos stage-windows
)

for branch in "${EXPECTED_BRANCHES[@]}"; do
  sha=$(gh api "repos/${REPO}/git/ref/heads/${branch}" --jq '.object.sha' 2>/dev/null || echo "")
  if [ -n "$sha" ]; then
    pass "Branch exists: ${branch}"
  else
    fail "Branch missing: ${branch}"
  fi
done

# === 2. Verify Rulesets exist ===
echo ""
echo "=== Rulesets ==="
EXPECTED_RULESETS=(
  pipeline-dev-protection
  pipeline-int-protection
  pipeline-test-ubuntu-debian-protection
  pipeline-test-fedora-rhel-protection
  pipeline-test-arch-protection
  pipeline-test-macos-protection
  pipeline-test-windows-protection
  pipeline-stage-ubuntu-debian-protection
  pipeline-stage-fedora-rhel-protection
  pipeline-stage-arch-protection
  pipeline-stage-macos-protection
  pipeline-stage-windows-protection
  pipeline-main-protection
)

EXISTING_RULESETS=$(gh api "repos/${REPO}/rulesets" --jq '.[].name' 2>/dev/null || echo "")

for name in "${EXPECTED_RULESETS[@]}"; do
  if echo "$EXISTING_RULESETS" | grep -qxF "$name"; then
    pass "Ruleset exists: ${name}"
  else
    fail "Ruleset missing: ${name}"
  fi
done

# === 3. Verify dev Ruleset status check contexts ===
echo ""
echo "=== dev Ruleset status checks ==="
DEV_RULESET_ID=$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="pipeline-dev-protection") | .id' 2>/dev/null || echo "")
if [ -n "$DEV_RULESET_ID" ]; then
  DEV_CHECKS=$(gh api "repos/${REPO}/rulesets/${DEV_RULESET_ID}" \
    --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null || echo "")
  for check in sast cve-scan secret-detection; do
    if echo "$DEV_CHECKS" | grep -qxF "$check"; then
      pass "dev Ruleset requires check: ${check}"
    else
      fail "dev Ruleset missing check: ${check}"
    fi
  done
else
  fail "Cannot inspect dev Ruleset — not found"
fi

# === 4. Verify main Ruleset status check contexts ===
echo ""
echo "=== main Ruleset status checks ==="
MAIN_RULESET_ID=$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="pipeline-main-protection") | .id' 2>/dev/null || echo "")
if [ -n "$MAIN_RULESET_ID" ]; then
  MAIN_CHECKS=$(gh api "repos/${REPO}/rulesets/${MAIN_RULESET_ID}" \
    --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null || echo "")
  for check in "pipeline/stage-ubuntu-debian" "pipeline/stage-fedora-rhel" "pipeline/stage-arch" "pipeline/stage-macos" "pipeline/stage-windows"; do
    if echo "$MAIN_CHECKS" | grep -qxF "$check"; then
      pass "main Ruleset requires check: ${check}"
    else
      fail "main Ruleset missing check: ${check}"
    fi
  done
else
  fail "Cannot inspect main Ruleset — not found"
fi

# === 5. Push rejection tests ===
echo ""
echo "=== Push rejection ==="
MAIN_SHA=$(gh api "repos/${REPO}/git/ref/heads/main" --jq '.object.sha')

test_push_rejected() {
  local branch="$1"
  local label="$2"
  local output
  local http_code
  # gh api does not support curl's -w/-o flags; use --include to capture
  # response headers and parse the HTTP status line from them.
  output=$(gh api "repos/${REPO}/git/refs/heads/${branch}" \
    --method PATCH \
    --field sha="${MAIN_SHA}" \
    --field force=false \
    --include 2>/dev/null || true)
  http_code=$(printf '%s' "$output" | grep -m1 '^HTTP' | awk '{print $2}')
  if [[ "$http_code" == "422" || "$http_code" == "403" ]]; then
    pass "Push rejected (${http_code}): ${label}"
  else
    fail "Push NOT rejected (${http_code:-000}): ${label} — Ruleset not enforcing"
  fi
}

test_push_rejected "int"                  "direct push to int"
test_push_rejected "test-ubuntu-debian"   "direct push to test-ubuntu-debian"
test_push_rejected "stage-ubuntu-debian"  "direct push to stage-ubuntu-debian"
test_push_rejected "dev"                  "direct push to dev (no PR)"
test_push_rejected "main"                 "direct push to main (admin)"

# === 6. Verify non-stage PR to main cannot be merged ===
# A PR from any non-stage-* branch to main can never be merged because the
# five pipeline/stage-* required status checks can only be posted by stage-*
# workflows. This is structural: verify it by confirming that main requires
# all five pipeline/stage-* checks AND that no other bypass actor exists.
echo ""
echo "=== Non-stage PR to main blocked (structural) ==="
if [ -n "$MAIN_RULESET_ID" ]; then
  bypass_count=$(gh api "repos/${REPO}/rulesets/${MAIN_RULESET_ID}" \
    --jq '.bypass_actors | length' 2>/dev/null || echo "-1")
  if [ "$bypass_count" -eq 0 ]; then
    pass "main Ruleset has no bypass actors — no actor can skip required checks"
  else
    fail "main Ruleset has ${bypass_count} bypass actor(s) — required checks can be bypassed"
  fi
  # Confirm the check count matches expected 5
  check_count=$(gh api "repos/${REPO}/rulesets/${MAIN_RULESET_ID}" \
    --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | length' 2>/dev/null || echo "0")
  if [ "$check_count" -eq 5 ]; then
    pass "main Ruleset requires exactly 5 status checks — non-stage PRs will never satisfy them"
  else
    fail "main Ruleset requires ${check_count} status check(s), expected 5"
  fi
else
  fail "Cannot verify non-stage PR gate — main Ruleset not found"
fi

# === Summary ===
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "${FAILED} check(s) FAILED. Review [FAIL] lines above."
  exit 1
fi
