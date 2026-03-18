---
title: MPD Fork — Branch and Promotion Strategy
description: Branch topology, automated lane promotion mechanics, and main branch protection design for the MPD fork CI/CD pipeline.
doc_type: research
author: Devin Hedge
version: 0.2.0
last_updated: 2026-03-18
status: draft
category: ci-cd
tags: [github-actions, branch-strategy, promotion, branch-protection, rulesets]
---

# MPD Fork — Branch and Promotion Strategy

## Purpose

This document defines the branch topology, automated promotion mechanics between pipeline lanes, and the enforcement strategy for the `main` branch. It is a design document — no workflow YAML is produced here.

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

## Promotion Mechanics

### int to test-* (fan-out)

The `int` workflow triggers all five platform test workflows on successful completion. This is implemented as a fan-out: `int` dispatches a `repository_dispatch` event (or uses `workflow_call`) to each platform test workflow in parallel. No branch push is required at this step — the test workflows operate on the same commit SHA that passed `int`.

### test-* to stage-* (automated promotion)

When all jobs in a platform test workflow pass, the final job performs an automated branch promotion by pushing the commit to the corresponding stage branch. This uses a **GitHub App installation token** — not `GITHUB_TOKEN` and not a personal access token.

The promotion job generates a short-lived installation token at runtime using `actions/create-github-app-token`, then uses that token for the push:

```
git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
  HEAD:refs/heads/stage-<platform>
```

The GitHub App holds `contents: write` and `statuses: write` permissions scoped to this repository. Because the App is the only actor with permission to push to `stage-*` branches, those branches can be protected — enforcing that only pipeline-verified commits reach staging.

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

These checks are only posted by their respective stage workflows. A PR opened directly from `feature/*`, `dev`, or `int` to `main` will never have any of these checks present, making the merge button permanently disabled for any bypass attempt.

### GitHub Ruleset

A GitHub Ruleset is applied to `main` to prohibit direct pushes for all actors including repository administrators. This closes the bypass path that classic branch protection rules leave open for admins. Combined with required status checks, the two controls together mean:

- No direct push to `main` is possible for any actor.
- No PR against `main` can be merged unless all five stage status checks are present and passing.
- The only path to `main` is through the full pipeline topology.

### What is Not Restricted

Pull requests against `main` can be opened by anyone with repository access. GitHub does not support restricting PR creation at the platform level. This is acceptable because the merge gate makes such PRs inert — they cannot be merged without satisfying all five stage checks.

The `stage-*` branches are protected. Only the GitHub App can push to them. This ensures that no commit reaches staging unless it has passed the full test lane for its platform.

## Key Design Decisions

**GitHub App over `GITHUB_TOKEN` for lane promotion.** A GitHub App with `contents: write` and `statuses: write` permissions scoped to this repository is the promotion actor. This provides several security properties that `GITHUB_TOKEN` cannot: the App identity appears in the audit log as a named non-human actor, its credentials (App ID + private key) are stored as repository secrets and are independently rotatable, and the App can be suspended or uninstalled without affecting any human account. Short-lived installation tokens are generated per-workflow run — no long-lived credential is ever present in the runner environment.

**`stage-*` branches protected.** Because the GitHub App is the promotion actor, `stage-*` branches can be protected with a push restriction allowing only the App. This closes the path where any actor with `contents: write` access could push directly to staging. The protection on `stage-*` and the Ruleset on `main` together form two independent enforcement layers.

**No promote-to-main job.** The pipeline does not contain a job that pushes to `main`. Keeping `main` promotion as a manual human action preserves a deliberate review point regardless of pipeline automation. This boundary is enforced structurally, not by convention.

**Status checks as the enforcement primitive.** Requiring named status checks rather than requiring a specific source branch makes the enforcement model composable. If a platform is added in the future, adding its stage status check to the required list is the only configuration change needed — no Ruleset modifications, no YAML restructuring.
