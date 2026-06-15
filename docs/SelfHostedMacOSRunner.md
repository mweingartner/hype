---
type: guide
title: Self-hosted macOS GitHub Actions Runner
description: Setup and maintenance guide for the Hype repository's macOS self-hosted GitHub Actions runner.
updated: 2026-06-15
---

# Self-hosted macOS GitHub Actions Runner

Hype uses a macOS self-hosted runner for GitHub Actions because the project
depends on local Apple tooling that is not guaranteed on GitHub-hosted runners.
The runner should be an Apple Silicon Mac with Xcode beta installed at:

```bash
/Applications/Xcode-beta.app
```

## Provision The Runner

From the repository root:

```bash
scripts/provision_self_hosted_runner_macos.sh
```

The script checks the macOS build dependencies, prepares an unlocked CI
keychain for headless Keychain tests, downloads and verifies the GitHub Actions
runner, registers it to the current GitHub repository, installs it as a launchd
service, starts it, and runs the same logic/CLI/fuzz test gate used by the
local pre-push hook.

If the current `gh` token does not have repository admin access, get a one-time
registration token from GitHub:

1. Open this repository on GitHub.
1. Go to Settings -> Actions -> Runners.
1. Click New self-hosted runner.
1. Select macOS and ARM64.
1. Copy only the token shown in the generated `./config.sh` command.

Then run:

```bash
HYPE_RUNNER_TOKEN="<token-from-github>" scripts/provision_self_hosted_runner_macos.sh
```

The token is short-lived and is not written into the repository.

## Runner Labels

The default labels are:

```text
self-hosted,macOS,ARM64,hype,xcode-beta
```

The workflow in `.github/workflows/self-hosted-macos.yml` targets:

```yaml
runs-on: [self-hosted, macOS, ARM64, hype]
```

## Reboot Behavior

The provisioning script runs:

```bash
./svc.sh install
./svc.sh start
```

On macOS this installs the runner as a launchd service for the current user.
It restarts after reboot once that user session is available. Keep the Mac
awake for CI:

```bash
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
```

Use automatic login only if the physical and network security tradeoff is
acceptable for the machine.

## Keychain Access

The workflow creates a temporary unlocked keychain under `$RUNNER_TEMP` before
running Swift tests. This is required because several Hype tests intentionally
exercise the real `SecItem` API with `kSecAttrAccessibleWhenUnlocked` in a
non-interactive process. The provisioning script creates the same kind of
keychain under the runner directory for local validation.

## Check Status

```bash
cd ~/actions-runner/hype
./svc.sh status
```

The runner should show as Idle in GitHub under Settings -> Actions -> Runners.
