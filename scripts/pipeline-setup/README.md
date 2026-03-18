# Pipeline Setup Scripts

Scripts to establish the branch topology and GitHub Ruleset protection for the
MPD-secure CI/CD pipeline. Run in numeric order. Step 2 is manual.

---

## Prerequisites

- `gh` CLI installed and authenticated as a repository admin for `devinhedge/MPD-secure`
- Sufficient GitHub permissions to create branches, create GitHub Apps, and manage
  repository Rulesets and secrets
- The GitHub App private key saved locally as a `.pem` file (downloaded during step 2)

---

## Step 1: Create pipeline branches

```bash
./01-create-branches.sh
```

Creates the 12 pipeline branches from `main` HEAD:
`dev`, `int`, `test-ubuntu-debian`, `test-fedora-rhel`, `test-arch`, `test-macos`,
`test-windows`, `stage-ubuntu-debian`, `stage-fedora-rhel`, `stage-arch`,
`stage-macos`, `stage-windows`

Safe to re-run — existing branches are skipped.

---

## Step 2: Create and install the GitHub App (manual — GitHub UI)

This step cannot be scripted. You must complete it before running steps 3 and 4.

### 2a. Create the App

1. Go to: https://github.com/settings/apps/new
2. Fill in the fields:
   - **GitHub App name:** `mpd-secure-pipeline`
   - **Homepage URL:** `https://github.com/devinhedge/MPD-secure`
   - **Webhook:** uncheck "Active" (no webhook needed)
3. Set **Repository permissions:**
   - **Contents:** Read and write
   - **Commit statuses:** Read and write
4. Under **Where can this GitHub App be installed?**, select **Only on this account**
5. Click **Create GitHub App**
6. Record the **App ID** shown at the top of the App settings page

### 2b. Generate a private key

On the App settings page, scroll to **Private keys** and click **Generate a private key**.
A `.pem` file downloads automatically. Save it somewhere secure — you will need the path
in step 3.

### 2c. Install the App on the repository

1. On the App settings page, click **Install App** in the left sidebar
2. Click **Install** next to your account
3. Select **Only select repositories** and choose `devinhedge/MPD-secure`
4. Click **Install**

### 2d. Retrieve the installation ID

```bash
gh api /repos/devinhedge/MPD-secure/installation --jq '.id'
```

Record this number. You will pass it to steps 3 and 4.

---

## Step 3: Store App credentials as repository secrets

```bash
./02-store-app-secrets.sh <APP_ID> <INSTALLATION_ID> <path-to-private-key.pem>
```

Example:

```bash
./02-store-app-secrets.sh 123456 78901234 ~/Downloads/mpd-secure-pipeline.2026-03-18.private-key.pem
```

Stores three repository secrets:
- `PIPELINE_APP_ID`
- `PIPELINE_APP_INSTALLATION_ID`
- `PIPELINE_APP_PRIVATE_KEY`

The private key file is read once and never written to stdout.

---

## Step 4: Configure GitHub Rulesets

```bash
./03-configure-rulesets.sh <INSTALLATION_ID>
```

Example:

```bash
./03-configure-rulesets.sh 78901234
```

Applies all 13 Rulesets. Safe to re-run — existing Rulesets are skipped.

**To update the `dev` Ruleset status check context strings** (after US-006-05/06/07
define the final workflow job names):

```bash
./03-configure-rulesets.sh <INSTALLATION_ID> <SAST_JOB_NAME> <CVE_JOB_NAME> <SECRETS_JOB_NAME>
```

The existing `pipeline-dev-protection` Ruleset will be skipped (idempotent). To force
an update, delete the Ruleset manually in the GitHub UI or via
`gh api repos/devinhedge/MPD-secure/rulesets/<id> --method DELETE`, then re-run.

---

## Step 5: Verify

```bash
./04-verify.sh
```

Verifies:
- All 12 pipeline branches exist
- All 13 Rulesets are present
- `dev` Ruleset requires the three security gate checks
- `main` Ruleset requires all five `pipeline/stage-*` checks
- Direct push to `int`, `test-ubuntu-debian`, `stage-ubuntu-debian`, `dev`, and `main`
  is rejected

Exits 0 if all checks pass. Exits 1 and prints a failure summary if any check fails.
This script must exit 0 before the story is considered done.

---

## WARNING

Scripts must be run in numeric order. Step 2 is manual and must complete before
step 3. Running `03-configure-rulesets.sh` without first completing step 2 will
fail because the installation ID argument will be unknown.
