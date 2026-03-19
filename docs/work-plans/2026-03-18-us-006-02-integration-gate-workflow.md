# US-006-02: Integration Gate Workflow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `.github/workflows/int.yml` (full feature build, regression suite, App fan-out to all five `test-*` branches) and add the `promote-to-int` job to `.github/workflows/dev.yml` (App push to `int` on security gate success).

**Architecture:** Two workflow files. `int.yml` is fully owned by this story. The `promote-to-int` job appended to `dev.yml` depends on job IDs from five other stories — that task is blocked until all job IDs are confirmed. Build and test run in the same job (`build-and-test`) so compiled artifacts are available to `meson test --no-rebuild` on the same runner filesystem. Promotion in both workflows uses the GitHub App installation token (`actions/create-github-app-token`) with step-level `env:` variables for shell interpolation — never `GITHUB_TOKEN`.

**Tech Stack:** GitHub Actions YAML, Meson, Ninja, `actions/create-github-app-token`, `actionlint`, `gh` CLI

**Spec:** `docs/specs/2026-03-18-us-006-02-integration-gate-workflow-design.md`
**Story:** `docs/stories/US-006-02-integration-gate-workflow.md`

---

## Blocking Dependencies

**`promote-to-int` (Task 4) is blocked.** Do not write Task 4 until all of the following are confirmed:

| Blocker | Provides | Status |
|---|---|---|
| `dev.yml` quality gate story (not yet created) | `compile` job ID, `unit-tests` job ID | Blocked — story not yet assigned |
| US-006-05 | `sast` job ID | Blocked — story not yet implemented |
| US-006-06 | `cve-scan` job ID | Blocked — story not yet implemented |
| US-006-07 | `secret-detection` job ID | Blocked — story not yet implemented |
| US-006-01 | `int` branch exists and is App-push-protected | Blocked — must complete first |

**Integration verification tasks (Tasks 5-7) are blocked** until US-006-01 is complete. The `int` and `test-*` branches must exist and be protected before any push-triggered verification is possible. Additionally, Task 7 depends on Task 5 completing successfully first — Task 7 uses the SHA from a successful Task 5 run as its verification baseline.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `.github/workflows/int.yml` | Create | Integration gate: full feature build, regression suite, fan-out to all five `test-*` branches |
| `.github/workflows/dev.yml` | Modify — BLOCKED | Append `promote-to-int` job; cannot be written until all five security gate job IDs are confirmed |

---

## Pre-Work: Obtain SHA Pins

Every action reference in the new workflows must be pinned to a full commit SHA, not a floating version tag. Run these commands at the start of implementation to get the current SHAs. Record the outputs — you will substitute them for every `<ACTIONS_CHECKOUT_SHA>` and `<CREATE_APP_TOKEN_SHA>` placeholder in the tasks below.

- [ ] **Get `actions/checkout` SHA**

```bash
gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
```

Expected: a 40-character hex SHA (e.g., `11bd71901bbe5b1630ceea73d27597364c9af683`)

- [ ] **Get `actions/create-github-app-token` SHA**

```bash
gh api repos/actions/create-github-app-token/git/ref/tags/v1 --jq '.object.sha'
```

Expected: a 40-character hex SHA

Record both SHAs before writing any YAML.

---

## Task 1: Install `actionlint` and validate existing workflows

`actionlint` is a static analysis tool for GitHub Actions workflow files. It catches YAML structure errors, invalid action references, missing fields, and logic errors before you push. Install it once and use it after every workflow edit.

**Files:** No new files — verification only.

- [ ] **Step 1: Install actionlint**

On macOS:

```bash
brew install actionlint
```

On Linux (download binary):

```bash
gh release download --repo rhysd/actionlint --pattern 'actionlint_*_linux_amd64.tar.gz' --dir /tmp
```

Then extract to a location on your `$PATH`.

- [ ] **Step 2: Verify actionlint works on existing workflows**

Run from the repository root:

```bash
actionlint .github/workflows/build.yml
```

Expected: no output (no issues). If issues are reported, they are pre-existing and not part of this story's scope.

```bash
actionlint .github/workflows/build_android.yml
```

Expected: no output.

---

## Task 2: Create `int.yml` — trigger and `build-and-test` job

This task creates the `int.yml` file with the `on: push: branches: [int]` trigger and the `build-and-test` job. The `build-and-test` job performs a full feature Meson build (no `auto_features=disabled`) and runs the full unit test regression suite.

**Files:**
- Create: `.github/workflows/int.yml`

**Notes for the implementer:**

The story lists "Implement full feature Meson build job" and "Implement full unit test regression suite job" as two separate tasks. The spec requires both to run in a single job (`build-and-test`) so that `meson test --no-rebuild` can use the compiled artifacts on the same runner filesystem without an artifact upload/download. Both story tasks are therefore implemented here in one plan task.

The package list below is the full set of optional MPD dependencies available on `ubuntu-latest`. Before committing, verify that every package in the list resolves successfully with `apt-get install --dry-run`. If any package name has changed in the current `ubuntu-latest` image, substitute the correct name and document the change in the commit message.

- [ ] **Step 1: Write the stub file**

Create `.github/workflows/int.yml` with this content. Substitute the actual `<ACTIONS_CHECKOUT_SHA>` from Pre-Work.

```yaml
---
name: Integration Gate

on:
  push:
    branches:
      - int

permissions:
  contents: read

jobs:

  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@<ACTIONS_CHECKOUT_SHA>
        # No ref override needed: for a push trigger, actions/checkout defaults
        # to github.sha (the commit that triggered the workflow).

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            meson \
            ninja-build \
            g++ \
            nlohmann-json3-dev \
            libfmt-dev \
            libgtest-dev \
            libpcre2-dev \
            libsystemd-dev \
            libdbus-1-dev \
            libicu-dev \
            libcurl4-gnutls-dev \
            libavahi-client-dev \
            libmad0-dev \
            libmpg123-dev \
            libid3tag0-dev \
            libflac-dev \
            libvorbis-dev \
            libopus-dev \
            libogg-dev \
            libadplug-dev \
            libaudiofile-dev \
            libsndfile1-dev \
            libfaad-dev \
            libfluidsynth-dev \
            libgme-dev \
            libmikmod-dev \
            libmodplug-dev \
            libmpcdec-dev \
            libwavpack-dev \
            libwildmidi-dev \
            libsidplay2-dev \
            libsidutils-dev \
            libresid-builder-dev \
            libavcodec-dev \
            libavformat-dev \
            libmp3lame-dev \
            libtwolame-dev \
            libshine-dev \
            libsamplerate0-dev \
            libsoxr-dev \
            libbz2-dev \
            libcdio-paranoia-dev \
            libiso9660-dev \
            libmms-dev \
            libzzip-dev \
            libexpat-dev \
            libasound2-dev \
            libao-dev \
            libjack-jackd2-dev \
            libopenal-dev \
            libpulse-dev \
            libshout3-dev \
            libsndio-dev \
            libmpdclient-dev \
            libnfs-dev \
            libupnp-dev \
            libsqlite3-dev \
            libchromaprint-dev \
            libgcrypt20-dev

      - name: Configure (full feature build)
        run: meson setup builddir
        # Do NOT add -Dauto_features=disabled — this must be a full feature build.

      - name: Build
        run: ninja -C builddir

      - name: Unit tests
        run: meson test -C builddir --no-rebuild
```

- [ ] **Step 2: Run actionlint**

```bash
actionlint .github/workflows/int.yml
```

Expected: no output. Fix any issues before proceeding.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/int.yml
git commit -m "feat(ci): add int.yml with full feature build-and-test job"
```

---

## Task 3: Add `promote-to-test-lanes` job to `int.yml`

This task appends the `promote-to-test-lanes` job to `int.yml`. This job runs only when `build-and-test` passes and pushes the same commit SHA to all five `test-*` branches using the GitHub App installation token.

**Files:**
- Modify: `.github/workflows/int.yml`

**Notes for the implementer:**

- Substitute `<ACTIONS_CHECKOUT_SHA>` and `<CREATE_APP_TOKEN_SHA>` from Pre-Work.
- The `permissions` block at the top of the file already sets `contents: read` for `GITHUB_TOKEN`. The App token carries its own `contents: write` permissions — no change to the `permissions` block is needed.
- `${{ github.sha }}` in the `run:` block is interpolated by the Actions runner before the shell executes. `${TOKEN}` and `${REPO}` are shell variables sourced from the step-level `env:` block. Do not mix these up.

- [ ] **Step 1: Append `promote-to-test-lanes` to `int.yml`**

Add the following job block after the `build-and-test` job in `.github/workflows/int.yml`:

```yaml
  promote-to-test-lanes:
    needs: [build-and-test]
    if: success()
    # success() is scoped to needs: [build-and-test] only.
    # Any future job added to int.yml must also be added to this needs list
    # or promotion will proceed silently on partial failure.
    # IMPORTANT: This guard is sufficient only while push is the sole trigger.
    # If workflow_dispatch is ever added to int.yml, an additional
    # if: github.ref == 'refs/heads/int' guard MUST be added here before
    # enabling that trigger.
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@<ACTIONS_CHECKOUT_SHA>
        with:
          ref: ${{ github.sha }}
        # Required: git push <url> <sha>:<ref> resolves the SHA from the
        # local git object store. Without checkout, git cannot resolve
        # github.sha and the push fails with "unknown revision."

      - name: Generate App token
        id: token
        uses: actions/create-github-app-token@<CREATE_APP_TOKEN_SHA>
        with:
          app-id: ${{ secrets.PIPELINE_APP_ID }}
          private-key: ${{ secrets.PIPELINE_APP_PRIVATE_KEY }}
          repositories: ${{ github.event.repository.name }}
        # SHA-pinned (not @v1). Token scoped to this repository only.

      - name: Push SHA to all test-* branches
        env:
          TOKEN: ${{ steps.token.outputs.token }}
          REPO: ${{ github.repository }}
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

- [ ] **Step 2: Run actionlint**

```bash
actionlint .github/workflows/int.yml
```

Expected: no output. Fix any issues before proceeding.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/int.yml
git commit -m "feat(ci): add promote-to-test-lanes job to int.yml"
```

---

## Task 4: Add `promote-to-int` job to `dev.yml` — BLOCKED

**This task is blocked.** Do not begin until all five security gate job IDs are finalized and US-006-01 is complete (see Blocking Dependencies above).

When unblocked, the implementer must:

1. Confirm the exact job IDs used by `compile`, `unit-tests`, `sast`, `cve-scan`, and `secret-detection` in `dev.yml`. The `needs` list must exactly match those IDs — a mismatch causes `promote-to-int` to be silently skipped.
2. Obtain the SHA pins (see Pre-Work above) if not already recorded.
3. Append the following job to `dev.yml`. Substitute all placeholder values before writing.

```yaml
  promote-to-int:
    needs: [compile, unit-tests, sast, cve-scan, secret-detection]
    if: success()
    # success() is scoped to the needs list above. Any future job added to
    # dev.yml must also be added to this needs list to prevent silent
    # promotion to int on partial failure.
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@<ACTIONS_CHECKOUT_SHA>
        with:
          ref: ${{ github.sha }}
        # Required: git push <url> <sha>:<ref> resolves the SHA from the
        # local git object store. Without checkout, no local repository
        # exists and git cannot resolve github.sha.

      - name: Generate App token
        id: token
        uses: actions/create-github-app-token@<CREATE_APP_TOKEN_SHA>
        with:
          app-id: ${{ secrets.PIPELINE_APP_ID }}
          private-key: ${{ secrets.PIPELINE_APP_PRIVATE_KEY }}
          repositories: ${{ github.event.repository.name }}
        # SHA-pinned (not @v1). Token scoped to this repository only.

      - name: Push SHA to int
        env:
          TOKEN: ${{ steps.token.outputs.token }}
          REPO: ${{ github.repository }}
        run: |
          git push https://x-access-token:${TOKEN}@github.com/${REPO}.git \
            ${{ github.sha }}:refs/heads/int
```

After writing:

- [ ] Run `actionlint .github/workflows/dev.yml`
- [ ] `git add .github/workflows/dev.yml`
- [ ] Commit: `git commit -m "feat(ci): add promote-to-int job to dev.yml"`
- [ ] Update the job ID table in `docs/specs/2026-03-18-us-006-02-integration-gate-workflow-design.md` if any confirmed job IDs differ from the placeholders in the spec.

---

## Task 5: Verify — `int.yml` triggers on push to `int` branch — BLOCKED

**Requires:** US-006-01 complete; `int` branch exists and is App-push-protected; `PIPELINE_APP_ID` and `PIPELINE_APP_PRIVATE_KEY` secrets stored.

This verification confirms that pushing a commit to `int` causes `int.yml` to run.

- [ ] **Step 1: Push a test commit to `int` via the App token**

The `int` branch is push-protected — only the GitHub App can push to it. Use the App token generation script from US-006-01, or generate a token manually. First retrieve the installation ID:

```bash
gh api /app/installations --jq '.[0].id'
```

If the App has more than one installation, `.[0]` may return the wrong one. Use the following form to select by account login instead:

```bash
gh api /app/installations --jq '.[] | select(.account.login=="devinhedge") | .id'
```

Verify the returned ID corresponds to the `devinhedge/MPD-secure` repository before proceeding.

Then generate the token:

```bash
gh api -X POST /app/installations/<INSTALLATION_ID>/access_tokens \
  --jq '.token'
```

Then push:

```bash
git push https://x-access-token:<APP_TOKEN>@github.com/devinhedge/MPD-secure.git \
  HEAD:refs/heads/int
```

- [ ] **Step 2: Observe the Actions run**

```bash
gh run list --workflow=int.yml --limit=1
```

Expected: one run entry with status `in_progress` or `completed`.

```bash
gh run view --workflow=int.yml
```

Expected: `build-and-test` job visible.

- [ ] **Step 3: Verify `promote-to-test-lanes` ran and pushed to all five branches**

```bash
gh run view --workflow=int.yml --job=promote-to-test-lanes
```

Expected: job status `completed` (success).

Verify each `test-*` branch received the pushed SHA:

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-ubuntu-debian --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-fedora-rhel --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-arch --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-macos --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-windows --jq '.object.sha'
```

Expected: all five return the same SHA that was pushed to `int`.

---

## Task 6: Verify — failed `build-and-test` blocks fan-out — BLOCKED

**Requires:** US-006-01 complete; `int` branch exists and is protected.

This task satisfies two separate story acceptance criteria: "failed `int.yml` build prevents fan-out" and "failed `int.yml` regression prevents fan-out." Both are verified here with one test because the underlying mechanism is identical — `if: success()` on `promote-to-test-lanes` is scoped to `needs: [build-and-test]`, so any failure in `build-and-test` (whether a compile error or a test failure) causes `promote-to-test-lanes` to be skipped. A build failure and a regression failure are indistinguishable to the promotion gate.

This verification confirms that a failed `build-and-test` job causes `promote-to-test-lanes` to be skipped and the `test-*` branches are left unchanged.

- [ ] **Step 1: Record current SHA on all five test-* branches**

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-ubuntu-debian --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-fedora-rhel --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-arch --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-macos --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-windows --jq '.object.sha'
```

Record these SHAs as the baseline.

- [ ] **Step 2: Create a branch with a deliberate build failure**

On a feature branch:

```bash
git checkout -b test/int-failure-path
echo "INVALID C++ SYNTAX" >> src/Main.cxx
git add src/Main.cxx
git commit -m "test: deliberate build failure for int.yml failure path verification"
```

- [ ] **Step 3: Push to `int` via App token**

```bash
git push https://x-access-token:<APP_TOKEN>@github.com/devinhedge/MPD-secure.git \
  HEAD:refs/heads/int
```

- [ ] **Step 4: Observe that `promote-to-test-lanes` is skipped**

```bash
gh run view --workflow=int.yml
```

Expected: `build-and-test` job status `failure`. `promote-to-test-lanes` job status `skipped`.

- [ ] **Step 5: Verify test-* branches are unchanged**

Re-run the `gh api` commands from Step 1. Expected: all five branches return the same SHAs recorded in Step 1.

- [ ] **Step 6: Revert the deliberate failure**

Restore `src/Main.cxx` to its previous state and push the revert to `int` via App token:

```bash
git revert HEAD --no-edit
git push https://x-access-token:<APP_TOKEN>@github.com/devinhedge/MPD-secure.git \
  HEAD:refs/heads/int
```

---

## Task 7: Verify — all five `test-*` branches receive the same commit SHA — BLOCKED

**Requires:** US-006-01 complete; Task 5 completed successfully.

This acceptance criterion verification confirms that all five `test-*` branch pushes carry the identical SHA that passed `build-and-test`.

- [ ] **Step 1: Identify the SHA of the `int.yml` run from Task 5**

```bash
gh run list --workflow=int.yml --limit=1 --json headSha --jq '.[0].headSha'
```

Record this SHA as `VERIFIED_SHA`.

- [ ] **Step 2: Verify all five branches match `VERIFIED_SHA`**

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-ubuntu-debian --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-fedora-rhel --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-arch --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-macos --jq '.object.sha'
gh api repos/devinhedge/MPD-secure/git/ref/heads/test-windows --jq '.object.sha'
```

Expected: all five return `VERIFIED_SHA`.

- [ ] **Step 3: Mark acceptance criteria verified in the story file**

Update `docs/stories/US-006-02-integration-gate-workflow.md` — check off the completed verification tasks in the Tasks section.

---

---

## Task 8: Verify — `dev.yml` promotion runs when all security gate jobs pass — BLOCKED

**Requires:** Task 4 complete (unblocked); US-006-01 complete; all five security gate job IDs confirmed in `dev.yml`.

This verification confirms the positive path: when all five security gate jobs pass, the `promote-to-int` job runs and pushes the commit SHA to `int`.

- [ ] **Step 1: Push a commit to `dev` via PR merge**

Create a feature branch with a clean change, open a PR targeting `dev`, and merge it. This triggers `dev.yml`.

- [ ] **Step 2: Observe all five security gate jobs pass**

```bash
gh run view --workflow=dev.yml
```

Expected: `compile`, `unit-tests`, `sast`, `cve-scan`, `secret-detection` all show status `success`.

- [ ] **Step 3: Verify `promote-to-int` ran**

```bash
gh run view --workflow=dev.yml --job=promote-to-int
```

Expected: job status `completed` (success).

- [ ] **Step 4: Verify `int` branch received the promoted SHA**

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/int --jq '.object.sha'
```

Expected: the SHA matches the merged PR commit.

---

## Task 9: Verify — `dev.yml` promotion is skipped when any security gate job fails — BLOCKED

**Requires:** Task 4 complete (unblocked); US-006-01 complete; all five security gate job IDs confirmed in `dev.yml`.

This verification confirms the negative path: if any one security gate job fails, `promote-to-int` is skipped and `int` is left unchanged.

- [ ] **Step 1: Record the current SHA on the `int` branch**

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/int --jq '.object.sha'
```

Record this as `INT_BASELINE_SHA`.

- [ ] **Step 2: Push a commit that will cause one security gate job to fail**

Create a PR targeting `dev` with a change that triggers a failure in one of the security gate jobs (for example, a SAST-detectable vulnerability, a CVE-affected dependency version, or a known secret pattern for secret detection). The exact method depends on which security gate is easiest to trigger cleanly.

Merge the PR to trigger `dev.yml`.

- [ ] **Step 3: Observe the security gate failure**

```bash
gh run view --workflow=dev.yml
```

Expected: at least one of `compile`, `unit-tests`, `sast`, `cve-scan`, `secret-detection` shows status `failure`.

- [ ] **Step 4: Verify `promote-to-int` was skipped**

```bash
gh run view --workflow=dev.yml --job=promote-to-int
```

Expected: job status `skipped`.

- [ ] **Step 5: Verify `int` branch is unchanged**

```bash
gh api repos/devinhedge/MPD-secure/git/ref/heads/int --jq '.object.sha'
```

Expected: SHA matches `INT_BASELINE_SHA` recorded in Step 1.

---

## Acceptance Criteria Traceability

| Acceptance Criterion | Verified By |
|---|---|
| `dev.yml` promotion job conditional on all five security gate jobs | Task 4 (BLOCKED), Task 8 (BLOCKED) |
| `dev.yml` promotion job skipped when any gate job fails | Task 9 (BLOCKED) |
| `int.yml` triggers on push to `int` branch | Task 5 |
| `int.yml` full feature Meson build | Task 2 |
| `int.yml` full unit test regression suite | Task 2 |
| Fan-out to all five `test-*` branches on pass | Task 5, Task 7 |
| All five branches receive identical SHA | Task 7 |
| Failed `int.yml` build prevents fan-out | Task 6 |
| Failed `int.yml` regression prevents fan-out | Task 6 (same mechanism: `if: success()` on `build-and-test`) |
