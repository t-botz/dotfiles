#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This configuration targets Apple Silicon macOS." >&2
  exit 1
fi
if [[ "$(id -un)" != tibo ]]; then
  echo "Set your username in flake.nix and bootstrap.sh before continuing." >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1 && [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if ! command -v nix >/dev/null 2>&1; then
  installer="$(mktemp -t dotfiles-nix)"
  trap 'rm -f "$installer"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL https://install.determinate.systems/nix -o "$installer"
  sh "$installer" install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

exec "$DIR/rebuild.sh"
