#!/usr/bin/env bash
# Registers this Mac as a self-hosted GitHub Actions runner for the current
# repo and installs it as a launchd service, so the macOS CI job runs here
# for free instead of on GitHub's metered macOS runners. One runner
# instance per repo, under ~/actions-runner/<repo>. Re-run to update.
#
#   scripts/runner.sh            # install + start
#   scripts/runner.sh remove     # stop, uninstall, deregister
set -euo pipefail
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
NAME=${REPO#*/}
DIR="$HOME/actions-runner/$NAME"
ARCH=$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x64)

if [ "${1:-}" = remove ]; then
  cd "$DIR"
  ./svc.sh stop || true; ./svc.sh uninstall || true
  TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/remove-token" --jq .token)
  ./config.sh remove --token "$TOKEN"
  echo "runner removed; delete $DIR when convenient"
  exit 0
fi

command -v xcodegen >/dev/null || { echo "error: xcodegen not installed (brew install xcodegen)." >&2; exit 1; }
VERSION=$(gh api repos/actions/runner/releases/latest --jq .tag_name | tr -d v)
mkdir -p "$DIR" && cd "$DIR"
if [ ! -x ./run.sh ] || [ "$(cat .version 2>/dev/null)" != "$VERSION" ]; then
  echo "downloading actions-runner $VERSION ($ARCH)…"
  curl -sSL -o runner.tgz "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-osx-$ARCH-$VERSION.tar.gz"
  tar xzf runner.tgz && rm runner.tgz && echo "$VERSION" > .version
fi
# Short-lived registration token; never printed.
TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)
./config.sh --unattended --replace --url "https://github.com/$REPO" --token "$TOKEN" \
  --name "$(scutil --get ComputerName | tr ' ' '-')-$NAME" --labels macOS --work _work >/dev/null
# The service inherits this shell's PATH (config.sh writes .path), so
# /opt/homebrew/bin is visible to jobs.
./svc.sh install >/dev/null && ./svc.sh start >/dev/null
echo "runner registered for $REPO and running as a launchd service ($DIR)."
echo "Status: cd $DIR && ./svc.sh status"
