#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if ! command -v nix >/dev/null 2>&1; then
  echo "Run ./bootstrap.sh first (or open a new terminal after installing Nix)." >&2
  exit 1
fi

# Build successfully before changing the running system.
nix build "path:$DIR#darwinConfigurations.mac.system" --out-link "$DIR/result"
sudo "$DIR/result/sw/bin/darwin-rebuild" switch --flake "path:$DIR#mac"

# Install user tools after Brew and Home Manager have finished activation.
# Use the home directory so the caller's project config doesn't affect setup.
(
  cd "$HOME"
  /opt/homebrew/bin/mise install
)
