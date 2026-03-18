# US-006-03: Implement Platform Test Lanes

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/6
**Status:** Planned
**Blocked By:** US-006-01 (branches and protection must exist first),
               US-006-02 (fan-out dispatch comes from `int` workflow)

---

## User Story

**As a** contributor to MPD-secure,
**I want** per-platform test workflows that build and validate the
platform-native package,
**so that** packaging regressions are caught before artifacts reach staging.

---

## Acceptance Criteria

- Five test workflows: `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`,
  `test-macos`, `test-windows`
- Each workflow:
  - Runs on the correct runner (see platform table below)
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

### Platform Runner Reference

| Platform | Package Format | Runner |
|---|---|---|
| Ubuntu / Debian | `.deb` | `ubuntu-latest` (GitHub-hosted) |
| Fedora / RHEL | `.rpm` | Docker (`fedora`) on `ubuntu-latest` |
| Arch Linux | `PKGBUILD` / `.pkg.tar.zst` | Docker (`archlinux`) on `ubuntu-latest` |
| macOS | Homebrew formula / `.pkg` | `macos-latest` (GitHub-hosted) |
| Windows | WiX v4 installer | `windows-latest` (GitHub-hosted) |

---

## Tasks

_Task files live in `docs/09-tasks/`. Create one task file per discrete
implementation step following the TASK_STANDARD._

- [ ] Write `test-ubuntu-debian` workflow YAML (`.deb` build, `lintian`,
      App push to `test-ubuntu-debian` and `stage-ubuntu-debian`)
- [ ] Write `test-fedora-rhel` workflow YAML (`.rpm` build in `fedora` container,
      `rpmlint`, App push to `test-fedora-rhel` and `stage-fedora-rhel`)
- [ ] Write `test-arch` workflow YAML (`PKGBUILD`/`.pkg.tar.zst` in `archlinux`
      container, `namcap`, App push to `test-arch` and `stage-arch`)
- [ ] Write `test-macos` workflow YAML (Homebrew formula build,
      App push to `test-macos` and `stage-macos`)
- [ ] Write `test-windows` workflow YAML (WiX v4 installer build,
      App push to `test-windows` and `stage-windows`)
- [ ] Verify: each workflow produces the correct native artifact
- [ ] Verify: package validation tooling runs and blocks on failure
- [ ] Verify: failed packaging job prevents promotion to `test-*` and `stage-*`
- [ ] Verify: `test-*` branch receives the commit after test jobs pass
- [ ] Verify: `stage-*` branch receives the commit after test jobs pass
