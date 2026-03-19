# US-006-01: Branch Topology and Protection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 12 pipeline branches and configure 13 GitHub Rulesets via idempotent `gh` CLI scripts, with a manual GitHub App creation step in the middle.

**Architecture:** Four numbered shell scripts in `scripts/pipeline-setup/` — each with a single responsibility, safe to re-run, and executed in numeric order. A `README.md` in the same directory documents the manual GitHub App creation step (step 2) that sits between scripts 01 and 02.

**Tech Stack:** `gh` CLI (GitHub API), Bash (`set -euo pipefail`), GitHub Rulesets API (`gh api`)

**Spec:** `docs/specs/2026-03-18-us-006-01-branch-topology-protection-design.md`
**Story:** `docs/stories/US-006-01-branch-topology-protection.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `scripts/pipeline-setup/01-create-branches.sh` | Create | Creates all 12 pipeline branches from `main` HEAD; skips existing |
| `scripts/pipeline-setup/02-store-app-secrets.sh` | Create | Stores `PIPELINE_APP_ID`, `PIPELINE_APP_PRIVATE_KEY`, `PIPELINE_APP_INSTALLATION_ID` as repo secrets |
| `scripts/pipeline-setup/03-configure-rulesets.sh` | Create | Applies all 13 GitHub Rulesets; skips any that already exist |
| `scripts/pipeline-setup/04-verify.sh` | Create | Acceptance gate: verifies branches, Rulesets, and push rejection |
| `scripts/pipeline-setup/README.md` | Create | Manual GitHub App creation procedure and full execution sequence |

---

## Task 1: Create the `scripts/pipeline-setup/` directory and `01-create-branches.sh`

**Files:**
- Create: `scripts/pipeline-setup/01-create-branches.sh`

This script creates all 12 pipeline branches from `main` HEAD. It is idempotent: it checks whether each branch exists before creating it.

There are no automated tests for shell scripts in this project. Verification is manual via `04-verify.sh`. Each task ends with a commit.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p scripts/pipeline-setup
```

- [ ] **Step 2: Write `01-create-branches.sh`**

Create `scripts/pipeline-setup/01-create-branches.sh` with this exact content:

```bash
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
```

- [ ] **Step 3: Make the script executable**

```bash
chmod +x scripts/pipeline-setup/01-create-branches.sh
```

- [ ] **Step 4: Run the script to verify it executes without error**

```bash
./scripts/pipeline-setup/01-create-branches.sh
```

Expected: 12 `[CREATE]` lines (or `[SKIP]` for any branches that already exist), then `Done.`

- [ ] **Step 5: Commit**

```bash
git add scripts/pipeline-setup/01-create-branches.sh
git commit -m "feat(us-006-01): add script to create pipeline branches"
```

---

## Task 2: Write `02-store-app-secrets.sh`

**Files:**
- Create: `scripts/pipeline-setup/02-store-app-secrets.sh`

This script runs after the manual GitHub App creation step (step 2 in the execution sequence). It reads the App ID, installation ID, and private key file path from command-line arguments and stores all three as GitHub repository secrets. The private key is read from the file and never echoed to stdout.

- [ ] **Step 1: Write `02-store-app-secrets.sh`**

Create `scripts/pipeline-setup/02-store-app-secrets.sh` with this exact content:

```bash
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
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x scripts/pipeline-setup/02-store-app-secrets.sh
```

- [ ] **Step 3: Verify the usage message**

```bash
./scripts/pipeline-setup/02-store-app-secrets.sh
```

Expected: usage text printed, exits 1.

- [ ] **Step 4: Commit**

```bash
git add scripts/pipeline-setup/02-store-app-secrets.sh
git commit -m "feat(us-006-01): add script to store GitHub App secrets"
```

---

## Task 3: Write `03-configure-rulesets.sh`

**Files:**
- Create: `scripts/pipeline-setup/03-configure-rulesets.sh`

This is the most complex script. It configures all 13 Rulesets via the GitHub Rulesets API. It applies three Ruleset patterns from the spec:

- Pattern 1 (`dev`): `require_pull_request` + three required status checks + `non_fast_forward`
- Pattern 2 (`int`, `test-*`, `stage-*`): `restrict_creations` + `restrict_updates` + `non_fast_forward` + GitHub App as bypass actor
- Pattern 3 (`main`): `require_pull_request` + five stage status checks + `non_fast_forward`

The installation ID is passed as the first argument (not read from secrets — repo secrets are not readable outside an Actions runner). Status check context strings for `dev` are passed as optional arguments (defaults: `sast`, `cve-scan`, `secret-detection`).

Idempotency: before each `POST`, the script lists existing Rulesets and skips any whose name already exists.

- [ ] **Step 1: Write `03-configure-rulesets.sh`**

Create `scripts/pipeline-setup/03-configure-rulesets.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <INSTALLATION_ID> [COMPILE_CHECK] [UT_CHECK] [SAST_CHECK] [CVE_CHECK] [SECRETS_CHECK]"
  echo ""
  echo "  INSTALLATION_ID  — GitHub App installation ID"
  echo "  COMPILE_CHECK    — status check context for compile (default: compile)"
  echo "  UT_CHECK         — status check context for unit tests (default: unit-tests)"
  echo "  SAST_CHECK       — status check context for SAST (default: sast)"
  echo "  CVE_CHECK        — status check context for CVE scan (default: cve-scan)"
  echo "  SECRETS_CHECK    — status check context for secret detection (default: secret-detection)"
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
fi

INSTALLATION_ID="$1"
COMPILE_CHECK="${2:-compile}"
UT_CHECK="${3:-unit-tests}"
SAST_CHECK="${4:-sast}"
CVE_CHECK="${5:-cve-scan}"
SECRETS_CHECK="${6:-secret-detection}"

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
  id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
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
        "required_approving_review_count": 1,
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
          {"context": "${COMPILE_CHECK}"},
          {"context": "${UT_CHECK}"},
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
    {"type": "restrict_creations"},
    {"type": "restrict_updates"},
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
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x scripts/pipeline-setup/03-configure-rulesets.sh
```

- [ ] **Step 3: Verify the usage message**

```bash
./scripts/pipeline-setup/03-configure-rulesets.sh
```

Expected: usage text printed, exits 1.

- [ ] **Step 4: Commit**

```bash
git add scripts/pipeline-setup/03-configure-rulesets.sh
git commit -m "feat(us-006-01): add script to configure GitHub Rulesets"
```

---

## Task 4: Write `04-verify.sh`

**Files:**
- Create: `scripts/pipeline-setup/04-verify.sh`

This is the acceptance gate. It must exit 0 for the story to be considered done.

It verifies:
1. All 12 pipeline branches exist
2. All 13 Rulesets are present
3. Ruleset content: `dev` requires the three expected status checks; `main` requires the five `pipeline/stage-*` checks
4. Push rejection: direct push to `int`, `test-ubuntu-debian`, `stage-ubuntu-debian`, `dev` (no PR), and `main` each returns 422 or 403

Push rejection test technique: attempt `PATCH /repos/{owner}/{repo}/git/refs/heads/<branch>` with the current `main` SHA (a no-op if it would succeed). A 422 or 403 means the Ruleset blocked it. A 200 means it was not blocked — that is a `[FAIL]`.

- [ ] **Step 1: Write `04-verify.sh`**

Create `scripts/pipeline-setup/04-verify.sh` with this exact content:

```bash
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
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x scripts/pipeline-setup/04-verify.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/pipeline-setup/04-verify.sh
git commit -m "feat(us-006-01): add acceptance verification script"
```

---

## Task 5: Write `scripts/pipeline-setup/README.md`

**Files:**
- Create: `scripts/pipeline-setup/README.md`

This document is the human operator's reference. It covers prerequisites, the manual GitHub App creation step (which cannot be scripted), how to retrieve the installation ID, and the complete execution sequence with exact commands. The warning about numeric ordering is mandatory.

- [ ] **Step 1: Write `scripts/pipeline-setup/README.md`**

Create `scripts/pipeline-setup/README.md` with this exact content:

```markdown
# Pipeline Setup Scripts

Scripts to establish the branch topology and GitHub Ruleset protection for the
MPD-secure CI/CD pipeline. Run in numeric order. Step 2 is manual.

---

## Prerequisites

- `gh` CLI installed and authenticated as a repository admin for `devinhedge/MPD-secure`
- Sufficient GitHub permissions to create branches, create GitHub Apps, and manage
  repository Rulesets and secrets
- The GitHub App private key saved locally as a `.pem` file (downloaded during step 2)

---

## Step 1: Create pipeline branches

```bash
./01-create-branches.sh
```

Creates the 12 pipeline branches from `main` HEAD:
`dev`, `int`, `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`, `test-macos`,
`test-windows`, `stage-ubuntu-debian`, `stage-fedora-rhel`, `stage-arch`,
`stage-macos`, `stage-windows`

Safe to re-run — existing branches are skipped.

---

## Step 2: Create and install the GitHub App (manual — GitHub UI)

This step cannot be scripted. You must complete it before running steps 3 and 4.

### 2a. Create the App

1. Go to: https://github.com/settings/apps/new
2. Fill in the fields:
   - **GitHub App name:** `mpd-secure-pipeline`
   - **Homepage URL:** `https://github.com/devinhedge/MPD-secure`
   - **Webhook:** uncheck "Active" (no webhook needed)
3. Set **Repository permissions:**
   - **Contents:** Read and write
   - **Commit statuses:** Read and write
4. Under **Where can this GitHub App be installed?**, select **Only on this account**
5. Click **Create GitHub App**
6. Record the **App ID** shown at the top of the App settings page

### 2b. Generate a private key

On the App settings page, scroll to **Private keys** and click **Generate a private key**.
A `.pem` file downloads automatically. Save it somewhere secure — you will need the path
in step 3.

### 2c. Install the App on the repository

1. On the App settings page, click **Install App** in the left sidebar
2. Click **Install** next to your account
3. Select **Only select repositories** and choose `devinhedge/MPD-secure`
4. Click **Install**

### 2d. Retrieve the installation ID

```bash
gh api /repos/devinhedge/MPD-secure/installation --jq '.id'
```

Record this number. You will pass it to steps 3 and 4.

---

## Step 3: Store App credentials as repository secrets

```bash
./02-store-app-secrets.sh <APP_ID> <INSTALLATION_ID> <path-to-private-key.pem>
```

Example:

```bash
./02-store-app-secrets.sh 123456 78901234 ~/Downloads/mpd-secure-pipeline.2026-03-18.private-key.pem
```

Stores three repository secrets:
- `PIPELINE_APP_ID`
- `PIPELINE_APP_INSTALLATION_ID`
- `PIPELINE_APP_PRIVATE_KEY`

The private key file is read once and never written to stdout.

---

## Step 4: Configure GitHub Rulesets

```bash
./03-configure-rulesets.sh <INSTALLATION_ID>
```

Example:

```bash
./03-configure-rulesets.sh 78901234
```

Applies all 13 Rulesets. Safe to re-run — existing Rulesets are skipped.

**To update the `dev` Ruleset status check context strings** (after US-006-05/06/07
define the final workflow job names):

```bash
./03-configure-rulesets.sh <INSTALLATION_ID> <SAST_JOB_NAME> <CVE_JOB_NAME> <SECRETS_JOB_NAME>
```

The existing `pipeline-dev-protection` Ruleset will be skipped (idempotent). To force
an update, delete the Ruleset manually in the GitHub UI or via
`gh api repos/devinhedge/MPD-secure/rulesets/<id> --method DELETE`, then re-run.

---

## Step 5: Verify

```bash
./04-verify.sh
```

Verifies:
- All 12 pipeline branches exist
- All 13 Rulesets are present
- `dev` Ruleset requires the three security gate checks
- `main` Ruleset requires all five `pipeline/stage-*` checks
- Direct push to `int`, `test-ubuntu-debian`, `stage-ubuntu-debian`, `dev`, and `main`
  is rejected

Exits 0 if all checks pass. Exits 1 and prints a failure summary if any check fails.
This script must exit 0 before the story is considered done.

---

## WARNING

Scripts must be run in numeric order. Step 2 is manual and must complete before
step 3. Running `03-configure-rulesets.sh` without first completing step 2 will
fail because the installation ID argument will be unknown.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/pipeline-setup/README.md
git commit -m "docs(us-006-01): add pipeline-setup README with App creation procedure"
```

---

## Task 6: Execute the setup and verify

This task is the operational execution — not code authorship. Run after all four scripts and the README are committed.

- [ ] **Step 1: Run `01-create-branches.sh`**

```bash
./scripts/pipeline-setup/01-create-branches.sh
```

Expected: 12 `[CREATE]` or `[SKIP]` lines, then `Done.`

- [ ] **Step 2: Complete the manual GitHub App creation (README step 2)**

Follow `scripts/pipeline-setup/README.md` steps 2a–2d.
Record:
- App ID
- Installation ID (from `gh api /repos/devinhedge/MPD-secure/installation --jq '.id'`)
- Path to the downloaded `.pem` file

- [ ] **Step 3: Run `02-store-app-secrets.sh`**

```bash
./scripts/pipeline-setup/02-store-app-secrets.sh <APP_ID> <INSTALLATION_ID> <path-to-private-key.pem>
```

Expected: three `[OK]` lines, then `Done.`

- [ ] **Step 4: Run `03-configure-rulesets.sh`**

```bash
./scripts/pipeline-setup/03-configure-rulesets.sh <INSTALLATION_ID>
```

Expected: 13 `[CREATE]` or `[SKIP]` lines, then `Done.`

- [ ] **Step 5: Confirm `gh api --include` header output before running `04-verify.sh`**

The push rejection tests in `04-verify.sh` use `gh api --include` to capture the HTTP
status code from response headers. Behavior on 4xx responses varies by `gh` version.
Run this manual check first to confirm headers appear in stdout:

```bash
gh api repos/devinhedge/MPD-secure/git/refs/heads/main \
  --method PATCH \
  --field sha=0000000000000000000000000000000000000000 \
  --field force=false \
  --include
```

Expected: output includes a line starting with `HTTP/` containing a 4xx status code.
If no `HTTP/` line appears, the push rejection tests will emit false `[FAIL]` results
and the script output cannot be trusted — stop and investigate the `gh` version.

- [ ] **Step 6: Run `04-verify.sh`**

```bash
./scripts/pipeline-setup/04-verify.sh
```

Expected: all `[OK]` lines, `All checks passed.`, exits 0.

If any `[FAIL]` lines appear, diagnose and resolve before proceeding.

- [ ] **Step 7: Create the pull request**

Per CLAUDE.md, a PR is created upon completion of every user story.

```bash
gh pr create \
  --title "feat(us-006-01): establish branch topology and Ruleset protection" \
  --body "Implements US-006-01. Creates 12 pipeline branches and configures 13 GitHub Rulesets via idempotent scripts. GitHub App credentials stored as repository secrets. Verified by 04-verify.sh exiting 0.

Closes #12" \
  --base main
```
