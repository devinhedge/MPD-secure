# US-006-04: Implement Platform Stage Lanes

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/15
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
  - Triggers on push to its corresponding `stage-*` branch (push performed by
    `test-{platform}.yml` via GitHub App)
  - Builds the release candidate package (final artifact; signed artifacts
    deferred to separate feature)
  - Generates a package fingerprint (checksum) for the release candidate
  - Generates GitHub-style release notes
  - Creates a platform-specific release tag via GitHub App installation token
    (e.g., `v2.3.1-ubuntu-debian`; patch version is independent per platform
    to accommodate platform-specific fixes)
  - On success, posts a named commit status check to the originating commit
    via GitHub App installation token:
    - `pipeline/stage-ubuntu-debian`
    - `pipeline/stage-fedora-rhel`
    - `pipeline/stage-arch`
    - `pipeline/stage-macos`
    - `pipeline/stage-windows`
  - Uses `actions/create-github-app-token` to generate a short-lived
    installation token from the App ID and private key stored as secrets —
    same App used for all automated pipeline promotions
- Status checks use the exact names listed in US-006-01's Ruleset
  configuration — any mismatch means `main` merge remains blocked

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Write `stage-ubuntu-debian` workflow YAML (RC `.deb` package; fingerprint;
      release notes; platform-specific tag `v*-ubuntu-debian`; post
      `pipeline/stage-ubuntu-debian` status check via App token)
- [ ] Write `stage-fedora-rhel` workflow YAML (RC `.rpm` package; fingerprint;
      release notes; platform-specific tag `v*-fedora-rhel`; post
      `pipeline/stage-fedora-rhel` status check via App token)
- [ ] Write `stage-arch` workflow YAML (RC `.pkg.tar.zst` package; fingerprint;
      release notes; platform-specific tag `v*-arch`; post
      `pipeline/stage-arch` status check via App token)
- [ ] Write `stage-macos` workflow YAML (RC Homebrew/`.pkg` package; fingerprint;
      release notes; platform-specific tag `v*-macos`; post
      `pipeline/stage-macos` status check via App token)
- [ ] Write `stage-windows` workflow YAML (RC WiX v4 installer; fingerprint;
      release notes; platform-specific tag `v*-windows`; post
      `pipeline/stage-windows` status check via App token)
- [ ] Define platform-specific versioning scheme (major.minor.patch-platform;
      patch independent per platform)
- [ ] Verify: each stage workflow triggers on push to its `stage-*` branch
- [ ] Verify: RC package artifact is produced
- [ ] Verify: package fingerprint is generated and attached to the release
- [ ] Verify: GitHub-style release notes are generated
- [ ] Verify: platform-specific release tag is created via App token
- [ ] Verify: each stage workflow posts its named status check to the
      originating commit using the exact check name from the GitHub Ruleset
- [ ] Verify: a PR to `main` shows all five `pipeline/stage-*` checks present
      and green when all five stage workflows have run
- [ ] Verify: a PR to `main` from a non-`stage-*` branch has no checks and
      cannot be merged
