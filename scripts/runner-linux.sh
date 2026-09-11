#!/usr/bin/env bash
# Registers a Linux box (default: Proxmox LXC 108 "gh-runner" on proxmox01)
# as a self-hosted GitHub Actions runner for the current repo, so the Linux
# CI jobs cost no hosted minutes either. One runner instance per repo,
# under /home/runner/actions-runner-<repo>. Re-run to update.
#
#   scripts/runner-linux.sh            # install + start
#   scripts/runner-linux.sh remove     # stop, uninstall, deregister
#
# RUNNER_SHELL is how to get a root bash on the box, reading the script from
# stdin. This repo's Linux jobs (changes, attribution) need only git, python3
# and gh, all of which LXC 108 already has from the ios-app-template setup.
set -euo pipefail
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
NAME=${REPO#*/}
RUNNER_SHELL=${RUNNER_SHELL:-"ssh rolodex-pve pct exec 108 -- bash -s"}
DIR="/home/runner/actions-runner-$NAME"

if [ "${1:-}" = remove ]; then
  TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/remove-token" --jq .token)
  $RUNNER_SHELL <<REMOTE
set -e; cd "$DIR"
./svc.sh stop || true; ./svc.sh uninstall || true
su runner -c "./config.sh remove --token $TOKEN"
echo "runner removed; delete $DIR when convenient"
REMOTE
  exit 0
fi

VERSION=$(gh api repos/actions/runner/releases/latest --jq .tag_name | tr -d v)
# Short-lived registration token; never printed.
TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)
$RUNNER_SHELL <<REMOTE
set -e; export LC_ALL=C
mkdir -p "$DIR" && cd "$DIR"
if [ ! -x ./run.sh ] || [ "\$(cat .version 2>/dev/null)" != "$VERSION" ]; then
  curl -sSL -o r.tgz "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-linux-x64-$VERSION.tar.gz"
  tar xzf r.tgz && rm r.tgz && echo "$VERSION" > .version
  ./bin/installdependencies.sh >/dev/null 2>&1 || apt-get install -yq "libicu[0-9]*" >/dev/null
fi
chown -R runner:runner "$DIR"
[ -f .runner ] || su runner -c "./config.sh --unattended --replace --url https://github.com/$REPO --token $TOKEN --name \$(hostname)-$NAME --labels Linux --work _work" >/dev/null
./svc.sh install runner >/dev/null 2>&1 || true
./svc.sh start >/dev/null
./svc.sh status | tail -1
REMOTE
echo "runner registered for $REPO as a systemd service ($DIR)."
