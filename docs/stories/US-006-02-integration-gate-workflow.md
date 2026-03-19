# US-006-02: Implement Integration Gate (`int` workflow)

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/13
**Status:** Planned
**Blocked By:** US-006-01 (branches and protection must exist first)

---

## User Story

**As a** contributor to MPD-secure,
**I want** the `dev.yml` workflow to promote passing commits to `int`, and
`int.yml` to run a full build and regression suite before fanning out to all
five platform test lanes,
**so that** integration failures are caught before any platform-specific work
begins.

---

## Acceptance Criteria

- `dev.yml` includes a final promotion job that runs only when all security
  gate jobs pass (`compile`, `unit-tests`, `sast`, `cve-scan`,
  `secret-detection`); the GitHub App pushes the commit to `int` using a
  short-lived installation token generated via `actions/create-github-app-token`:
  ```
  git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
    ${{ github.sha }}:refs/heads/int
  ```
  where `TOKEN` and `REPO` are step-level environment variables set from
  Actions expressions (`TOKEN: ${{ steps.token.outputs.token }}`,
  `REPO: ${{ github.repository }}`)
- `int.yml` triggers on push to the `int` branch
- `int.yml` builds MPD-secure using Meson with all features enabled
  (full feature build — no `auto_features=disabled`)
- `int.yml` runs the full unit test regression suite
- On all `int.yml` jobs passing, a promotion job uses the GitHub App to push
  the same commit SHA to all five `test-*` branches:
  - `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`, `test-macos`,
    `test-windows`
- All five `test-*` branch pushes use the identical commit SHA that passed
  the integration build and regression suite
- A failed `dev.yml` security gate job prevents promotion to `int`
- A failed `int.yml` build or regression job prevents fan-out to any
  `test-*` branch

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Write `dev.yml` promotion job (conditional on all security gate job IDs
      passing; App token generation; App push to `int`)
- [ ] Write `int.yml` triggered on push to `int` branch
- [ ] Implement full feature Meson build job in `int.yml`
- [ ] Implement full unit test regression suite job in `int.yml`
- [ ] Implement `int.yml` promotion job: App token generation and push of
      same commit SHA to all five `test-*` branches
- [ ] Verify: `dev.yml` promotion job runs only when all security gate jobs pass
- [ ] Verify: `dev.yml` promotion job is skipped when any security gate job fails
- [ ] Verify: `int.yml` triggers on push to `int` branch
- [ ] Verify: failed `int.yml` build prevents fan-out to `test-*` branches
- [ ] Verify: failed `int.yml` regression prevents fan-out to `test-*` branches
- [ ] Verify: all five `test-*` branches receive the same commit SHA on success
