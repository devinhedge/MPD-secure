# US-006-01: Establish Branch Topology and Protection

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/6
**Status:** Planned
**Blocked By:** FEATURE-007 (STRIDE threat model)

---

## User Story

**As a** contributor to MPD-secure,
**I want** the branch topology created with every pipeline branch protected,
**so that** no commit can reach any branch through an uncontrolled path, and
no commit can reach `main` without passing through the full pipeline.

---

## Acceptance Criteria

- Branches created: `dev`, `int`, `test-ubuntu-debian`, `test-fedora-rhel`,
  `test-arch`, `test-macos`, `test-windows`, `stage-ubuntu-debian`,
  `stage-fedora-rhel`, `stage-arch`, `stage-macos`, `stage-windows`
- `dev` protected with classic branch protection — PR required:
  - Direct push to `dev` is prohibited
  - Three required status checks on `dev` PRs: SAST, CVE scan, secret
    detection — a PR cannot be merged until all three pass
- `int` protected with classic branch protection — push restricted to the
  GitHub App only; no human or `GITHUB_TOKEN` can push directly
- `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`, `test-macos`,
  `test-windows` each protected with classic branch protection — push
  restricted to the GitHub App only
- `stage-ubuntu-debian`, `stage-fedora-rhel`, `stage-arch`, `stage-macos`,
  `stage-windows` each protected with classic branch protection — push
  restricted to the GitHub App only
- GitHub Ruleset applied to `main`:
  - Direct push prohibited for all actors including administrators
  - Five required status checks: `pipeline/stage-ubuntu-debian`,
    `pipeline/stage-fedora-rhel`, `pipeline/stage-arch`,
    `pipeline/stage-macos`, `pipeline/stage-windows`
- GitHub App created and installed on the repository:
  - App ID and private key stored as repository secrets
  - Permissions: `contents: write`, `statuses: write`, scoped to this repo
- A PR from any branch other than `stage-*` to `main` cannot be merged
  (required checks will never be present)

---

## Key Design Decisions

- **All branches protected** — every branch in the pipeline is protected; no
  commit can reach any branch through an uncontrolled path; this eliminates
  the attack surface where a compromised credential or misconfigured workflow
  could inject an unverified commit at any point in the topology
- **GitHub App over `GITHUB_TOKEN` for all automated promotions** — the App is
  the named non-human promotion actor for all lane transitions (dev→int,
  int→test-*, test-*→stage-*, and stage-* status checks); its credentials
  are independently rotatable; it appears in the audit log; short-lived
  installation tokens are generated per workflow run
- **Classic branch protection with App allowlist for `int`, `test-*`, and
  `stage-*`** — Rulesets cannot restrict pushes to a specific GitHub App
  identity (only to users or teams); classic branch protection supports the
  push restriction allowlist required to scope access to the App
- **GitHub Ruleset for `main`** — Rulesets block admin bypass; classic branch
  protection does not; `main` requires this stronger enforcement primitive
- **Required status checks as the enforcement primitive** — adding a platform
  in the future requires only adding its stage check to the required list
- **No automated promotion to `main`** — the pipeline never pushes to `main`;
  the human gate is structurally enforced, not by convention

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Create all pipeline branches in the repository
- [ ] Configure `dev` classic branch protection (PR required; SAST/CVE/secrets
      as required status checks)
- [ ] Configure `int` classic branch protection (push restricted to GitHub App)
- [ ] Configure `test-*` classic branch protection (push restricted to GitHub App)
- [ ] Configure `stage-*` classic branch protection (push restricted to GitHub App)
- [ ] Create GitHub App and install on repository; store `PIPELINE_APP_ID` and
      `PIPELINE_APP_PRIVATE_KEY` as repository secrets
- [ ] Configure GitHub Ruleset on `main` (no direct push; five required status
      checks)
- [ ] Verify: direct push to `dev` rejected; PR required; security gate checks
      enforced
- [ ] Verify: direct push to `int`, `test-*`, `stage-*` rejected as human actor
- [ ] Verify: direct push to `main` rejected for admin account
- [ ] Verify: PR from non-`stage-*` branch to `main` cannot be merged
