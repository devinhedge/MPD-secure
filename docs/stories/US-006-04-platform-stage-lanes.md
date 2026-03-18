# US-006-04: Implement Platform Stage Lanes

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/6
**Status:** Planned
**Blocked By:** US-006-01 (branches and protection must exist first),
               US-006-03 (stage workflows trigger on push to `stage-*` branches
               promoted by test lanes)

---

## User Story

**As a** contributor to MPD-secure,
**I want** per-platform stage workflows that run final packaging jobs and post
named commit status checks,
**so that** `main` branch protection can verify all five platforms are ready
before any PR is merged.

---

## Acceptance Criteria

- Five stage workflows: `stage-ubuntu-debian`, `stage-fedora-rhel`,
  `stage-arch`, `stage-macos`, `stage-windows`
- Each workflow:
  - Triggers on push to its corresponding `stage-*` branch
  - Runs final, release-quality packaging (signed artifacts deferred to
    separate feature)
  - On success, posts a named commit status check to the originating commit:
    - `pipeline/stage-ubuntu-debian`
    - `pipeline/stage-fedora-rhel`
    - `pipeline/stage-arch`
    - `pipeline/stage-macos`
    - `pipeline/stage-windows`
  - Uses the GitHub App installation token (same App used for promotion) to
    post status checks — token generated via `actions/create-github-app-token`
- Status checks use the exact names listed in US-006-01's Ruleset
  configuration — any mismatch means `main` merge remains blocked

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Write `stage-ubuntu-debian` workflow YAML (triggered on push to
      `stage-ubuntu-debian`; final `.deb` packaging; post
      `pipeline/stage-ubuntu-debian` status check via App token)
- [ ] Write `stage-fedora-rhel` workflow YAML (triggered on push to
      `stage-fedora-rhel`; final `.rpm` packaging; post
      `pipeline/stage-fedora-rhel` status check via App token)
- [ ] Write `stage-arch` workflow YAML (triggered on push to `stage-arch`;
      final `.pkg.tar.zst` packaging; post `pipeline/stage-arch` status
      check via App token)
- [ ] Write `stage-macos` workflow YAML (triggered on push to `stage-macos`;
      final Homebrew/`.pkg` packaging; post `pipeline/stage-macos` status
      check via App token)
- [ ] Write `stage-windows` workflow YAML (triggered on push to
      `stage-windows`; final WiX v4 installer packaging; post
      `pipeline/stage-windows` status check via App token)
- [ ] Verify: each stage workflow triggers on push to its `stage-*` branch
- [ ] Verify: each stage workflow posts its named status check to the
      originating commit using the exact check name from the GitHub Ruleset
- [ ] Verify: a PR to `main` shows all five `pipeline/stage-*` checks present
      and green when all five stage workflows have run
- [ ] Verify: a PR to `main` from a non-`stage-*` branch has no checks and
      cannot be merged
