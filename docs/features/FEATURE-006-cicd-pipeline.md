# FEATURE-006: Add CI/CD Pipeline with Security Gates

**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/6
**EPIC:** #1 MPD-secure Zero-Trust Network Security
**Blocked By:** FEATURE-007 (threat model must exist before security gates are scoped)
**Status:** Planned

## What the User Experiences

A contributor to MPD-secure pushes a feature branch and the pipeline does the
rest. Code flows automatically from development through integration, fans out
to five platform-specific test and staging lanes, and arrives at `main` only
after all five platforms have passed. Security gates embedded in the pipeline
catch vulnerabilities, leaked secrets, and known CVEs before they ever reach
`main`. No human touches the merge button until the entire pipeline is green.

## Zero-Trust Alignment

A zero-trust codebase is only as trustworthy as its delivery pipeline. Code
that passes security review can be undermined by an unscanned dependency, a
leaked credential in a workflow, or a packaging artifact built from an
unverified commit. This feature makes the pipeline itself a zero-trust
enforcement layer: every commit is verified, scanned, and promoted only on
evidence of passing — never on assumption.

## Scope

This feature covers the complete CI/CD pipeline for MPD-secure:

1. **Branch topology and protection** — the lane structure that enforces
   promotion order and prevents bypasses to `main`
2. **Platform packaging lanes** — per-platform build, test, and staging
   workflows producing native artifacts for all five target platforms
3. **Promotion mechanics** — automated lane transitions using `GITHUB_TOKEN`;
   single human gate at `main`
4. **Security gates** — SAST, CVE scanning, and secret detection embedded as
   required checks in the `dev` and `int` lanes

### Target Platforms

| Platform | Package Format | Runner |
|---|---|---|
| Ubuntu / Debian | `.deb` | `ubuntu-latest` (GitHub-hosted) |
| Fedora / RHEL | `.rpm` | Docker (`fedora`) on `ubuntu-latest` |
| Arch Linux | `PKGBUILD` / `.pkg.tar.zst` | Docker (`archlinux`) on `ubuntu-latest` |
| macOS | Homebrew formula / `.pkg` | `macos-latest` (GitHub-hosted) |
| Windows | WiX v4 installer | `windows-latest` (GitHub-hosted) |

### Branch Topology

```
feature | chore | fix
        │
        ▼
       dev  ◄── security gates (SAST, CVE, secrets) run here
        │
        ▼
       int  ◄── integration gate; fans out to platform lanes
        │
        ├──► test-ubuntu-debian ──► stage-ubuntu-debian ──┐
        │                                                  │
        ├──► test-fedora-rhel   ──► stage-fedora-rhel   ──┤
        │                                                  │
        ├──► test-arch          ──► stage-arch           ──┤
        │                                                  │
        ├──► test-macos         ──► stage-macos          ──┤
        │                                                  │
        └──► test-windows       ──► stage-windows        ──┘
                                                           │
                                                          main
                                                     (manual PR merge;
                                                      all 5 stage checks required)
```

### Out of Scope

- Signing infrastructure (binaries, packages) — separate feature
- Official distributor submission (Debian NEW queue, Homebrew core, etc.)
- Release artifact hosting / distribution CDN

---

## User Stories

### US-006-01: Establish Branch Topology and Protection

**As a** contributor to MPD-secure,
**I want** the branch topology created and `main` protected by a GitHub Ruleset,
**so that** no commit can reach `main` without passing through the full pipeline.

**Acceptance Criteria:**

- Branches created: `dev`, `int`, `test-ubuntu-debian`, `test-fedora-rhel`,
  `test-arch`, `test-macos`, `test-windows`, `stage-ubuntu-debian`,
  `stage-fedora-rhel`, `stage-arch`, `stage-macos`, `stage-windows`
- GitHub Ruleset applied to `main`:
  - Direct push prohibited for all actors including administrators
  - Five required status checks: `pipeline/stage-ubuntu-debian`,
    `pipeline/stage-fedora-rhel`, `pipeline/stage-arch`,
    `pipeline/stage-macos`, `pipeline/stage-windows`
- `stage-*` branches intentionally left unprotected (allows `GITHUB_TOKEN`
  promotion without a PAT)
- A PR from any branch other than `stage-*` to `main` cannot be merged
  (required checks will never be present)

**Key Design Decisions:**

- GitHub Ruleset over classic branch protection — Rulesets block admin bypass;
  classic branch protection does not
- Required status checks as the enforcement primitive — adding a platform in
  the future requires only adding its stage check to the required list
- No automated promotion to `main` — the pipeline never pushes to `main`;
  the human gate is structurally enforced, not by convention

---

### US-006-02: Implement Integration Gate (`int` workflow)

**As a** contributor to MPD-secure,
**I want** an `int` workflow that runs on push to `dev` and fans out to all
five platform test lanes,
**so that** integration failures are caught before any platform-specific work
begins.

**Acceptance Criteria:**

- Workflow triggers on push to `dev`
- Builds MPD-secure using Meson on a generic runner (validates build system
  correctness independent of platform packaging)
- On success, dispatches all five platform test workflows in parallel using
  `workflow_call` or `repository_dispatch`
- All five fan-out dispatches use the same commit SHA that passed `int`
- No branch push to `int` is required — the test workflows operate on the
  commit SHA directly

---

### US-006-03: Implement Platform Test Lanes

**As a** contributor to MPD-secure,
**I want** per-platform test workflows that build and validate the
platform-native package,
**so that** packaging regressions are caught before artifacts reach staging.

**Acceptance Criteria:**

- Five test workflows: `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`,
  `test-macos`, `test-windows`
- Each workflow:
  - Runs on the correct runner (see platform table in Scope section)
  - Builds MPD-secure with Meson for the target platform
  - Produces the platform-native package artifact (`.deb`, `.rpm`,
    `.pkg.tar.zst`, Homebrew formula, WiX installer)
  - Runs the platform's package validation tooling (e.g., `lintian` for
    `.deb`, `rpmlint` for `.rpm`)
  - On all jobs passing, promotes the commit to the corresponding `stage-*`
    branch via:
    ```
    git push origin HEAD:refs/heads/stage-<platform>
    ```
  - Uses `GITHUB_TOKEN` with `contents: write` — no PAT required
- Arch Linux: uses `archlinux` Docker container image on `ubuntu-latest` host
- Fedora/RHEL: uses `fedora` Docker container image on `ubuntu-latest` host

---

### US-006-04: Implement Platform Stage Lanes

**As a** contributor to MPD-secure,
**I want** per-platform stage workflows that run final packaging jobs and post
named commit status checks,
**so that** `main` branch protection can verify all five platforms are ready
before any PR is merged.

**Acceptance Criteria:**

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
  - Uses `GITHUB_TOKEN` with `statuses: write` permission
- Status checks use the exact names listed in US-006-01's Ruleset
  configuration — any mismatch means `main` merge remains blocked

---

### US-006-05: Embed SAST in the `dev` Lane

**As a** contributor to MPD-secure,
**I want** static analysis (SAST) running on every push to `dev`,
**so that** code-level vulnerabilities from the STRIDE vulnerability catalog
are caught before integration.

**Acceptance Criteria:**

- SAST tool selected and configured for C++ codebase (CodeQL or equivalent)
- Runs on every push to `dev` and on every PR targeting `dev`
- All findings reported at Critical and High severity block the push
- Findings at Medium and Low are reported but non-blocking
- Baseline report stored at `docs/security/sast-baseline.md`
  (see FEATURE-002 US-002-01)
- SAST check is a required status check on `dev` PRs

---

### US-006-06: Embed CVE Scanning in the `dev` Lane

**As a** contributor to MPD-secure,
**I want** dependency CVE scanning on every push to `dev`,
**so that** known vulnerabilities in third-party libraries are surfaced before
they reach integration or `main`.

**Acceptance Criteria:**

- CVE scanner configured for C++ dependencies (OSV-Scanner, Grype, or
  equivalent)
- Scans the full dependency graph including Meson subprojects
- Critical and High CVEs block the push
- Medium and Low CVEs produce a report but are non-blocking
- CVE scan results posted as a check on the PR

---

### US-006-07: Embed Secret Detection in the `dev` Lane

**As a** contributor to MPD-secure,
**I want** secret detection running on every push to `dev`,
**so that** credentials, API keys, and tokens are never committed to the
repository.

**Acceptance Criteria:**

- Secret detection tool configured (Gitleaks or equivalent)
- Scans the full commit history on first run; incremental on subsequent runs
- Any detected secret blocks the push with zero exceptions
- Suppression mechanism exists for false positives with mandatory rationale
  comment
- Secret detection check is a required status check on `dev` PRs
- Satisfies FEATURE-002 US-002-02 acceptance criterion for CI enforcement

---

## Definition of Ready

- FEATURE-007 (STRIDE threat model) merged — provides the vulnerability
  catalog that informs SAST baseline and CVE scope
- SAST tool selected and agreed upon (see FEATURE-002 US-002-01)
- GitHub Actions available on the repository (confirmed)
- All five target platforms confirmed (see research: `docs/01-research/mpd-packaging-context.md`)

## Definition of Done

- All branches from US-006-01 exist in the repository
- GitHub Ruleset on `main` in place and tested (attempt a direct push from
  an admin account — it must be rejected)
- `int` workflow triggers on push to `dev` and successfully fans out
- All five platform test workflows produce their native package artifact
- All five platform stage workflows post their named commit status checks
- A PR from a non-`stage-*` branch to `main` cannot be merged
  (merge button disabled — required checks absent)
- SAST, CVE scan, and secret detection run on every push to `dev`
- Critical/High SAST and CVE findings block the push
- Zero secrets detected in full commit history scan
- `docs/security/sast-baseline.md` committed
- This feature's merge to `main` is the first PR to pass through its own
  pipeline end-to-end

## Research References

- `docs/01-research/mpd-branch-and-promotion-strategy.md` — branch topology,
  promotion mechanics, and `main` branch protection design
- `docs/01-research/mpd-packaging-context.md` — platform targets, runner
  strategy, resolved decisions, and constraints
