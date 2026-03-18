# US-006-05: Embed SAST in the `dev` Lane

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/6
**Status:** Planned
**Blocked By:** FEATURE-007 (STRIDE threat model provides the vulnerability
               catalog that informs SAST baseline and rule scope),
               US-006-01 (`dev` branch and protection must exist first)

---

## User Story

**As a** contributor to MPD-secure,
**I want** static analysis (SAST) running on every push to `dev`,
**so that** code-level vulnerabilities from the STRIDE vulnerability catalog
are caught before integration.

---

## Acceptance Criteria

- SAST tool selected and configured for C++ codebase (CodeQL or equivalent)
- Runs on every push to `dev` and on every PR targeting `dev`
- All findings reported at Critical and High severity block the push
- Findings at Medium and Low are reported but non-blocking
- Baseline report stored at `docs/security/sast-baseline.md`
  (see FEATURE-002 US-002-01)
- SAST check is a required status check on `dev` PRs

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Select and document SAST tool choice (CodeQL or equivalent) for C++
- [ ] Write SAST workflow YAML triggered on push to `dev` and PRs targeting
      `dev`
- [ ] Configure severity thresholds: Critical/High block; Medium/Low report only
- [ ] Run initial SAST scan; commit baseline report to
      `docs/security/sast-baseline.md`
- [ ] Add SAST check as a required status check on `dev` PRs (US-006-01
      configuration)
- [ ] Verify: Critical/High finding on `dev` PR blocks merge
- [ ] Verify: Medium/Low finding appears in report but does not block merge
- [ ] Verify: `docs/security/sast-baseline.md` committed and current
