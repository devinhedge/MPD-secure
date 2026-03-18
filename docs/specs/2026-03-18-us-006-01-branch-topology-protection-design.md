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

Scripts are numbered to match execution order. Step 2 is a manual GitHub UI
step; there is no script for it.

```
scripts/pipeline-setup/
├── 01-create-branches.sh       # creates all 12 pipeline branches
├── 02-store-app-secrets.sh     # stores App ID, private key, and installation
│                               #   ID as repo secrets (run after manual step)
├── 03-configure-rulesets.sh    # applies all 13 Rulesets via gh api
├── 04-verify.sh                # verifies branches, Rulesets, and push rejection
└── README.md                   # manual GitHub App creation procedure (step 2)
                                #   and full execution sequence with commands
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
| `main` | No bypass actors + 5 required stage status checks |

`main` already exists. Its Ruleset is configured by `03-configure-rulesets.sh`.
Total: 13 Rulesets (12 pipeline branches + `main`).

---

## Ruleset Configurations

### Pattern 1 — `dev`

`require_pull_request` enforces that changes must arrive via PR, which blocks
direct push. `restrict_creations` and `restrict_updates` are not needed here
because no automated actor needs to push to `dev` — only humans via PR. Adding
those rules would be redundant and would require a bypass actor that does not
exist for this branch.

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

Note: the status check context strings (`sast`, `cve-scan`, `secret-detection`)
must match the job names used in the workflow files defined in US-006-05,
US-006-06, and US-006-07. These names are treated as placeholders until those
stories are implemented. `03-configure-rulesets.sh` accepts them as arguments
so the Ruleset can be updated without editing the script. See Constraints.

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
STEP 1 (scripted)
  ./01-create-branches.sh
    Creates dev, int, test-*, stage-* from main HEAD.
    Skips any branch that already exists.

STEP 2 (manual — GitHub UI)
  Create and install the GitHub App.
  See scripts/pipeline-setup/README.md for the step-by-step procedure,
  required permission values, and how to retrieve the installation ID.
  Record three values before proceeding to step 3:
    App ID              → needed for PIPELINE_APP_ID
    Private key (.pem)  → needed for PIPELINE_APP_PRIVATE_KEY
    Installation ID     → needed for PIPELINE_APP_INSTALLATION_ID
  Installation ID can be retrieved after install via:
    gh api /repos/{owner}/{repo}/installation --jq '.id'

STEP 3 (scripted)
  ./02-store-app-secrets.sh <APP_ID> <INSTALLATION_ID> <path-to-private-key.pem>
    Stores three repository secrets:
      PIPELINE_APP_ID
      PIPELINE_APP_PRIVATE_KEY   (read from the .pem file; not echoed to stdout)
      PIPELINE_APP_INSTALLATION_ID
    Private key file is read once and not retained by the script.

STEP 4 (scripted)
  ./03-configure-rulesets.sh <INSTALLATION_ID> [SAST_CHECK] [CVE_CHECK] [SECRETS_CHECK]
    Receives the installation ID as an argument — GitHub repo secrets are not
    readable from outside an Actions runner and cannot be fetched by a local
    script. Remaining arguments set the dev Ruleset status check context
    strings (defaults: "sast", "cve-scan", "secret-detection").
    Applies all 13 Rulesets. Skips any Ruleset whose name already exists.

STEP 5 (scripted)
  ./04-verify.sh
    Confirms all 12 pipeline branches exist.
    Confirms all 13 Rulesets are present and correctly configured.
    Push rejection tests (using gh api with human actor token):
      [OK/FAIL]  direct push to int rejected
      [OK/FAIL]  direct push to test-ubuntu-debian rejected
      [OK/FAIL]  direct push to stage-ubuntu-debian rejected
      [OK/FAIL]  direct push to dev rejected (no PR)
      [OK/FAIL]  direct push to main rejected (admin account)
    Status check configuration:
      [OK/FAIL]  dev Ruleset requires: sast, cve-scan, secret-detection
      [OK/FAIL]  main Ruleset requires all 5 pipeline/stage-* checks
    Exits non-zero and prints a failure summary if any check fails.
```

---

## Script Conventions

- `set -euo pipefail` in every script
- Output prefixes: `[CREATE]`, `[SKIP]`, `[OK]`, `[FAIL]`
- Each `gh api` call validates the HTTP response before proceeding
- Idempotency: `GET` before `POST`; skip with `[SKIP]` if already present
- No secrets written to files or stdout; `gh secret set` reads from file or
  stdin only; private key path is passed as argument, not inlined

---

## GitHub App Requirements

| Field | Value |
|---|---|
| Name | `mpd-secure-pipeline` (or equivalent) |
| Homepage URL | repository URL |
| Permissions | `contents: write`, `statuses: write` |
| Installation scope | This repository only |
| Where to install | Only on `devinhedge/MPD-secure` |

---

## `scripts/pipeline-setup/README.md` Required Content

- Prerequisites: `gh` CLI authenticated as repo admin, App private key saved
  locally as a `.pem` file
- Step-by-step GitHub UI procedure for creating and installing the App with
  exact field values from the table above
- How to retrieve the installation ID after install
- The full execution sequence (steps 1–5) with exact commands
- Warning: scripts must be run in numeric order; step 2 is manual and must
  complete before step 3

---

## Error Handling

`04-verify.sh` is the acceptance gate. It must exit 0 before this story is
considered done. Failure output identifies which check failed and the expected
state.

Push rejection tests use `gh api PATCH /repos/{owner}/{repo}/git/refs/heads/<branch>`
with a non-App token. A `422` or `403` response confirms the Ruleset is
enforcing correctly. A `200` response is a `[FAIL]`.

---

## Constraints and Dependencies

- GitHub App creation cannot be scripted via `gh` CLI — requires GitHub UI
  (manual step 2). No script exists for this step.
- `03-configure-rulesets.sh` must run after `02-store-app-secrets.sh`. The
  installation ID is passed as a command-line argument — it cannot be read
  back from repository secrets in a local script context.
- The `dev` Ruleset status check context strings (`sast`, `cve-scan`,
  `secret-detection`) are placeholders. They must match the exact job names
  used in the workflow files from US-006-05, US-006-06, and US-006-07.
  `03-configure-rulesets.sh` accepts these as optional arguments to allow
  updating the Ruleset when the final names are confirmed without modifying
  the script. Re-running the script with correct names after FEATURE-007
  merges is the intended update path.
- `PIPELINE_APP_INSTALLATION_ID` must be stored as a repository secret
  (handled by `02-store-app-secrets.sh`) in addition to `PIPELINE_APP_ID`
  and `PIPELINE_APP_PRIVATE_KEY`. All three are required by the workflow
  files in subsequent user stories.
