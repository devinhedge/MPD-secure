# US-006-02: Implement Integration Gate (`int` workflow)

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/13
**Status:** Planned
**Blocked By:** US-006-01 (branches and protection must exist first)

---

## User Story

**As a** contributor to MPD-secure,
**I want** an `int` workflow that runs on push to `dev` and fans out to all
five platform test lanes,
**so that** integration failures are caught before any platform-specific work
begins.

---

## Acceptance Criteria

- Workflow triggers on push to `dev`
- Builds MPD-secure using Meson on a generic runner (validates build system
  correctness independent of platform packaging)
- On success, the GitHub App pushes the commit to the `int` branch using a
  short-lived installation token generated via `actions/create-github-app-token`:
  ```
  git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
    HEAD:refs/heads/int
  ```
- On success, dispatches all five platform test workflows in parallel using
  `workflow_call` or `repository_dispatch`
- All five fan-out dispatches use the same commit SHA that passed the
  integration build

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Write `int` workflow YAML triggered on push to `dev`
- [ ] Implement Meson build step on generic runner
- [ ] Implement GitHub App token generation step using
      `actions/create-github-app-token` with `PIPELINE_APP_ID` and
      `PIPELINE_APP_PRIVATE_KEY` secrets
- [ ] Implement App push to `int` branch on build success
- [ ] Implement parallel fan-out dispatch to all five platform test workflows
      using the same commit SHA
- [ ] Verify: push to `dev` triggers `int` workflow
- [ ] Verify: failed Meson build prevents promotion to `int` and blocks fan-out
- [ ] Verify: `int` branch receives the commit only after successful build
