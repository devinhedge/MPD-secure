# US-006-03: Implement Platform Test Lanes

**Feature:** [FEATURE-006](../features/FEATURE-006-cicd-pipeline.md) — Add CI/CD Pipeline with Security Gates
**GitHub Issue:** https://github.com/devinhedge/MPD-secure/issues/14
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
  - Triggers on push to its corresponding `test-*` branch (push performed by
    `int-to-fanout.yml` via GitHub App)
  - Runs on the correct runner (see platform table below)
  - Builds MPD-secure with Meson for the target platform
  - Produces the platform-native package artifact (`.deb`, `.rpm`,
    `.pkg.tar.zst`, Homebrew formula, WiX installer)
  - Runs the platform's package validation tooling (e.g., `lintian` for
    `.deb`, `rpmlint` for `.rpm`)
  - Installs the platform-native package from the built artifact
  - Runs automated functional tests against the installed binary
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
      package install, functional tests, App push to `stage-ubuntu-debian`)
- [ ] Write `test-fedora-rhel` workflow YAML (`.rpm` build in `fedora` container,
      `rpmlint`, package install, functional tests, App push to `stage-fedora-rhel`)
- [ ] Write `test-arch` workflow YAML (`PKGBUILD`/`.pkg.tar.zst` in `archlinux`
      container, `namcap`, package install, functional tests, App push to `stage-arch`)
- [ ] Write `test-macos` workflow YAML (Homebrew formula build, package install,
      functional tests, App push to `stage-macos`)
- [ ] Write `test-windows` workflow YAML (WiX v4 installer build, package install,
      functional tests, App push to `stage-windows`)
- [ ] Write automated functional test suite invoked by all platform workflows
- [ ] Verify: each workflow triggers on push to its `test-*` branch
- [ ] Verify: each workflow produces the correct native artifact
- [ ] Verify: package validation tooling runs and blocks on failure
- [ ] Verify: package installs successfully from the built artifact
- [ ] Verify: functional tests run against the installed binary and block on failure
- [ ] Verify: failed job prevents promotion to `stage-*`
- [ ] Verify: `stage-*` branch receives the commit after all jobs pass
