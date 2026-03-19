# Design Spec: US-006-02 — Integration Gate (`int` Workflow)

**Story:** [US-006-02](../../stories/US-006-02-integration-gate-workflow.md)
**Feature:** [FEATURE-006](../../features/FEATURE-006-cicd-pipeline.md)
**Date:** 2026-03-18
**Status:** Approved

---

## Notes

The inline US-006-02 summary in `FEATURE-006-cicd-pipeline.md` previously
described a `workflow_call`/`repository_dispatch` fan-out triggered by push
to `dev`. That text has been updated to match this spec and the standalone
story file. This spec and the standalone story file are authoritative.

---

## Summary

Implement the integration gate for the MPD-secure CI/CD pipeline. This
story owns two workflow files: the promotion job appended to `dev.yml`
(App push to `int` on security gate success), and `int.yml` (full feature
build, full regression suite, and App fan-out push to all five `test-*`
branches).

---

## Implementation Approach

All promotion mechanics use the GitHub App installation token
(`actions/create-github-app-token`) — never `GITHUB_TOKEN`. Each promotion
is an explicit `git push` over HTTPS using a short-lived token generated
per workflow run. No `workflow_run` chaining: promotion steps are
conditional final jobs within each workflow, eliminating the need for
`dev-to-int.yml` and `int-to-fanout.yml` as separate files.

---

## Workflow Files

### File 1: `.github/workflows/dev.yml` (promotion job only)

US-006-02 adds a single final job to `dev.yml`. The security gate jobs are
owned by other stories. The `needs` list below must exactly match the job
IDs those stories implement:

| Job ID | Owner story |
|---|---|
| `compile` | `dev.yml` quality gate story (not yet assigned a story number; story creation is tracked in TODOS.md under "Open Story Creation (FEATURE-006)") |
| `unit-tests` | `dev.yml` quality gate story (not yet assigned a story number; story creation is tracked in TODOS.md under "Open Story Creation (FEATURE-006)") |
| `sast` | US-006-05 |
| `cve-scan` | US-006-06 |
| `secret-detection` | US-006-07 |

If any of these job IDs change during implementation, the `needs` list in
the promotion job must be updated to match. Mismatch causes the promotion
job to be silently skipped.

```
Job: promote-to-int
  needs: [compile, unit-tests, sast, cve-scan, secret-detection]
  if: success()
  # success() is scoped to the needs list above. Any future job added to
  # dev.yml must also be added to this needs list to prevent silent
  # promotion to int on partial failure.
  runs-on: ubuntu-latest

  Steps:
    1. actions/checkout
         ref: ${{ github.sha }}
       # Required: git push <url> <sha>:<ref> resolves the SHA from the
       # local git object store. Without checkout, no local repository
       # exists and git cannot resolve github.sha — the push fails with
       # "unknown revision."

    2. actions/create-github-app-token@v1
         id: token
         app-id:      ${{ secrets.PIPELINE_APP_ID }}
         private-key: ${{ secrets.PIPELINE_APP_PRIVATE_KEY }}
         repositories: ${{ github.event.repository.name }}
       # Pin to a version tag (v1 or SHA) — unpinned actions are a
       # supply chain risk. Token is scoped to this repository only.

    3. Push ${{ github.sha }} to refs/heads/int.
       TOKEN and REPO must be set as step-level environment variables so
       that the shell can reference them as ${TOKEN} and ${REPO}.
       ${{ github.sha }} is interpolated by Actions before the shell runs;
       TOKEN and REPO are shell variables set from Actions expressions in
       the step env block:
         env:
           TOKEN: ${{ steps.token.outputs.token }}
           REPO:  ${{ github.repository }}
         run: |
           git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
             ${{ github.sha }}:refs/heads/int
```

---

### File 2: `.github/workflows/int.yml`

US-006-02 owns this file entirely.

```
Trigger:
  on:
    push:
      branches:
        - int

Jobs:

  build-and-test:
    runs-on: ubuntu-latest
    Steps:
      1. actions/checkout
         # No ref override needed: for a push trigger, actions/checkout
         # defaults to github.sha (the commit that triggered the workflow).
         # ref is only required when the local object store would otherwise
         # not contain the target SHA — which is not the case here.
      2. Install Meson, Ninja, and all optional MPD dependencies
         (full feature build — all optional packages must be available
          on ubuntu-latest; see Constraints)
      3. meson setup builddir
         (full feature build — no auto_features=disabled;
          all optional dependencies resolved)
      4. ninja -C builddir
      5. meson test -C builddir --no-rebuild
         (full unit test regression suite against artifacts from step 4)

  promote-to-test-lanes:
    needs: [build-and-test]
    if: success()
    # success() is scoped to needs: [build-and-test] only — see Constraints.
    # IMPORTANT: This guard is sufficient only while push is the sole trigger.
    # If workflow_dispatch is ever added to int.yml, an additional
    # if: github.ref == 'refs/heads/int' guard MUST be added here before
    # enabling that trigger — see workflow_dispatch constraint in Constraints.
    runs-on: ubuntu-latest
    Steps:
      1. actions/checkout
           ref: ${{ github.sha }}
         # Required: git push <url> <sha>:<ref> resolves the SHA from the
         # local git object store. Without checkout, git cannot resolve
         # github.sha — the push fails with "unknown revision."

      2. actions/create-github-app-token@v1
           id: token
           app-id:      ${{ secrets.PIPELINE_APP_ID }}
           private-key: ${{ secrets.PIPELINE_APP_PRIVATE_KEY }}
           repositories: ${{ github.event.repository.name }}
         # Pin to a version tag (v1 or SHA). Token scoped to this repo only.

      3. Push ${{ github.sha }} to all five test-* branches.
         TOKEN and REPO must be set as step-level environment variables so
         that the shell can reference them as ${TOKEN} and ${REPO}.
         ${{ github.sha }} is interpolated by Actions before the shell runs;
         TOKEN and REPO are shell variables set from Actions expressions in
         the step env block:
           env:
             TOKEN: ${{ steps.token.outputs.token }}
             REPO:  ${{ github.repository }}
           run: |
             git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
               ${{ github.sha }}:refs/heads/test-ubuntu-debian
             git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
               ${{ github.sha }}:refs/heads/test-fedora-rhel
             git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
               ${{ github.sha }}:refs/heads/test-arch
             git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
               ${{ github.sha }}:refs/heads/test-macos
             git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
               ${{ github.sha }}:refs/heads/test-windows
```

Build and test run in the same job (`build-and-test`) to share the
compiled artifacts. `meson test --no-rebuild` runs against the artifacts
produced by `ninja` in the same job — no artifact upload/download required.

The same commit SHA is pushed to all five `test-*` branches. Each
platform test workflow (`test-{platform}.yml`) triggers independently on
push to its branch (US-006-03).

---

## Execution Flow

```
PR merged to dev
    │
    ▼
dev.yml runs (security gate jobs: compile, unit-tests, sast, cve-scan, secret-detection)
    │
    ├── any job fails → promote-to-int skipped; int branch unchanged
    │
    └── all jobs pass
            │
            ▼
        promote-to-int job (checkout + App token + git push SHA to int)
            │
            ▼
        int.yml triggers (on: push to int)
            │
            ├── build-and-test fails → promote-to-test-lanes skipped
            │
            └── build-and-test passes
                    │
                    ▼
                promote-to-test-lanes job
                App push: $SHA → refs/heads/test-ubuntu-debian
                App push: $SHA → refs/heads/test-fedora-rhel
                App push: $SHA → refs/heads/test-arch
                App push: $SHA → refs/heads/test-macos
                App push: $SHA → refs/heads/test-windows
                    │
                    ▼
                test-{platform}.yml triggers per branch (US-006-03)
```

---

## Constraints and Dependencies

- **US-006-01 must complete first** — `int` and all `test-*` branches must
  exist and be protected (GitHub App as sole bypass actor) before any
  promotion push can succeed.
- **`PIPELINE_APP_ID` and `PIPELINE_APP_PRIVATE_KEY` secrets must be
  stored** (by `02-store-app-secrets.sh` in US-006-01) before either
  workflow can generate an App token.
- **`needs` job IDs in the `dev.yml` promotion job are a cross-story
  contract** — see the job ID table above. Finalization of job IDs from
  US-006-05, US-006-06, US-006-07, and the `dev.yml` quality gate story
  is a blocking prerequisite before the `promote-to-int` task file is
  written.
- **Full feature build dependency availability** — `int.yml`
  `build-and-test` installs all optional MPD dependencies on
  `ubuntu-latest`. The full list of required packages must be confirmed
  against the `ubuntu-latest` image before the task file for
  `build-and-test` is written. The implementer of `build-and-test` owns
  this confirmation as the first step of that task.
- **Same SHA propagated throughout** — `github.sha` in `int.yml` is the
  SHA pushed to `int` by the `dev.yml` promotion job. All five
  `test-*` branch pushes use this same SHA, ensuring every platform test
  workflow runs against the identical commit.
- **No `workflow_run`** — the App token provides the elevated permissions
  needed for protected branch pushes; `workflow_run` is not used.
- **`success()` scope in both promotion jobs** — `if: success()` on
  `promote-to-int` is scoped to its `needs` list (the five security gate
  jobs). `if: success()` on `promote-to-test-lanes` is scoped to
  `needs: [build-and-test]`. Any future job added to either workflow must
  be added to the corresponding `needs` list or promotion will proceed
  silently on partial failure.
- **`workflow_dispatch` prohibited on `int.yml`** — the promotion job
  does not guard against triggers other than `push` to `int`. If
  `workflow_dispatch` is ever added, an `if: github.ref == 'refs/heads/int'`
  guard must be added to `promote-to-test-lanes` before the trigger is
  enabled.
- **`actions/create-github-app-token` must be SHA-pinned at implementation
  time** — the pseudo-code in this spec uses `@v1` as a placeholder, but
  the implemented workflow YAML must use a full commit SHA pin
  (e.g., `actions/create-github-app-token@<sha>`). A floating major version
  tag (`@v1`) allows the action author to push changes under the same tag
  without notice, which is a supply chain risk inconsistent with the
  zero-trust posture of this pipeline. The implementer is responsible for
  pinning to the SHA of the `@v1` release at the time of implementation and
  recording it in the workflow file.
- **App token scoped to this repository only** — both token generation
  steps must include `repositories: ${{ github.event.repository.name }}`
  to prevent the token from carrying organization-wide write permissions.
