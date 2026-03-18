---
title: MPD Fork — Branch and Promotion Strategy
description: Branch topology, automated lane promotion mechanics, and main branch protection design for the MPD fork CI/CD pipeline.
doc_type: research
author: Devin Hedge
version: 0.1.0
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

When all jobs in a platform test workflow pass, the final job performs an automated branch promotion by pushing the commit to the corresponding stage branch. This uses the built-in `GITHUB_TOKEN` with `contents: write` permission granted at the workflow level — no personal access token or GitHub App is required.

Concretely, the promotion job executes:

```
git push origin HEAD:refs/heads/stage-<platform>
```

The `stage-*` branches are not protected, so `GITHUB_TOKEN` with `contents: write` can push to them without restriction. This triggers the stage workflow for that platform.

The stage workflow runs packaging jobs that produce the release-quality artifact (format determined by platform). When the stage workflow succeeds, it posts a named commit status check to that commit — for example, `pipeline/stage-ubuntu-debian: passed`.

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

The `stage-*` branches are intentionally left unprotected to allow `GITHUB_TOKEN` to push to them automatically. Protection on `stage-*` is not required because `main` is the authoritative gate.

## Key Design Decisions

**`GITHUB_TOKEN` over PAT for lane promotion.** Using the built-in token avoids credentials tied to a personal account and removes the operational risk of a token expiring or its owner leaving the project. `contents: write` permission is granted per-workflow, not globally, minimizing the permission surface.

**No promote-to-main job.** The pipeline does not contain a job that pushes to `main`. Keeping `main` promotion as a manual human action preserves a deliberate review point regardless of pipeline automation. This boundary is enforced structurally, not by convention.

**Stage lanes unprotected by design.** Protecting `stage-*` would require either a PAT or a GitHub App to push through branch protection. Leaving them unprotected simplifies the runner credential model. The only branch requiring protection is `main`.

**Status checks as the enforcement primitive.** Requiring named status checks rather than requiring a specific source branch makes the enforcement model composable. If a platform is added in the future, adding its stage status check to the required list is the only configuration change needed — no Ruleset modifications, no YAML restructuring.
