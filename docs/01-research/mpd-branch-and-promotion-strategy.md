---
title: MPD Fork — Branch and Promotion Strategy
description: Branch topology, automated lane promotion mechanics, and main branch protection design for the MPD fork CI/CD pipeline.
doc_type: research
author: Devin Hedge
version: 0.4.0
last_updated: 2026-03-18
status: draft
category: ci-cd
tags: [github-actions, branch-strategy, promotion, branch-protection, rulesets]
---

# MPD Fork — Branch and Promotion Strategy

## Purpose

This document defines the branch topology, automated promotion mechanics between pipeline lanes, and the branch protection strategy for the entire pipeline. Every branch in the pipeline is protected. It is a design document — no workflow YAML is produced here.

---

## Branch Topology

All five platforms follow a symmetric promotion pattern. Feature work integrates at `dev`, flows through `int` (the integration gate), fans out to per-platform test lanes, promotes to per-platform stage lanes, and converges at `main` via manual PR merge.

```
feature | chore | fix
        │
        ▼
       dev
        │
        ▼
       int  ──────────────────────────────────────────────────┐
        │                                                      │
        ├──► test-ubuntu-debian ──► stage-ubuntu-debian ──────┤
        │                                                      │
        ├──► test-fedora-rhel   ──► stage-fedora-rhel   ──────┤
        │                                                      │
        ├──► test-arch          ──► stage-arch          ──────┤
        │                                                      │
        ├──► test-macos         ──► stage-macos         ──────┤
        │                                                      │
        └──► test-windows       ──► stage-windows       ──────┤
                                                               │
                                                             main
                                                          (manual PR merge)
```

### Lane Definitions

| Lane | Stage | Platform Scope | Trigger |
|---|---|---|---|
| `dev` | development | all platforms | push from feature branches |
| `int` | integration | all platforms | push from `dev` |
| `test-ubuntu-debian` | test | Ubuntu and Debian | push from `int` |
| `test-fedora-rhel` | test | Fedora and RHEL | push from `int` |
| `test-arch` | test | Arch Linux | push from `int` |
| `test-macos` | test | macOS | push from `int` |
| `test-windows` | test | Windows | push from `int` |
| `stage-ubuntu-debian` | stage | Ubuntu and Debian | auto-promoted from `test-ubuntu-debian` |
| `stage-fedora-rhel` | stage | Fedora and RHEL | auto-promoted from `test-fedora-rhel` |
| `stage-arch` | stage | Arch Linux | auto-promoted from `test-arch` |
| `stage-macos` | stage | macOS | auto-promoted from `test-macos` |
| `stage-windows` | stage | Windows | auto-promoted from `test-windows` |
| `main` | release | all platforms | manual PR merge from all five stage lanes |

## Branch Protection Summary

Every branch in the pipeline is protected. No commit reaches any branch through an uncontrolled path.

| Branch | Protection mechanism | Authorized push actor |
|---|---|---|
| `dev` | GitHub Ruleset — PR required; 3 required status checks | Human actors via PR |
| `int` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `test-ubuntu-debian` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `test-fedora-rhel` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `test-arch` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `test-macos` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `test-windows` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `stage-ubuntu-debian` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `stage-fedora-rhel` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `stage-arch` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `stage-macos` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `stage-windows` | GitHub Ruleset — push restricted; GitHub App bypass | GitHub App only |
| `main` | GitHub Ruleset — no direct push; 5 required status checks | No direct push; PR only |

All branches use GitHub Rulesets. Rulesets support GitHub Apps as named bypass actors, enabling push-restricted branches where only the pipeline App can push. This eliminates the need for classic branch protection entirely and ensures admin bypass is blocked on every branch, not just `main`.

---

## Promotion Mechanics

### feature/* to dev (PR merge)

Feature, chore, and fix branches are merged to `dev` via pull request. The `dev` branch has branch protection requiring PR review. The three security gates (SAST, CVE scan, secret detection) are configured as required status checks on `dev` PRs — a PR cannot be merged until all three pass. Human actors perform the merge; no automated promotion is involved at this step.

### dev to int (automated promotion)

When a commit lands on `dev` (via PR merge), the `dev` workflow runs the integration build. On success, the GitHub App pushes that commit to `int`:

```
git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
  HEAD:refs/heads/int
```

The `int` branch Ruleset restricts all pushes; the GitHub App is the only bypass actor. This ensures that only commits that have passed the integration build can trigger the platform fan-out.

### int to test-* (fan-out)

When a commit lands on `int`, the `int` workflow triggers all five platform test workflows on successful completion. This is implemented as a fan-out using `workflow_call` or `repository_dispatch`. Each platform test workflow receives the same commit SHA. On completion of each test workflow, the GitHub App pushes that commit to the corresponding `test-*` branch:

```
git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
  <SHA>:refs/heads/test-<platform>
```

Each `test-*` branch Ruleset restricts all pushes; the GitHub App is the only bypass actor.

### test-* to stage-* (automated promotion)

When all jobs in a platform test workflow pass, the final job performs an automated branch promotion by pushing the commit to the corresponding stage branch. This uses a **GitHub App installation token** — not `GITHUB_TOKEN` and not a personal access token.

The promotion job generates a short-lived installation token at runtime using `actions/create-github-app-token`, then uses that token for the push:

```
git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
  HEAD:refs/heads/stage-<platform>
```

The GitHub App holds `contents: write` and `statuses: write` permissions scoped to this repository. Each `stage-*` branch Ruleset restricts all pushes; the GitHub App is the only bypass actor — enforcing that only pipeline-verified commits reach staging.

The stage workflow runs packaging jobs that produce the release-quality artifact (format determined by platform). When the stage workflow succeeds, it posts a named commit status check to that commit using the same App token — for example, `pipeline/stage-ubuntu-debian: passed`.

### stage-* to main (manual PR merge)

Promotion to `main` is not automated. The pipeline does not push to `main` under any circumstances. Instead, the stage workflows post named commit status checks. A developer opens a pull request from any `stage-*` branch to `main` and merges it manually after all five stage checks are present and green.

This is the only human gate in the pipeline. All other lane transitions are automated.

## main Branch Protection

### Required Status Checks

`main` is configured with the following required status checks, which must all pass before any PR can be merged:

- `pipeline/stage-ubuntu-debian`
- `pipeline/stage-fedora-rhel`
- `pipeline/stage-arch`
- `pipeline/stage-macos`
- `pipeline/stage-windows`

These checks are only posted by their respective stage workflows. A PR opened directly from `feature/*`, `dev`, `int`, or any `test-*` branch to `main` will never have any of these checks present, making the merge button permanently disabled for any bypass attempt.

### GitHub Ruleset

A GitHub Ruleset is applied to `main` with no bypass actors, prohibiting direct pushes for all actors including repository administrators. Combined with required status checks, the two controls together mean:

- No direct push to `main` is possible for any actor.
- No PR against `main` can be merged unless all five stage status checks are present and passing.
- The only path to `main` is through the full pipeline topology.

### What is Not Restricted

Pull requests against `main` can be opened by anyone with repository access. GitHub does not support restricting PR creation at the platform level. This is acceptable because the merge gate makes such PRs inert — they cannot be merged without satisfying all five stage checks.

## Key Design Decisions

**All branches protected.** Every branch in the pipeline is protected. No commit can reach any branch through an uncontrolled path. This eliminates the attack surface where a compromised credential or misconfigured workflow could inject an unverified commit at any point in the pipeline topology.

**GitHub App over `GITHUB_TOKEN` for all automated promotions.** A GitHub App with `contents: write` and `statuses: write` permissions scoped to this repository is the sole automated promotion actor for all lane transitions: dev→int, int→test-*, test-*→stage-*, and stage-* status checks. This provides several security properties that `GITHUB_TOKEN` cannot: the App identity appears in the audit log as a named non-human actor, its credentials (App ID + private key) are stored as repository secrets and are independently rotatable, and the App can be suspended or uninstalled without affecting any human account. Short-lived installation tokens are generated per-workflow run — no long-lived credential is ever present in the runner environment.

**`dev` uses PR-based promotion with required security gates.** The `dev` branch is the only branch where human actors participate in promotion. Feature branches are merged via PR. The three security gates (SAST, CVE scan, secret detection) are required status checks on `dev` PRs. No PR can be merged without all three passing.

**All branches use GitHub Rulesets exclusively.** GitHub Rulesets support named GitHub Apps as bypass actors. A Ruleset that restricts all pushes and lists only the pipeline GitHub App as a bypass actor is the correct mechanism for App-only branch promotion — no classic branch protection is required. This applies to `int`, all `test-*` branches, and all `stage-*` branches. Using Rulesets everywhere (rather than a mix of classic rules and Rulesets) means admin bypass is blocked on every branch in the pipeline, not just `main`, and the enforcement primitive is consistent across the entire topology.

**`main` Ruleset has no bypass actors.** The `main` Ruleset prohibits direct pushes for all actors including administrators. No bypass actor is configured — promotion to `main` is exclusively via PR merge after all five required status checks are satisfied.

**No promote-to-main job.** The pipeline does not contain a job that pushes to `main`. Keeping `main` promotion as a manual human action preserves a deliberate review point regardless of pipeline automation. This boundary is enforced structurally, not by convention.

**Status checks as the enforcement primitive.** Requiring named status checks rather than requiring a specific source branch makes the enforcement model composable. If a platform is added in the future, adding its stage status check to the required list is the only configuration change needed — no Ruleset modifications, no YAML restructuring.
