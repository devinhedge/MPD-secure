# Design Spec: US-006-01 — Branch Topology and Protection

**Story:** [US-006-01](../../stories/US-006-01-branch-topology-protection.md)
**Feature:** [FEATURE-006](../../features/FEATURE-006-cicd-pipeline.md)
**Date:** 2026-03-18
**Status:** Draft

---

## Summary

Implement the branch topology and Ruleset-based protection for the MPD-secure
CI/CD pipeline. Creates 12 pipeline branches and configures 13 GitHub Rulesets
via idempotent `gh` CLI scripts. A GitHub App is created manually and its
credentials stored as repository secrets before Rulesets that require the App
as a bypass actor can be applied.

---

## Implementation Approach

Idempotent `gh` CLI scripts checked into the repository under
`scripts/pipeline-setup/`. Each script has a single responsibility and is safe
to re-run. No classic branch protection rules are used anywhere — all
protection is enforced via GitHub Rulesets.

---

## Repository Structure

```
scripts/pipeline-setup/
├── 01-create-branches.sh       # creates all 12 pipeline branches
├── 02-configure-rulesets.sh    # applies all 13 Rulesets via gh api
├── 03-store-app-secrets.sh     # stores App secrets as repo secrets
├── 04-verify.sh                # verifies branches, Rulesets, and push rejection
└── README.md                   # manual GitHub App creation procedure and
                                #   full execution sequence
```

---

## Branches Created

| Branch | Protection pattern |
|---|---|
| `dev` | PR required + 3 security gate status checks |
| `int` | Push restricted — GitHub App bypass only |
| `test-ubuntu-debian` | Push restricted — GitHub App bypass only |
| `test-fedora-rhel` | Push restricted — GitHub App bypass only |
| `test-arch` | Push restricted — GitHub App bypass only |
| `test-macos` | Push restricted — GitHub App bypass only |
| `test-windows` | Push restricted — GitHub App bypass only |
| `stage-ubuntu-debian` | Push restricted — GitHub App bypass only |
| `stage-fedora-rhel` | Push restricted — GitHub App bypass only |
| `stage-arch` | Push restricted — GitHub App bypass only |
| `stage-macos` | Push restricted — GitHub App bypass only |
| `stage-windows` | Push restricted — GitHub App bypass only |

`main` already exists. Its Ruleset is configured by `02-configure-rulesets.sh`.

---

## Ruleset Configurations

### Pattern 1 — `dev`

```
Name:    pipeline-dev-protection
Target:  branch name = "dev"
Rules:
  - require_pull_request (required_approving_review_count: 0)
  - required_status_checks:
      - context: "sast"
      - context: "cve-scan"
      - context: "secret-detection"
  - non_fast_forward: true
Bypass actors: none
```

### Pattern 2 — `int`, `test-*`, `stage-*` (one Ruleset per branch)

```
Name:    pipeline-<branch>-protection
Target:  branch name = "<branch>"
Rules:
  - restrict_creations
  - restrict_updates
  - non_fast_forward: true
Bypass actors:
  - actor_type: Integration   (GitHub App installation)
    actor_id:   <PIPELINE_APP_INSTALLATION_ID>
    bypass_mode: always
```

### Pattern 3 — `main`

```
Name:    pipeline-main-protection
Target:  branch name = "main"
Rules:
  - require_pull_request (required_approving_review_count: 0)
  - required_status_checks:
      - context: "pipeline/stage-ubuntu-debian"
      - context: "pipeline/stage-fedora-rhel"
      - context: "pipeline/stage-arch"
      - context: "pipeline/stage-macos"
      - context: "pipeline/stage-windows"
  - non_fast_forward: true
Bypass actors: none
```

---

## Execution Sequence

```
STEP 1 (scripted)    ./01-create-branches.sh
                       Creates dev, int, test-*, stage-* from main HEAD.
                       Skips any branch that already exists.

STEP 2 (manual)      GitHub UI — create and install the GitHub App.
                       Record:
                         App ID              → PIPELINE_APP_ID
                         Private key (.pem)  → PIPELINE_APP_PRIVATE_KEY
                         Installation ID     → PIPELINE_APP_INSTALLATION_ID
                       See scripts/pipeline-setup/README.md for exact
                       field values and procedure.

STEP 3 (scripted)    ./03-store-app-secrets.sh <APP_ID> <INSTALLATION_ID>
                       Reads private key from a local .pem file (path passed
                       as argument). Stores three repo secrets:
                         PIPELINE_APP_ID
                         PIPELINE_APP_PRIVATE_KEY
                         PIPELINE_APP_INSTALLATION_ID

STEP 4 (scripted)    ./02-configure-rulesets.sh
                       Reads PIPELINE_APP_INSTALLATION_ID from repo secrets.
                       Applies all 13 Rulesets. Skips any Ruleset whose name
                       already exists (idempotent).

STEP 5 (scripted)    ./04-verify.sh
                       Confirms all 12 branches exist.
                       Confirms all 13 Rulesets are present and correctly
                       configured.
                       Attempts push as human actor to int — must be rejected.
                       Prints [OK] / [FAIL] for each check.
                       Exits non-zero if any check fails.
```

---

## Script Conventions

- `set -euo pipefail` in every script
- Output prefixes: `[CREATE]`, `[SKIP]`, `[OK]`, `[FAIL]`
- Each `gh api` call validates the HTTP response before proceeding
- Idempotency: `GET` before `POST`; skip with `[SKIP]` if already present
- No secrets written to files or stdout; `gh secret set` reads from stdin or
  environment variables only

---

## GitHub App Requirements

| Field | Value |
|---|---|
| Name | `mpd-secure-pipeline` (or equivalent) |
| Homepage URL | repository URL |
| Permissions | `contents: write`, `statuses: write` |
| Installation scope | This repository only |
| Where to install | Only on `devinhedge/MPD-secure` |

The App must be installed on the repository before the installation ID is
available. The installation ID is retrieved from the App's installation page
or via `gh api /repos/{owner}/{repo}/installation --jq '.id'` after
installation.

---

## Error Handling

`04-verify.sh` is the acceptance gate. It must exit 0 before this story is
considered done. Failure output identifies which check failed and what the
expected state is.

Push rejection tests use `gh api PATCH /repos/{owner}/{repo}/git/refs/heads/<branch>`
with a non-App token. A `422` or `403` response confirms the Ruleset is
enforcing correctly. A `200` response is a `[FAIL]`.

---

## Constraints and Dependencies

- GitHub App creation cannot be scripted via `gh` CLI — requires GitHub UI
  (manual step 2)
- `02-configure-rulesets.sh` must run after step 3; the installation ID must
  be present as a repo secret before Rulesets with App bypass actors can be
  configured
- FEATURE-007 (STRIDE threat model) must be merged before the three security
  gate check names (`sast`, `cve-scan`, `secret-detection`) are finalised —
  the `dev` Ruleset status check context strings must match the names used by
  the actual workflow jobs defined in US-006-05, US-006-06, and US-006-07
