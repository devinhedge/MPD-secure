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
3. **Promotion mechanics** — automated lane transitions via GitHub App
   installation tokens; single human gate at `main`
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
**I want** the branch topology created with every pipeline branch protected,
**so that** no commit can reach any branch through an uncontrolled path, and
no commit can reach `main` without passing through the full pipeline.

**Acceptance Criteria:**

- Branches created: `dev`, `int`, `test-ubuntu-debian`, `test-fedora-rhel`,
  `test-arch`, `test-macos`, `test-windows`, `stage-ubuntu-debian`,
  `stage-fedora-rhel`, `stage-arch`, `stage-macos`, `stage-windows`
- `dev` protected with GitHub Ruleset — PR required:
  - Direct push to `dev` is prohibited
  - At least one approving review required before merge
  - Five required status checks on `dev` PRs: constrained compile, full unit
    test suite, SAST, CVE scan, secret detection — a PR cannot be merged
    until all five pass
- `int` protected with GitHub Ruleset — push restricted; GitHub App is the
  only bypass actor; no human or `GITHUB_TOKEN` can push directly
- `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`, `test-macos`,
  `test-windows` each protected with GitHub Ruleset — push restricted;
  GitHub App is the only bypass actor
- `stage-ubuntu-debian`, `stage-fedora-rhel`, `stage-arch`, `stage-macos`,
  `stage-windows` each protected with GitHub Ruleset — push restricted;
  GitHub App is the only bypass actor
- GitHub Ruleset applied to `main`:
  - Direct push prohibited for all actors including administrators; no bypass
    actors configured
  - Five required status checks: `pipeline/stage-ubuntu-debian`,
    `pipeline/stage-fedora-rhel`, `pipeline/stage-arch`,
    `pipeline/stage-macos`, `pipeline/stage-windows`
- GitHub App created and installed on the repository:
  - App ID and private key stored as repository secrets
  - Permissions: `contents: write`, `statuses: write`, scoped to this repo
- A PR from any branch other than `stage-*` to `main` cannot be merged
  (required checks will never be present)

**Key Design Decisions:**

- All branches protected — every branch in the pipeline is protected; no
  commit can reach any branch through an uncontrolled path; this eliminates
  the attack surface where a compromised credential or misconfigured workflow
  could inject an unverified commit at any point in the topology
- GitHub App over `GITHUB_TOKEN` for all automated promotions — the App is
  the named non-human promotion actor for all lane transitions (dev→int,
  int→test-*, test-*→stage-*, and stage-* status checks); its credentials
  are independently rotatable; it appears in the audit log; short-lived
  installation tokens are generated per workflow run
- GitHub Rulesets exclusively for all branches — Rulesets support GitHub Apps
  as named bypass actors; a Ruleset that restricts all pushes with only the
  pipeline App as bypass actor is the correct mechanism for App-only branch
  promotion; using Rulesets everywhere blocks admin bypass on every branch,
  not just `main`
- `main` Ruleset has no bypass actors — direct push is prohibited for all
  actors including administrators; promotion to `main` is exclusively via PR
  merge after all five required status checks are satisfied
- Required status checks as the enforcement primitive — adding a platform in
  the future requires only adding its stage check to the required list
- No automated promotion to `main` — the pipeline never pushes to `main`;
  the human gate is structurally enforced, not by convention

---

### US-006-02: Implement Integration Gate (`int` workflow)

**As a** contributor to MPD-secure,
**I want** the `dev.yml` workflow to promote passing commits to `int`, and
`int.yml` to run a full build and regression suite before fanning out to all
five platform test lanes,
**so that** integration failures are caught before any platform-specific work
begins.

**Acceptance Criteria:**

- `dev.yml` includes a final promotion job that runs only when all five
  security gate jobs pass (`compile`, `unit-tests`, `sast`, `cve-scan`,
  `secret-detection`); the GitHub App pushes the commit to `int` using a
  short-lived installation token generated via `actions/create-github-app-token`:
  ```
  git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
    ${{ github.sha }}:refs/heads/int
  ```
- `int.yml` triggers on push to the `int` branch
- `int.yml` builds MPD-secure using Meson with all features enabled
  (full feature build — no `auto_features=disabled`)
- `int.yml` runs the full unit test regression suite
- On all `int.yml` jobs passing, a promotion job uses the GitHub App to push
  the same commit SHA to all five `test-*` branches: `test-ubuntu-debian`,
  `test-fedora-rhel`, `test-arch`, `test-macos`, `test-windows`
- All five `test-*` branch pushes use the identical commit SHA that passed
  the integration build and regression suite
- A failed `dev.yml` security gate job prevents promotion to `int`
- A failed `int.yml` build or regression job prevents fan-out to any
  `test-*` branch

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
  - On all jobs passing, promotes the commit to the corresponding `test-*`
    branch via a GitHub App installation token:
    ```
    git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
      <SHA>:refs/heads/test-<platform>
    ```
  - On all jobs passing, promotes the commit to the corresponding `stage-*`
    branch via a GitHub App installation token:
    ```
    git push https://x-access-token:${APP_TOKEN}@github.com/<owner>/<repo>.git \
      HEAD:refs/heads/stage-<platform>
    ```
  - Uses `actions/create-github-app-token` to generate a short-lived
    installation token from the App ID and private key stored as secrets
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
  - Uses the GitHub App installation token (same App used for promotion) to
    post status checks — token generated via `actions/create-github-app-token`
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
- GitHub App created and installed on the repository with `contents: write`
  and `statuses: write` permissions; App ID and private key stored as
  repository secrets (`PIPELINE_APP_ID`, `PIPELINE_APP_PRIVATE_KEY`)
- All pipeline branches created and branch protection configured before
  workflow implementation begins: `dev` (PR required + security gate checks),
  `int` (App push only), all `test-*` branches (App push only), all
  `stage-*` branches (App push only), `main` (GitHub Ruleset)

## Definition of Done

- GitHub App created, installed, and secrets stored in the repository
- All branches from US-006-01 exist in the repository
- `dev` branch protection verified — PR required; a direct push as a human
  actor must be rejected; SAST, CVE scan, and secret detection checks are
  required on `dev` PRs
- `int` branch protected — only the GitHub App can push to it
  (attempt a direct push as a human actor — it must be rejected)
- All `test-*` branches protected — only the GitHub App can push to them
  (attempt a direct push as a human actor — it must be rejected)
- `stage-*` branches protected — only the GitHub App can push to them
  (attempt a direct push as a human actor — it must be rejected)
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
  all-branch protection design, promotion mechanics for every lane transition,
  and `main` GitHub Ruleset design
- `docs/01-research/mpd-packaging-context.md` — platform targets, runner
  strategy, resolved decisions, and constraints
- `docs/01-research/mpd-cicd-pipeline.drawio` — visual diagram of the full
  pipeline topology with branch protection annotations
