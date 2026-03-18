# US-006-07: Embed Secret Detection in the `dev` Lane

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/18
**Status:** Planned
**Blocked By:** US-006-01 (`dev` branch and protection must exist first)

---

## User Story

**As a** contributor to MPD-secure,
**I want** secret detection running on every push to `dev`,
**so that** credentials, API keys, and tokens are never committed to the
repository.

---

## Acceptance Criteria

- Secret detection tool configured (Gitleaks or equivalent)
- No Meson build step required — secret detection scans git object history
  directly and does not depend on compilation artifacts
- Scans the full commit history on first run; incremental on subsequent runs
- Any detected secret blocks the push with zero exceptions
- Suppression mechanism exists for false positives with mandatory rationale
  comment
- Secret detection check is a required status check on `dev` PRs
- Satisfies FEATURE-002 US-002-02 acceptance criterion for CI enforcement

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Select and document secret detection tool (Gitleaks or equivalent)
- [ ] Write secret detection workflow YAML triggered on push to `dev` and PRs
      targeting `dev`
- [ ] Configure full history scan on first run; incremental on subsequent runs
- [ ] Configure any-secret-blocks-push policy with zero exception default
- [ ] Implement suppression mechanism for false positives requiring mandatory
      rationale comment
- [ ] Add secret detection check as a required status check on `dev` PRs
      (US-006-01 configuration)
- [ ] Run initial full-history scan; verify zero secrets detected in current
      commit history
- [ ] Verify: a commit containing a detectable secret blocks the `dev` PR merge
- [ ] Verify: a suppressed false positive with rationale comment allows the PR
      to proceed
- [ ] Verify: `docs/security/sast-baseline.md` CI enforcement criterion from
      FEATURE-002 US-002-02 is satisfied
